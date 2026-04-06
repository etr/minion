#!/usr/bin/env bash
#
# Tests for lib/minion-run.sh — inline invocation mode.
# Uses a mock pi script to verify argument passing and exit code propagation.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MINION_RUN="$ROOT/lib/minion-run.sh"

PASS=0
FAIL=0

# --- Mock Pi setup ---
MOCK_DIR="$(mktemp -d)"
trap 'rm -rf "$MOCK_DIR"' EXIT

# Mock pi script: echoes received args, supports configurable exit code and stderr
cat > "$MOCK_DIR/pi" <<'MOCKEOF'
#!/usr/bin/env bash
# Echo all arguments so tests can verify what was passed
echo "MOCK_ARGS: $*"
# If MOCK_PI_STDERR is set, write it to stderr
if [ -n "${MOCK_PI_STDERR:-}" ]; then
  echo "$MOCK_PI_STDERR" >&2
fi
# If MOCK_PI_STDOUT is set, write it to stdout (in addition to MOCK_ARGS)
if [ -n "${MOCK_PI_STDOUT:-}" ]; then
  echo "$MOCK_PI_STDOUT"
fi
exit "${MOCK_PI_EXIT_CODE:-0}"
MOCKEOF
chmod +x "$MOCK_DIR/pi"

# Prepend mock dir to PATH so minion-run.sh finds our mock pi
export PATH="$MOCK_DIR:$PATH"

# --- Test helpers ---

check() {
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    FAIL=$((FAIL + 1))
  fi
}

# Run a command, capture stdout+stderr and exit code, then check assertions.
# Usage: run_and_check "description" expected_exit "stdout_contains" "stderr_contains" -- cmd args...
# The command after -- is executed directly (no eval), preserving quoting.
run_and_check() {
  local description="$1"
  local expected_exit="$2"
  local stdout_pattern="$3"
  local stderr_pattern="$4"
  shift 4
  # skip the -- separator
  [ "${1:-}" = "--" ] && shift

  local stdout stderr actual_exit

  set +e
  stdout="$("$@" 2>"$MOCK_DIR/_stderr")"
  actual_exit=$?
  set -e
  stderr="$(cat "$MOCK_DIR/_stderr")"

  local all_pass=true

  if [ "$actual_exit" != "$expected_exit" ]; then
    all_pass=false
  fi

  if [ -n "$stdout_pattern" ]; then
    if ! echo "$stdout" | grep -qF "$stdout_pattern"; then
      all_pass=false
    fi
  fi

  if [ -n "$stderr_pattern" ]; then
    if ! echo "$stderr" | grep -qF "$stderr_pattern"; then
      all_pass=false
    fi
  fi

  if $all_pass; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    if [ "$actual_exit" != "$expected_exit" ]; then
      echo "        exit: expected=$expected_exit actual=$actual_exit"
    fi
    if [ -n "$stdout_pattern" ] && ! echo "$stdout" | grep -qF "$stdout_pattern"; then
      echo "        stdout missing: '$stdout_pattern'"
      echo "        stdout was: '$stdout'"
    fi
    if [ -n "$stderr_pattern" ] && ! echo "$stderr" | grep -qF "$stderr_pattern"; then
      echo "        stderr missing: '$stderr_pattern'"
      echo "        stderr was: '$stderr'"
    fi
    FAIL=$((FAIL + 1))
  fi
}

echo "=== minion-run.sh Tests ==="
echo ""

# --- 1. Script is executable ---
echo "-- Basics --"
check "script is executable" test -x "$MINION_RUN"

# --- 2. Correct Pi command with all three params ---
# The -- sentinel precedes the prompt so Pi never interprets it as a flag.
echo ""
echo "-- Argument passing --"
run_and_check \
  "passes --provider --model and prompt to pi" \
  0 \
  "MOCK_ARGS: --provider openai --model gpt-4 -- hello" \
  "" \
  -- "$MINION_RUN" --provider openai --model gpt-4 --prompt hello

# --- 3. Params in different order ---
run_and_check \
  "params in different order work" \
  0 \
  "MOCK_ARGS: --provider openai --model gpt-4 -- hello" \
  "" \
  -- "$MINION_RUN" --model gpt-4 --prompt hello --provider openai

# --- 4. Prompt with spaces preserved as single arg ---
run_and_check \
  "prompt with spaces preserved as single arg" \
  0 \
  "MOCK_ARGS: --provider openai --model gpt-4 -- hello world how are you" \
  "" \
  -- "$MINION_RUN" --provider openai --model gpt-4 --prompt "hello world how are you"

# --- 5-9. Validation: missing params ---
echo ""
echo "-- Missing parameter validation --"
run_and_check \
  "missing model exits non-zero with 'missing' message containing 'model'" \
  1 \
  "" \
  "model" \
  -- "$MINION_RUN" --provider openai --prompt hello

run_and_check \
  "missing provider exits non-zero with 'missing' message containing 'provider'" \
  1 \
  "" \
  "provider" \
  -- "$MINION_RUN" --model gpt-4 --prompt hello

run_and_check \
  "missing prompt exits non-zero with 'missing' message containing 'prompt'" \
  1 \
  "" \
  "prompt" \
  -- "$MINION_RUN" --provider openai --model gpt-4

run_and_check \
  "no arguments exits non-zero with all three field names" \
  1 \
  "" \
  "missing:" \
  -- "$MINION_RUN"

# Verify provider and model are reported when no args given (on stderr).
# Note: --prompt is no longer required when --claude-skills or --extra-input is present,
# so it is not reported in the missing list at the provider/model gate.
check_no_args_provider_model() {
  local stderr
  set +e
  stderr="$("$MINION_RUN" 2>&1 1>/dev/null)"
  local exit_code=$?
  set -e
  [ "$exit_code" != "0" ] || return 1
  echo "$stderr" | grep -qF "provider" || return 1
  echo "$stderr" | grep -qF "model" || return 1
}
check "no arguments output reports missing provider and model" check_no_args_provider_model

# When provider+model are given but no prompt content, the script still fails with 'missing'
check_no_prompt_content_fails() {
  local stderr exit_code
  set +e
  stderr="$("$MINION_RUN" --provider openai --model gpt-4 2>&1 1>/dev/null)"
  exit_code=$?
  set -e
  [ "$exit_code" != "0" ] || return 1
  echo "$stderr" | grep -qF "missing" || return 1
}
check "provider+model only (no prompt content) exits with missing" check_no_prompt_content_fails

# --- 10-12. Exit code propagation ---
echo ""
echo "-- Exit code propagation --"
run_and_check \
  "pi exit 0 -> script exits 0" \
  0 \
  "MOCK_ARGS:" \
  "" \
  -- env MOCK_PI_EXIT_CODE=0 "$MINION_RUN" --provider openai --model gpt-4 --prompt hello

run_and_check \
  "pi exit 1 -> script exits 1" \
  1 \
  "" \
  "" \
  -- env MOCK_PI_EXIT_CODE=1 "$MINION_RUN" --provider openai --model gpt-4 --prompt hello

run_and_check \
  "pi exit 127 -> script exits 127" \
  127 \
  "" \
  "" \
  -- env MOCK_PI_EXIT_CODE=127 "$MINION_RUN" --provider openai --model gpt-4 --prompt hello

# --- 13. Pi stdout passed through ---
echo ""
echo "-- Output passthrough --"
run_and_check \
  "pi stdout passed through on success" \
  0 \
  "delegation complete" \
  "" \
  -- env MOCK_PI_STDOUT="delegation complete" "$MINION_RUN" --provider openai --model gpt-4 --prompt hello

# --- 14. Pi stderr passed through on failure ---
run_and_check \
  "pi stderr passed through on failure" \
  1 \
  "" \
  "something went wrong" \
  -- env MOCK_PI_EXIT_CODE=1 MOCK_PI_STDERR="something went wrong" "$MINION_RUN" --provider openai --model gpt-4 --prompt hello

# --- 15. Flag with no value ---
echo ""
echo "-- Flag with missing value --"
run_and_check \
  "flag with no value exits 2 with error on stderr" \
  2 \
  "" \
  "missing value for --provider" \
  -- "$MINION_RUN" --provider

# --- 16. Unknown flag ---
echo ""
echo "-- Unknown flags --"
run_and_check \
  "unknown flag exits 2 with error on stderr" \
  2 \
  "" \
  "unknown" \
  -- "$MINION_RUN" --provider openai --model gpt-4 --prompt hello --bogus-flag

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  echo "TESTS FAILED"
  exit 1
else
  echo "ALL TESTS PASSED"
  exit 0
fi
