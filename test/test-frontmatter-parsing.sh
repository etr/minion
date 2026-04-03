#!/usr/bin/env bash
#
# Tests for lib/minion-run.sh — file mode: frontmatter parsing and Pi flag mapping.
# Uses a mock pi script to verify argument parsing from minion files.
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
# Usage: create_minion_file "content"
# Returns the path to the created file via stdout
create_minion_file() {
  local content="$1"
  local path="$MOCK_DIR/test-minion-$((RANDOM)).md"
  printf '%s\n' "$content" > "$path"
  echo "$path"
}

echo "=== Frontmatter Parsing Tests ==="
echo ""

# ============================================================
# Phase 1: Mode switching (--file flag)
# ============================================================
echo "-- Mode switching --"

# Test: --file flag accepted with minimal valid minion file
MINFILE="$(create_minion_file "---
provider: openai
model: gpt-4
---
Do the thing")"

run_and_check \
  "--file with valid minion file exits 0" \
  0 \
  "MOCK_ARGS:" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE"

# Test: --file and --provider are mutually exclusive
run_and_check \
  "--file and --provider mutually exclusive exits 2" \
  2 \
  "" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE" --provider openai

# Test: --file with nonexistent path
run_and_check \
  "--file with nonexistent path exits non-zero" \
  1 \
  "" \
  "" \
  -- "$MINION_RUN" --file "/tmp/does-not-exist-$RANDOM.md"

# Test: inline mode still works (regression)
run_and_check \
  "inline mode still works" \
  0 \
  "MOCK_ARGS: --provider openai --model gpt-4 hello" \
  "" \
  -- "$MINION_RUN" --provider openai --model gpt-4 --prompt hello

# ============================================================
# Phase 2: String field parsing
# ============================================================
echo ""
echo "-- String field parsing --"

# Test: provider and model from frontmatter map to pi flags
MINFILE2="$(create_minion_file "---
provider: anthropic
model: claude-3-opus
---
Review this code")"

run_and_check \
  "provider and model map to pi flags" \
  0 \
  "MOCK_ARGS: --provider anthropic --model claude-3-opus Review this code" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE2"

# Test: optional string fields: thinking, tools, max-turns, append-system-prompt
MINFILE3="$(create_minion_file "---
provider: openai
model: gpt-4
thinking: extended
tools: bash,read
max-turns: 5
append-system-prompt: Be concise
---
Do analysis")"

run_and_check \
  "optional string field: thinking" \
  0 \
  "--thinking extended" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE3"

run_and_check \
  "optional string field: tools" \
  0 \
  "--tools bash,read" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE3"

run_and_check \
  "optional string field: max-turns" \
  0 \
  "--max-turns 5" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE3"

run_and_check \
  "optional string field: append-system-prompt" \
  0 \
  "--append-system-prompt Be concise" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE3"

# Test: body with multiple lines preserved
MINFILE4="$(create_minion_file "---
provider: openai
model: gpt-4
---
Line one
Line two
Line three")"

# Check that multi-line body is captured (all lines in single prompt arg)
run_and_check \
  "multi-line body preserved" \
  0 \
  "Line one" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE4"

# ============================================================
# Phase 3: Boolean fields
# ============================================================
echo ""
echo "-- Boolean fields --"

# Test: no-tools: true emits --no-tools
MINFILE_BOOL1="$(create_minion_file "---
provider: openai
model: gpt-4
no-tools: true
---
Do stuff")"

run_and_check \
  "no-tools: true emits --no-tools" \
  0 \
  "--no-tools" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_BOOL1"

# Test: no-tools: false omits --no-tools
MINFILE_BOOL2="$(create_minion_file "---
provider: openai
model: gpt-4
no-tools: false
---
Do stuff")"

# We need a custom check: --no-tools should NOT appear
check_no_tools_absent() {
  local stdout
  set +e
  stdout="$("$MINION_RUN" --file "$MINFILE_BOOL2" 2>/dev/null)"
  local rc=$?
  set -e
  [ "$rc" = "0" ] || return 1
  # --no-tools should NOT be in the output
  if echo "$stdout" | grep -qF -- "--no-tools"; then
    return 1
  fi
  return 0
}
check "no-tools: false omits --no-tools" check_no_tools_absent

# Test: all three booleans when true
MINFILE_BOOL3="$(create_minion_file "---
provider: openai
model: gpt-4
no-tools: true
no-session: true
stream: true
---
Do stuff")"

run_and_check \
  "all booleans true: --no-tools present" \
  0 \
  "--no-tools" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_BOOL3"

run_and_check \
  "all booleans true: --no-session present" \
  0 \
  "--no-session" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_BOOL3"

run_and_check \
  "all booleans true: --stream present" \
  0 \
  "--stream" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_BOOL3"

# ============================================================
# Phase 4: List fields
# ============================================================
echo ""
echo "-- List fields --"

# Test: single extension
MINFILE_LIST1="$(create_minion_file "---
provider: openai
model: gpt-4
extensions:
  - github-mcp
---
Do stuff")"

run_and_check \
  "single extension emits -e flag" \
  0 \
  "-e github-mcp" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_LIST1"

# Test: three extensions
MINFILE_LIST2="$(create_minion_file "---
provider: openai
model: gpt-4
extensions:
  - github-mcp
  - jira-mcp
  - slack-mcp
---
Do stuff")"

run_and_check \
  "three extensions emit -e per entry" \
  0 \
  "-e github-mcp -e jira-mcp -e slack-mcp" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_LIST2"

# Test: skills list
MINFILE_LIST3="$(create_minion_file "---
provider: openai
model: gpt-4
skills:
  - code-review
  - testing
---
Do stuff")"

run_and_check \
  "skills list emits --skill per entry" \
  0 \
  "--skill code-review --skill testing" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_LIST3"

# Test: empty extensions (just the key, no items) -> no -e flags
MINFILE_LIST4="$(create_minion_file "---
provider: openai
model: gpt-4
extensions:
---
Do stuff")"

check_no_ext_flags() {
  local stdout
  set +e
  stdout="$("$MINION_RUN" --file "$MINFILE_LIST4" 2>/dev/null)"
  local rc=$?
  set -e
  [ "$rc" = "0" ] || return 1
  if echo "$stdout" | grep -qF -- " -e "; then
    return 1
  fi
  return 0
}
check "empty extensions list emits no -e flags" check_no_ext_flags

# ============================================================
# Phase 5: Validation & Edge Cases
# ============================================================
echo ""
echo "-- Validation & edge cases --"

# Test: missing provider exits 1 with "missing: provider"
MINFILE_VAL1="$(create_minion_file "---
model: gpt-4
---
Do stuff")"

run_and_check \
  "missing provider exits 1 with message" \
  1 \
  "missing: provider" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_VAL1"

# Test: missing model
MINFILE_VAL2="$(create_minion_file "---
provider: openai
---
Do stuff")"

run_and_check \
  "missing model exits 1 with message" \
  1 \
  "missing: model" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_VAL2"

# Test: missing both
MINFILE_VAL3="$(create_minion_file "---
---
Do stuff")"

run_and_check \
  "missing both exits 1 with both names" \
  1 \
  "missing: provider, model" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_VAL3"

# Test: exit code passthrough in file mode
MINFILE_EXIT="$(create_minion_file "---
provider: openai
model: gpt-4
---
Do stuff")"

run_and_check \
  "file mode: pi exit 42 -> script exits 42" \
  42 \
  "" \
  "" \
  -- env MOCK_PI_EXIT_CODE=42 "$MINION_RUN" --file "$MINFILE_EXIT"

# ============================================================
# Phase 6: Comprehensive test with ALL field types
# ============================================================
echo ""
echo "-- Comprehensive --"

MINFILE_ALL="$(create_minion_file "---
provider: anthropic
model: claude-3-opus
thinking: extended
tools: bash,read,write
max-turns: 10
append-system-prompt: You are a security expert
no-tools: true
no-session: true
stream: true
extensions:
  - github-mcp
  - jira-mcp
skills:
  - code-review
---
Analyze the repository for vulnerabilities")"

run_and_check \
  "comprehensive: provider" \
  0 \
  "--provider anthropic" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_ALL"

run_and_check \
  "comprehensive: model" \
  0 \
  "--model claude-3-opus" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_ALL"

run_and_check \
  "comprehensive: thinking" \
  0 \
  "--thinking extended" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_ALL"

run_and_check \
  "comprehensive: tools" \
  0 \
  "--tools bash,read,write" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_ALL"

run_and_check \
  "comprehensive: max-turns" \
  0 \
  "--max-turns 10" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_ALL"

run_and_check \
  "comprehensive: append-system-prompt" \
  0 \
  "--append-system-prompt You are a security expert" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_ALL"

run_and_check \
  "comprehensive: no-tools" \
  0 \
  "--no-tools" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_ALL"

run_and_check \
  "comprehensive: no-session" \
  0 \
  "--no-session" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_ALL"

run_and_check \
  "comprehensive: stream" \
  0 \
  "--stream" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_ALL"

run_and_check \
  "comprehensive: extensions" \
  0 \
  "-e github-mcp -e jira-mcp" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_ALL"

run_and_check \
  "comprehensive: skills" \
  0 \
  "--skill code-review" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_ALL"

run_and_check \
  "comprehensive: body as prompt" \
  0 \
  "Analyze the repository for vulnerabilities" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_ALL"

# ============================================================
# Phase 7: Edge cases
# ============================================================
echo ""
echo "-- Edge cases --"

# Test: body with special characters preserved
MINFILE_SPECIAL="$(create_minion_file "---
provider: openai
model: gpt-4
---
Check if \$HOME is set and run: ls -la /tmp/*.log")"

run_and_check \
  "body with special characters preserved" \
  0 \
  'Check if $HOME is set' \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_SPECIAL"

# Test: file with no body (only frontmatter) - prompt is empty, should still work
MINFILE_NOBODY="$(create_minion_file "---
provider: openai
model: gpt-4
---")"

run_and_check \
  "file with no body exits 0" \
  0 \
  "MOCK_ARGS:" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_NOBODY"

# Verify the prompt is NOT passed when body is empty
check_no_prompt_arg() {
  local stdout
  set +e
  stdout="$("$MINION_RUN" --file "$MINFILE_NOBODY" 2>/dev/null)"
  local rc=$?
  set -e
  [ "$rc" = "0" ] || return 1
  # Should just be "MOCK_ARGS: --provider openai --model gpt-4" with nothing after
  echo "$stdout" | grep -qF "MOCK_ARGS: --provider openai --model gpt-4" || return 1
  # Ensure nothing extra after model
  local expected="MOCK_ARGS: --provider openai --model gpt-4"
  [ "$(echo "$stdout" | head -1)" = "$expected" ] || return 1
  return 0
}
check "file with no body does not pass empty prompt arg" check_no_prompt_arg

# Test: --file with missing value
run_and_check \
  "--file with missing value exits 2" \
  2 \
  "" \
  "missing value for --file" \
  -- "$MINION_RUN" --file

# Test: boolean absent (not in frontmatter) omits flag
MINFILE_NOBOOL="$(create_minion_file "---
provider: openai
model: gpt-4
---
Do stuff")"

check_absent_booleans() {
  local stdout
  set +e
  stdout="$("$MINION_RUN" --file "$MINFILE_NOBOOL" 2>/dev/null)"
  local rc=$?
  set -e
  [ "$rc" = "0" ] || return 1
  # None of the boolean flags should appear
  echo "$stdout" | grep -qF -- "--no-tools" && return 1
  echo "$stdout" | grep -qF -- "--no-session" && return 1
  echo "$stdout" | grep -qF -- "--stream" && return 1
  return 0
}
check "absent booleans omit all boolean flags" check_absent_booleans

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
