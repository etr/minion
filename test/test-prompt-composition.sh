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

# Mock pi script: echoes received args + stdin (the prompt is now delivered via stdin).
# Format: "MOCK_ARGS: <flags> | STDIN: <prompt>" when stdin is non-empty,
#         "MOCK_ARGS: <flags>" otherwise.
cat > "$MOCK_DIR/pi" <<'MOCKEOF'
#!/usr/bin/env bash
STDIN_CONTENT=""
if [ ! -t 0 ]; then
  STDIN_CONTENT="$(cat)"
fi
if [ -n "$STDIN_CONTENT" ]; then
  echo "MOCK_ARGS: $* | STDIN: $STDIN_CONTENT"
else
  echo "MOCK_ARGS: $*"
fi
if [ -n "${MOCK_PI_STDERR:-}" ]; then
  echo "$MOCK_PI_STDERR" >&2
fi
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
# Phase 1: --extra-input with --file uses caching-friendly layout
# ============================================================
# Fix A: when running in file mode with extra-input, the stable file body
# is routed through --append-system-prompt so it becomes part of the
# provider-cached prefix; the variable extra-input is piped via stdin as
# the user message. This maximises prompt-cache hit rates on providers
# that honour cache_control breakpoints.
echo "-- Prompt composition (caching layout) --"

MINFILE_COMPOSE="$(create_minion_file "---
provider: openai
model: gpt-4
---
Base prompt here")"

# 1. Caching layout: body → --append-system-prompt, extra-input → stdin
check_caching_layout_file_extra() {
  local stdout
  set +e
  stdout="$("$MINION_RUN" --file "$MINFILE_COMPOSE" --extra-input "review auth.py" 2>/dev/null)"
  local rc=$?
  set -e
  [ "$rc" = "0" ] || { echo "        rc=$rc"; return 1; }
  # Body must be in the --append-system-prompt arg
  echo "$stdout" | grep -qF -- "--append-system-prompt Base prompt here" \
    || { echo "        body not routed through --append-system-prompt"; return 1; }
  # Extra-input must be the stdin (user message)
  echo "$stdout" | grep -qF "STDIN: review auth.py" \
    || { echo "        extra-input not delivered via stdin"; return 1; }
  # Body must NOT appear in the STDIN portion
  if echo "$stdout" | sed -n 's/.* | STDIN: //p' | grep -qF "Base prompt here"; then
    echo "        body leaked into stdin (expected only in --append-system-prompt)"
    return 1
  fi
  return 0
}
check "file mode + extra-input uses caching layout (body in append-sys, extra in stdin)" check_caching_layout_file_extra

# 1b. Existing append-system-prompt is preserved: file body is appended to it,
# not overwritten, so caller-supplied append-system-prompt still takes effect.
MINFILE_COMPOSE_WITH_APPEND="$(create_minion_file "---
provider: openai
model: gpt-4
append-system-prompt: Be concise.
---
Base prompt here")"

check_caching_layout_merges_append_sys() {
  local stdout
  set +e
  stdout="$("$MINION_RUN" --file "$MINFILE_COMPOSE_WITH_APPEND" --extra-input "review auth.py" 2>/dev/null)"
  local rc=$?
  set -e
  [ "$rc" = "0" ] || return 1
  # Both the file's append-system-prompt AND the body must be in the merged value
  echo "$stdout" | grep -qF "Be concise." || { echo "        existing append-sys lost"; return 1; }
  echo "$stdout" | grep -qF "Base prompt here" || { echo "        body missing from merged append-sys"; return 1; }
  # Extra-input is still the stdin
  echo "$stdout" | grep -qF "STDIN: review auth.py" || return 1
  return 0
}
check "caching layout merges file body into existing append-system-prompt" check_caching_layout_merges_append_sys

# ============================================================
# Phase 2: --file without --extra-input uses caching layout with trigger
# ============================================================
# Even without extra-input, file mode uses the caching layout: body goes
# to --append-system-prompt and a stable "Begin." trigger is used as the
# user message (stdin). This ensures repeated no-extra-input invocations
# of the same minion hit the prompt cache (system + body + trigger are
# all stable), and avoids pi's empty-initialMessage / whitespace-filter
# edge cases that would otherwise drop the model call.

MINFILE_NOEXTRA="$(create_minion_file "---
provider: openai
model: gpt-4
---
Base prompt only")"

check_caching_layout_file_no_extra() {
  local stdout
  set +e
  stdout="$("$MINION_RUN" --file "$MINFILE_NOEXTRA" 2>/dev/null)"
  local rc=$?
  set -e
  [ "$rc" = "0" ] || { echo "        rc=$rc"; return 1; }
  # Body routed through --append-system-prompt
  echo "$stdout" | grep -qF -- "--append-system-prompt Base prompt only" \
    || { echo "        body not routed through --append-system-prompt"; return 1; }
  # Stable trigger is the user message
  echo "$stdout" | grep -qF "STDIN: Begin." \
    || { echo "        trigger not delivered via stdin"; return 1; }
  # Body must not leak into stdin
  if echo "$stdout" | sed -n 's/.* | STDIN: //p' | grep -qF "Base prompt only"; then
    echo "        body leaked into stdin"
    return 1
  fi
  return 0
}
check "file mode without extra-input uses caching layout + stable trigger" check_caching_layout_file_no_extra

# ============================================================
# Phase 3: --extra-input is now permitted in inline mode (FEATURE-claude-skills)
# ============================================================
echo ""
echo "-- Inline mode + extra-input --"

# 3. inline mode supports --extra-input — it appends after --prompt
run_and_check \
  "inline mode --provider/--model/--prompt + --extra-input works" \
  0 \
  "MOCK_ARGS:" \
  "" \
  -- "$MINION_RUN" --provider openai --model gpt-4 --prompt hello --extra-input "extra"

# Verify content composition: prompt and extra-input both end up in the prompt arg
check_extra_inline_compose() {
  local stdout
  set +e
  stdout="$("$MINION_RUN" --provider openai --model gpt-4 --prompt "BASE" --extra-input "EXTRA" 2>/dev/null)"
  local rc=$?
  set -e
  [ "$rc" = "0" ] || return 1
  echo "$stdout" | grep -qF "BASE" || return 1
  echo "$stdout" | grep -qF "EXTRA" || return 1
}
check "inline mode composes --prompt and --extra-input" check_extra_inline_compose

# ============================================================
# Phase 5: --extra-input with empty string is treated like absent
# ============================================================
echo ""
echo "-- Edge cases --"

MINFILE_EMPTY_EXTRA="$(create_minion_file "---
provider: openai
model: gpt-4
---
Base prompt unchanged")"

# 5. Empty --extra-input: same behaviour as no --extra-input at all — caching
# layout activates with the stable "Begin." trigger as the user message.
check_empty_extra_input_uses_caching_layout() {
  local stdout
  set +e
  stdout="$("$MINION_RUN" --file "$MINFILE_EMPTY_EXTRA" --extra-input "" 2>/dev/null)"
  local rc=$?
  set -e
  [ "$rc" = "0" ] || { echo "        rc=$rc"; return 1; }
  echo "$stdout" | grep -qF -- "--append-system-prompt Base prompt unchanged" \
    || { echo "        body not routed through --append-system-prompt"; return 1; }
  echo "$stdout" | grep -qF "STDIN: Begin." \
    || { echo "        trigger not delivered via stdin"; return 1; }
  return 0
}
check "empty --extra-input uses caching layout + stable trigger" check_empty_extra_input_uses_caching_layout

# ============================================================
# Phase 6: --extra-input with missing value exits 2
# ============================================================

# 6. --extra-input at end of args with no following value
MINFILE_MISSINGVAL="$(create_minion_file "---
provider: openai
model: gpt-4
---
Some prompt")"

run_and_check \
  "--extra-input with missing value exits 2" \
  2 \
  "" \
  "missing value for --extra-input" \
  -- "$MINION_RUN" --file "$MINFILE_MISSINGVAL" --extra-input

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

# 8b. SKILL.md references --extra-input
check_skill_extra_input() {
  grep -q '\-\-extra-input' "$ROOT/skills/delegate-to-minion/SKILL.md"
}
check "SKILL.md references --extra-input" check_skill_extra_input

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
