#!/usr/bin/env bash
#
# Tests for lib/minion-run.sh — prompt composition via --extra-input.
# Verifies that caller-provided extra input is combined with minion file body.
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
run_and_check() {
  local description="$1"
  local expected_exit="$2"
  local stdout_pattern="$3"
  local stderr_pattern="$4"
  shift 4
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
    if ! echo "$stdout" | grep -qF -- "$stdout_pattern"; then
      all_pass=false
    fi
  fi

  if [ -n "$stderr_pattern" ]; then
    if ! echo "$stderr" | grep -qF -- "$stderr_pattern"; then
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
    if [ -n "$stdout_pattern" ] && ! echo "$stdout" | grep -qF -- "$stdout_pattern"; then
      echo "        stdout missing: '$stdout_pattern'"
      echo "        stdout was: '$stdout'"
    fi
    if [ -n "$stderr_pattern" ] && ! echo "$stderr" | grep -qF -- "$stderr_pattern"; then
      echo "        stderr missing: '$stderr_pattern'"
      echo "        stderr was: '$stderr'"
    fi
    FAIL=$((FAIL + 1))
  fi
}

# Helper to create a minion file with given content
create_minion_file() {
  local content="$1"
  local path="$MOCK_DIR/test-minion-$((RANDOM)).md"
  printf '%s\n' "$content" > "$path"
  echo "$path"
}

echo "=== Prompt Composition Tests ==="
echo ""

# ============================================================
# Phase 1: --extra-input with --file composes prompt correctly
# ============================================================
echo "-- Prompt composition --"

MINFILE_COMPOSE="$(create_minion_file "---
provider: openai
model: gpt-4
---
Base prompt here")"

# 1. extra-input appended to body with double newline separator
run_and_check \
  "--extra-input with --file composes body + newline + extra" \
  0 \
  "Base prompt here

review auth.py" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_COMPOSE" --extra-input "review auth.py"

# ============================================================
# Phase 2: --file without --extra-input uses body as-is
# ============================================================

MINFILE_NOEXTRA="$(create_minion_file "---
provider: openai
model: gpt-4
---
Base prompt only")"

# 2. No extra-input: body passed alone
run_and_check \
  "--file without --extra-input uses body as-is" \
  0 \
  "MOCK_ARGS: --provider openai --model gpt-4 Base prompt only" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_NOEXTRA"

# ============================================================
# Phase 3: --extra-input without --file is an error
# ============================================================
echo ""
echo "-- Validation --"

# 3. extra-input requires --file
run_and_check \
  "--extra-input without --file exits 2" \
  2 \
  "" \
  "--extra-input requires --file" \
  -- "$MINION_RUN" --extra-input "some text"

# ============================================================
# Phase 4: --extra-input with inline mode flags is a conflict
# ============================================================

# 4. extra-input conflicts with inline mode flags
run_and_check \
  "--extra-input with inline flags exits 2 (conflict)" \
  2 \
  "" \
  "--extra-input requires --file" \
  -- "$MINION_RUN" --provider openai --model gpt-4 --prompt hello --extra-input "extra"

# ============================================================
# Phase 5: --extra-input with empty string uses body as-is
# ============================================================
echo ""
echo "-- Edge cases --"

MINFILE_EMPTY_EXTRA="$(create_minion_file "---
provider: openai
model: gpt-4
---
Base prompt unchanged")"

# 5. Empty --extra-input treated as absent
run_and_check \
  "--extra-input with empty string uses body as-is" \
  0 \
  "MOCK_ARGS: --provider openai --model gpt-4 Base prompt unchanged" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_EMPTY_EXTRA" --extra-input ""

# ============================================================
# Phase 6: --extra-input with missing value exits 2
# ============================================================

# 6. --extra-input at end of args with no following value
run_and_check \
  "--extra-input with missing value exits 2" \
  2 \
  "" \
  "missing value for --extra-input" \
  -- "$MINION_RUN" --file /dev/null --extra-input

# ============================================================
# Phase 7: --extra-input with special characters preserved
# ============================================================

MINFILE_SPECIAL="$(create_minion_file "---
provider: openai
model: gpt-4
---
Check this")"

# 7. Special characters pass through
run_and_check \
  "--extra-input with special characters preserved" \
  0 \
  'review $HOME and `ls`' \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_SPECIAL" --extra-input 'review $HOME and `ls`'

# ============================================================
# Phase 8: Structural checks on SKILL.md and COMMAND.md
# ============================================================
echo ""
echo "-- Structural checks --"

# 8a. SKILL.md has no TASK-007 TODO
check_no_task007_todo() {
  ! grep -q 'TODO (TASK-007)' "$ROOT/skills/delegate-to-minion/SKILL.md"
}
check "SKILL.md has no TASK-007 TODO" check_no_task007_todo

# 8b. SKILL.md references --extra-input
check_skill_extra_input() {
  grep -q '\-\-extra-input' "$ROOT/skills/delegate-to-minion/SKILL.md"
}
check "SKILL.md references --extra-input" check_skill_extra_input

# 8c. SKILL.md has no TASK-006 TODO
check_no_task006_todo() {
  ! grep -q 'TODO (TASK-006)' "$ROOT/skills/delegate-to-minion/SKILL.md"
}
check "SKILL.md has no TASK-006 TODO" check_no_task006_todo

# 8d. COMMAND.md has Usage Examples section
check_command_examples() {
  grep -q 'Usage Examples' "$ROOT/commands/minion/COMMAND.md"
}
check "COMMAND.md has Usage Examples section" check_command_examples

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
