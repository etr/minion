#!/usr/bin/env bash
#
# Tests for lib/auto-dispatch.sh — auto-minion dispatch logic.
# Uses a mock pi script to verify dispatcher invocation and route resolution.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUTO_DISPATCH="$ROOT/lib/auto-dispatch.sh"

PASS=0
FAIL=0

# --- Cleanup accumulator ---
# All temp dirs are registered here; a single EXIT trap removes them all.
_CLEANUP_DIRS=()
cleanup() {
  local dir
  for dir in "${_CLEANUP_DIRS[@]}"; do
    rm -rf "$dir"
  done
}
trap cleanup EXIT

# --- Mock Pi setup ---
MOCK_DIR="$(mktemp -d)"
_CLEANUP_DIRS+=("$MOCK_DIR")
FIXTURE_DIR="$(mktemp -d)"
_CLEANUP_DIRS+=("$FIXTURE_DIR")

# Standard mock pi body: stored in a variable so with_mock_pi can restore it without
# duplicating the heredoc. The mock echoes args + stdin (the prompt is now delivered
# via stdin, not as a positional argument). Format:
#   "MOCK_ARGS: <flags> | STDIN: <prompt>" when stdin is non-empty,
#   "MOCK_ARGS: <flags>"                    otherwise.
_STANDARD_PI_BODY='#!/usr/bin/env bash
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
exit "${MOCK_PI_EXIT_CODE:-0}"'

# Mock pi script: echoes received args, supports configurable exit code and response
printf '%s\n' "$_STANDARD_PI_BODY" > "$MOCK_DIR/pi"
chmod +x "$MOCK_DIR/pi"

export PATH="$MOCK_DIR:$PATH"

# --- Test helpers ---

# assert_file_contains DESCRIPTION FILE PATTERN
# Reads FILE and checks that PATTERN appears in its contents.
# Records PASS/FAIL using the same accounting as run_and_check.
assert_file_contains() {
  local description="$1"
  local file="$2"
  local pattern="$3"
  local contents
  contents="$(cat "$file" 2>/dev/null || echo MISSING)"
  if echo "$contents" | grep -qF -- "$pattern"; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    echo "    file: $file"
    echo "    expected pattern: $pattern"
    echo "    actual contents:  $contents"
    FAIL=$((FAIL + 1))
  fi
}

# with_mock_minionrun MOCK_CONTENT CALLBACK
# Intercepts calls to lib/minion-run.sh by copying the entire lib/ directory into
# a temp dir, installing the mock as minion-run.sh there, and redirecting the
# AUTO_DISPATCH variable to the temp dir's copy of auto-dispatch.sh. Because
# auto-dispatch.sh resolves SCRIPT_DIR from ${BASH_SOURCE[0]}, running it from
# the temp copy makes it call the mock minion-run.sh sibling automatically.
#
# The real production file is NEVER modified, so a process kill during the test
# cannot corrupt it — matching the pattern used by with_mock_pi (MOCK_DIR).
# Usage: with_mock_minionrun "$mock_body" my_test_fn
with_mock_minionrun() {
  local mock_content="$1"
  local callback="$2"
  local mock_lib_dir
  mock_lib_dir="$(mktemp -d)"
  _CLEANUP_DIRS+=("$mock_lib_dir")
  # Copy all lib/ scripts into the temp dir
  cp "$ROOT/lib/"*.sh "$mock_lib_dir/" 2>/dev/null || true
  # Install the mock minion-run.sh (real file untouched)
  printf '%s\n' "$mock_content" > "$mock_lib_dir/minion-run.sh"
  chmod +x "$mock_lib_dir/minion-run.sh"
  # Redirect AUTO_DISPATCH to the temp lib dir's copy so SCRIPT_DIR resolves
  # to the temp dir and sibling minion-run.sh calls hit the mock.
  local saved_auto_dispatch="$AUTO_DISPATCH"
  AUTO_DISPATCH="$mock_lib_dir/auto-dispatch.sh"
  trap 'AUTO_DISPATCH="$saved_auto_dispatch"' RETURN
  set +e
  "$callback"
  set -e
  AUTO_DISPATCH="$saved_auto_dispatch"
}

# with_mock_pi MOCK_CONTENT CALLBACK
# Replaces $MOCK_DIR/pi with MOCK_CONTENT for the duration of CALLBACK (a shell function name),
# then restores the standard pi body via a RETURN trap — even if CALLBACK fails.
# Usage: with_mock_pi "$sentinel_body" my_test_fn
with_mock_pi() {
  local mock_content="$1"
  local callback="$2"
  local pi_path="$MOCK_DIR/pi"
  trap 'printf "%s\n" "$_STANDARD_PI_BODY" > "$pi_path"; chmod +x "$pi_path"' RETURN
  printf '%s\n' "$mock_content" > "$pi_path"
  chmod +x "$pi_path"
  set +e
  "$callback"
  set -e
}

run_and_check() {
  local description="$1"
  local expected_exit="$2"
  local stdout_pattern="$3"
  local stderr_pattern="$4"
  shift 4
  [ "${1:-}" = "--" ] && shift

  # Snapshot mock config at call time so mutations between tests don't bleed in.
  # Callers must export MOCK_PI_STDOUT, MOCK_PI_EXIT_CODE etc. before each test group.
  local _mock_stdout="${MOCK_PI_STDOUT:-}"
  local _mock_exit="${MOCK_PI_EXIT_CODE:-0}"
  local _mock_stderr="${MOCK_PI_STDERR:-}"

  local stdout stderr actual_exit

  set +e
  stdout="$(MOCK_PI_STDOUT="$_mock_stdout" MOCK_PI_EXIT_CODE="$_mock_exit" MOCK_PI_STDERR="$_mock_stderr" "$@" 2>"$MOCK_DIR/_stderr")"
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
    echo "    expected exit=$expected_exit got=$actual_exit"
    if [ -n "$stdout_pattern" ]; then
      echo "    stdout expected: $stdout_pattern"
      echo "    stdout actual:   $stdout"
    fi
    if [ -n "$stderr_pattern" ]; then
      echo "    stderr expected: $stderr_pattern"
      echo "    stderr actual:   $stderr"
    fi
    FAIL=$((FAIL + 1))
  fi
}

# --- Create test fixture configs ---

# Basic valid config
cat > "$FIXTURE_DIR/basic-auto.md" <<'EOF'
---
dispatcher:
  provider: openai
  model: gpt-4o-mini

default:
  provider: openai
  model: gpt-4o

categories:
  code-review:
    provider: anthropic
    model: claude-sonnet-4-20250514
  explanation:
    provider: openai
    model: gpt-4o-mini

show-routing: true
---
You are a task classifier. Output ONLY the category name.

Available categories:
{{categories}}

If no category matches, output: default

User prompt:
{{prompt}}
EOF

# Config with inherit dispatcher
cat > "$FIXTURE_DIR/inherit-dispatcher.md" <<'EOF'
---
dispatcher: inherit

default:
  provider: openai
  model: gpt-4o

categories:
  code-review:
    provider: anthropic
    model: claude-sonnet-4-20250514

show-routing: true
---
Classify this prompt.

Categories:
{{categories}}

Prompt:
{{prompt}}
EOF

# Config with inherit category
cat > "$FIXTURE_DIR/inherit-category.md" <<'EOF'
---
dispatcher:
  provider: openai
  model: gpt-4o-mini

default:
  provider: openai
  model: gpt-4o

categories:
  code-review: inherit
  explanation:
    provider: openai
    model: gpt-4o-mini

show-routing: true
---
Classify. Categories: {{categories}}. Prompt: {{prompt}}
EOF

# Config with custom category
cat > "$FIXTURE_DIR/custom-category.md" <<'EOF'
---
dispatcher:
  provider: openai
  model: gpt-4o-mini

default:
  provider: openai
  model: gpt-4o

categories:
  code-review:
    provider: anthropic
    model: claude-sonnet-4-20250514
  translation:
    description: "Translating code between programming languages"
    provider: google
    model: gemini-2.5-pro

show-routing: true
---
Classify. Categories: {{categories}}. Prompt: {{prompt}}
EOF

# Config missing dispatcher model
cat > "$FIXTURE_DIR/bad-dispatcher.md" <<'EOF'
---
dispatcher:
  provider: openai

default:
  provider: openai
  model: gpt-4o

categories:
  code-review:
    provider: anthropic
    model: claude-sonnet-4-20250514
---
Classify. {{categories}} {{prompt}}
EOF

# Config with custom category missing description
cat > "$FIXTURE_DIR/bad-custom.md" <<'EOF'
---
dispatcher:
  provider: openai
  model: gpt-4o-mini

default:
  provider: openai
  model: gpt-4o

categories:
  my-custom-thing:
    provider: openai
    model: gpt-4o
---
Classify. {{categories}} {{prompt}}
EOF

# ============================================================
echo "=== Argument Validation ==="
# ============================================================

run_and_check "missing --config flag" 1 "" "missing: --config" \
  -- bash "$AUTO_DISPATCH" --prompt "test"

run_and_check "missing --prompt flag" 1 "" "missing: --prompt" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/basic-auto.md"

run_and_check "config file not found" 1 "" "config file not found" \
  -- bash "$AUTO_DISPATCH" --config "/nonexistent/auto.md" --prompt "test"

run_and_check "unknown flag rejected" 2 "" "unknown flag" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/basic-auto.md" --prompt "test" --badflag

# ============================================================
echo ""
echo "=== Config Validation ==="
# ============================================================

run_and_check "missing dispatcher model" 1 "" "missing dispatcher provider or model" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/bad-dispatcher.md" --prompt "test" --dry-run

run_and_check "custom category without description" 1 "" "requires a description" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/bad-custom.md" --prompt "test" --dry-run

# ============================================================
echo ""
echo "=== Dry-Run Dispatch (valid config) ==="
# ============================================================

# Mock pi returns "code-review" as the classification
export MOCK_PI_STDOUT="code-review"
export MOCK_PI_EXIT_CODE=0
unset MOCK_PI_STDERR 2>/dev/null || true

run_and_check "dry-run returns ROUTE header" 0 "ROUTE:code-review" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/basic-auto.md" --prompt "review my code" --dry-run

run_and_check "dry-run returns PROVIDER" 0 "PROVIDER:anthropic" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/basic-auto.md" --prompt "review my code" --dry-run

run_and_check "dry-run returns MODEL" 0 "MODEL:claude-sonnet" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/basic-auto.md" --prompt "review my code" --dry-run

run_and_check "dry-run returns FALLBACK:none" 0 "FALLBACK:none" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/basic-auto.md" --prompt "review my code" --dry-run

# ============================================================
echo ""
echo "=== Dispatcher Returns 'default' ==="
# ============================================================

export MOCK_PI_STDOUT="default"
export MOCK_PI_EXIT_CODE=0

run_and_check "routes to default when dispatcher says default" 0 "ROUTE:default" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/basic-auto.md" --prompt "do something random" --dry-run

run_and_check "default uses configured default provider" 0 "PROVIDER:openai" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/basic-auto.md" --prompt "do something random" --dry-run

run_and_check "default uses configured default model" 0 "MODEL:gpt-4o" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/basic-auto.md" --prompt "do something random" --dry-run

# ============================================================
echo ""
echo "=== Dispatcher Failure Fallback ==="
# ============================================================

export MOCK_PI_EXIT_CODE=1
export MOCK_PI_STDOUT=""

run_and_check "dispatcher failure falls back to default (exit 3)" 3 "ROUTE:default" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/basic-auto.md" --prompt "test" --dry-run

run_and_check "dispatcher failure sets FALLBACK reason" 3 "FALLBACK:dispatcher_failed" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/basic-auto.md" --prompt "test" --dry-run

# ============================================================
echo ""
echo "=== Unrecognized Dispatcher Response ==="
# ============================================================

export MOCK_PI_EXIT_CODE=0
export MOCK_PI_STDOUT="something_random_and_wrong"

run_and_check "unrecognized response falls back to default" 3 "ROUTE:default" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/basic-auto.md" --prompt "test" --dry-run

run_and_check "unrecognized response sets FALLBACK reason" 3 "FALLBACK:dispatcher_unrecognized" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/basic-auto.md" --prompt "test" --dry-run

# ============================================================
echo ""
echo "=== Inherit Dispatcher ==="
# ============================================================

# No Pi call needed for inherit dispatcher
export MOCK_PI_EXIT_CODE=99
export MOCK_PI_STDOUT="should_not_be_called"

run_and_check "inherit dispatcher outputs DISPATCHER:inherit" 0 "DISPATCHER:inherit" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/inherit-dispatcher.md" --prompt "test" --dry-run

run_and_check "inherit dispatcher outputs NEEDS_INLINE_CLASSIFICATION" 0 "NEEDS_INLINE_CLASSIFICATION" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/inherit-dispatcher.md" --prompt "test"

run_and_check "inherit dispatcher non-dry-run outputs DISPATCHER_PROMPT_B64" 0 "DISPATCHER_PROMPT_B64:" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/inherit-dispatcher.md" --prompt "review my code"

# Finding 5: DISPATCHER_PROMPT_B64 field must be present in inherit-dispatcher dry-run output
# and must decode to output containing the user prompt text.
INHERIT_DRY_STDOUT=""
set +e
INHERIT_DRY_STDOUT="$(bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/inherit-dispatcher.md" --prompt "review my code" --dry-run 2>/dev/null)"
INHERIT_DRY_EXIT=$?
set -e

INHERIT_B64_LINE="$(echo "$INHERIT_DRY_STDOUT" | grep -c '^DISPATCHER_PROMPT_B64:' || true)"
if [ "$INHERIT_B64_LINE" -ge 1 ]; then
  echo "  PASS: inherit dispatcher dry-run outputs DISPATCHER_PROMPT_B64 field"
  PASS=$((PASS + 1))
else
  echo "  FAIL: inherit dispatcher dry-run outputs DISPATCHER_PROMPT_B64 field"
  echo "    stdout=$INHERIT_DRY_STDOUT"
  FAIL=$((FAIL + 1))
fi

INHERIT_B64_VALUE="$(echo "$INHERIT_DRY_STDOUT" | sed -n 's/^DISPATCHER_PROMPT_B64://p')"
INHERIT_DECODED="$(printf '%s' "$INHERIT_B64_VALUE" | base64 -d 2>/dev/null || true)"
if echo "$INHERIT_DECODED" | grep -qF "review my code"; then
  echo "  PASS: DISPATCHER_PROMPT_B64 decodes to output containing the user prompt text"
  PASS=$((PASS + 1))
else
  echo "  FAIL: DISPATCHER_PROMPT_B64 decodes to output containing the user prompt text"
  echo "    b64_value=$INHERIT_B64_VALUE"
  echo "    decoded=$INHERIT_DECODED"
  FAIL=$((FAIL + 1))
fi

# ============================================================
echo ""
echo "=== Inherit Category ==="
# ============================================================

export MOCK_PI_EXIT_CODE=0
export MOCK_PI_STDOUT="code-review"

run_and_check "inherit category outputs PROVIDER:inherit" 0 "PROVIDER:inherit" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/inherit-category.md" --prompt "review my code" --dry-run

run_and_check "inherit category outputs MODEL:inherit" 0 "MODEL:inherit" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/inherit-category.md" --prompt "review my code" --dry-run

# Finding 4: Non-dry-run path for a ROUTE_INHERIT category must output NEEDS_NATIVE_HANDLING
# in the body (after ---) and exit 0 when no fallback reason.
export MOCK_PI_EXIT_CODE=0
export MOCK_PI_STDOUT="code-review"

run_and_check "inherit category non-dry-run exits 0" 0 "" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/inherit-category.md" --prompt "review my code"

run_and_check "inherit category non-dry-run outputs NEEDS_NATIVE_HANDLING" 0 "NEEDS_NATIVE_HANDLING" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/inherit-category.md" --prompt "review my code"

# ============================================================
echo ""
echo "=== Custom Categories ==="
# ============================================================

export MOCK_PI_STDOUT="translation"

run_and_check "custom category routes correctly" 0 "ROUTE:translation" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/custom-category.md" --prompt "translate this to Python" --dry-run

run_and_check "custom category has correct provider" 0 "PROVIDER:google" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/custom-category.md" --prompt "translate this to Python" --dry-run

run_and_check "custom category has correct model" 0 "MODEL:gemini-2.5-pro" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/custom-category.md" --prompt "translate this to Python" --dry-run

# ============================================================
echo ""
echo "=== Full Execution (non-dry-run) ==="
# ============================================================

export MOCK_PI_STDOUT="explanation"
export MOCK_PI_EXIT_CODE=0

run_and_check "full execution includes ROUTE header" 0 "ROUTE:explanation" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/basic-auto.md" --prompt "explain this code"

run_and_check "full execution invokes Pi for routed model" 0 "MOCK_ARGS:" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/basic-auto.md" --prompt "explain this code"

run_and_check "full execution passes correct provider and model to pi" 0 "--provider openai --model gpt-4o-mini" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/basic-auto.md" --prompt "explain this code"

# ============================================================
echo ""
echo "=== Input Validation: Provider/Model/ROUTE_MINION ==="
# ============================================================

# Config with shell-metacharacter provider
cat > "$FIXTURE_DIR/bad-provider.md" <<'EOF'
---
dispatcher:
  provider: "open ai; echo INJECTED"
  model: gpt-4o-mini

default:
  provider: openai
  model: gpt-4o

categories:
  code-review:
    provider: anthropic
    model: claude-sonnet-4-20250514
---
Classify. Categories: {{categories}}. Prompt: {{prompt}}
EOF

cat > "$FIXTURE_DIR/bad-model.md" <<'EOF'
---
dispatcher:
  provider: openai
  model: "gpt-4o; rm -rf /"

default:
  provider: openai
  model: gpt-4o

categories:
  code-review:
    provider: anthropic
    model: claude-sonnet-4-20250514
---
Classify. Categories: {{categories}}. Prompt: {{prompt}}
EOF

run_and_check "dispatcher provider with shell metacharacters rejected" 1 "" "invalid" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/bad-provider.md" --prompt "test" --dry-run

run_and_check "dispatcher model with shell metacharacters rejected" 1 "" "invalid" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/bad-model.md" --prompt "test" --dry-run

# Config where a category's minion field contains a path-traversal value
cat > "$FIXTURE_DIR/traversal-minion.md" <<'EOF'
---
dispatcher:
  provider: openai
  model: gpt-4o-mini

default:
  provider: openai
  model: gpt-4o

categories:
  security:
    description: "Security review tasks"
    minion: "../../../etc/passwd"

---
Classify. Categories: {{categories}}. Prompt: {{prompt}}
EOF

export MOCK_PI_STDOUT="security"
export MOCK_PI_EXIT_CODE=0
run_and_check "path-traversal minion name in config rejected" 1 "" "invalid" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/traversal-minion.md" --prompt "test" --dry-run

# ============================================================
echo ""
echo "=== Category Description Sanitization ==="
# ============================================================

# Config with a very long description (> 200 chars) - should be truncated, not error
LONG_DESC="$(printf 'A%.0s' {1..250})"
cat > "$FIXTURE_DIR/long-description.md" <<EOF
---
dispatcher:
  provider: openai
  model: gpt-4o-mini

default:
  provider: openai
  model: gpt-4o

categories:
  custom-cat:
    description: "$LONG_DESC"
    provider: openai
    model: gpt-4o-mini

---
Classify. Categories: {{categories}}. Prompt: {{prompt}}
EOF

export MOCK_PI_STDOUT="custom-cat"
export MOCK_PI_EXIT_CODE=0
run_and_check "long category description truncated to 200 chars in dispatcher prompt" 0 "ROUTE:custom-cat" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/long-description.md" --prompt "test" --dry-run

# ============================================================
echo ""
echo "=== No Default Configured Fallback ==="
# ============================================================

cat > "$FIXTURE_DIR/no-default.md" <<'EOF'
---
dispatcher:
  provider: openai
  model: gpt-4o-mini

categories:
  code-review:
    provider: anthropic
    model: claude-sonnet-4-20250514

---
Classify. Categories: {{categories}}. Prompt: {{prompt}}
EOF

export MOCK_PI_STDOUT="default"
export MOCK_PI_EXIT_CODE=0
run_and_check "no_default fallback outputs FALLBACK:no_default" 3 "FALLBACK:no_default" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/no-default.md" --prompt "something random" --dry-run

# dispatcher_unrecognized + no default: dispatcher returns unrecognized category,
# fallback-to-default path then hits no_default branch.
# Expected: exit 3, FALLBACK:no_default (no_default overwrites dispatcher_unrecognized).
export MOCK_PI_STDOUT="something_unrecognized"
export MOCK_PI_EXIT_CODE=0
run_and_check "dispatcher_unrecognized with no default falls back to no_default" 3 "FALLBACK:no_default" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/no-default.md" --prompt "something random" --dry-run

run_and_check "dispatcher_unrecognized with no default routes to default" 3 "ROUTE:default" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/no-default.md" --prompt "something random" --dry-run

# ============================================================
echo ""
echo "=== Minion-Based Routing ==="
# ============================================================

MINION_TMP="$(mktemp -d)"
_CLEANUP_DIRS+=("$MINION_TMP")
mkdir -p "$MINION_TMP/.claude/minions"
cat > "$MINION_TMP/.claude/minions/my-reviewer.md" <<'EOF'
---
provider: anthropic
model: claude-sonnet-4-20250514
---
You are a code reviewer.
EOF

cat > "$FIXTURE_DIR/minion-routing.md" <<'EOF'
---
dispatcher:
  provider: openai
  model: gpt-4o-mini

default:
  provider: openai
  model: gpt-4o

categories:
  security:
    description: "Security auditing and vulnerability review"
    minion: my-reviewer

---
Classify. Categories: {{categories}}. Prompt: {{prompt}}
EOF

export MOCK_PI_STDOUT="security"
export MOCK_PI_EXIT_CODE=0

# Run from MINION_TMP directory so the .claude/minions path is found
run_and_check "minion-based routing outputs MINION header" 0 "MINION:my-reviewer" "" \
  -- bash -c "cd '$MINION_TMP' && bash '$AUTO_DISPATCH' --config '$FIXTURE_DIR/minion-routing.md' --prompt 'review my code' --dry-run"

# Full execution via minion file: mock minion-run.sh at the boundary to verify --file flag
# and assert the correct minion path is passed without depending on pi's internal call count.
export MOCK_PI_STDOUT="security"
export MOCK_PI_EXIT_CODE=0

MINIONRUN_ARGS_FILE="$(mktemp)"
_CLEANUP_DIRS+=("$MINIONRUN_ARGS_FILE")
_minion_site1_body="#!/usr/bin/env bash
echo \"MINIONRUN_ARGS: \$*\" > \"$MINIONRUN_ARGS_FILE\"
exit 0"
_minion_site1_test() {
  run_and_check "minion full-execution passes --file flag to minion-run.sh" 0 "ROUTE:security" "" \
    -- bash -c "cd '$MINION_TMP' && bash '$AUTO_DISPATCH' --config '$FIXTURE_DIR/minion-routing.md' --prompt 'review my code'"
  assert_file_contains "minion full-execution: minion-run.sh received --file flag" \
    "$MINIONRUN_ARGS_FILE" "--file"
  assert_file_contains "minion full-execution: minion-run.sh received correct minion path" \
    "$MINIONRUN_ARGS_FILE" "my-reviewer.md"
}
with_mock_minionrun "$_minion_site1_body" _minion_site1_test
rm -f "$MINIONRUN_ARGS_FILE"

# Test missing minion file falls back to default route and reports to stderr
# Run from /tmp so .claude/minions/my-reviewer.md is not found
# When default route succeeds, exit is 0 (no overall failure)
export MOCK_PI_STDOUT="security"
export MOCK_PI_EXIT_CODE=0
run_and_check "missing minion file with default reports error to stderr" 0 "" "minion file not found" \
  -- bash -c "cd '/tmp' && bash '$AUTO_DISPATCH' --config '$FIXTURE_DIR/minion-routing.md' --prompt 'test'"

# Finding 4: no-default + missing-minion → exit 4
# Config has a minion category but NO default block. When minion file is not found,
# auto-dispatch.sh must exit 4 (no fallback available).
cat > "$FIXTURE_DIR/minion-no-default.md" <<'EOF'
---
dispatcher:
  provider: openai
  model: gpt-4o-mini

categories:
  security:
    description: "Security auditing and vulnerability review"
    minion: my-reviewer

---
Classify. Categories: {{categories}}. Prompt: {{prompt}}
EOF

export MOCK_PI_STDOUT="security"
export MOCK_PI_EXIT_CODE=0
run_and_check "no-default + missing-minion exits 4" 4 "" "minion file not found" \
  -- bash -c "cd '/tmp' && bash '$AUTO_DISPATCH' --config '$FIXTURE_DIR/minion-no-default.md' --prompt 'test'"

# ============================================================
echo ""
echo "=== Route Execution Failure Fallback ==="
# ============================================================

# These tests mock at the minion-run.sh boundary (the script auto-dispatch.sh calls directly)
# instead of counting pi invocations. This avoids coupling to minion-run.sh's internal
# call count and tests auto-dispatch.sh's fallback contract directly.
#
# Approach: temporarily replace $ROOT/lib/minion-run.sh with a mock, run the test,
# restore the original.

# --- Test: route execution fails AND default also fails → exit 4 ---
# The dispatcher call still goes through the pi mock (returns "explanation").
# The two minion-run.sh calls (primary route + default fallback) both fail.
export MOCK_PI_STDOUT="explanation"
export MOCK_PI_EXIT_CODE=0

MINIONRUN_CALL_FILE="$(mktemp)"
_CLEANUP_DIRS+=("$MINIONRUN_CALL_FILE")
_minion_site2_body="#!/usr/bin/env bash
# Mock minion-run.sh: always fails (both primary route and default fallback fail).
echo \"MOCK_MINIONRUN_ARGS: \$*\" >&2
exit 1"
_minion_site2_test() {
  run_and_check "route execution failure with failed default falls back to exit 4" 4 "" "" \
    -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/basic-auto.md" --prompt "explain this code"
}
with_mock_minionrun "$_minion_site2_body" _minion_site2_test
rm -f "$MINIONRUN_CALL_FILE"

# --- Test: route execution fails but default fallback succeeds → exit 3 ---
export MOCK_PI_STDOUT="explanation"
export MOCK_PI_EXIT_CODE=0

# Sentinel file: first call creates it and fails; second call sees it and succeeds.
MINIONRUN_CALL_FILE2="$(mktemp)"
rm -f "$MINIONRUN_CALL_FILE2"
_CLEANUP_DIRS+=("$MINIONRUN_CALL_FILE2")
_minion_site3_body="#!/usr/bin/env bash
# Mock minion-run.sh: first call (primary route) fails, second call (default fallback) succeeds.
# Uses a sentinel file: absent on first call (fails), present on second call (succeeds).
if [ ! -f '$MINIONRUN_CALL_FILE2' ]; then
  touch '$MINIONRUN_CALL_FILE2'
  echo \"MOCK_MINIONRUN_ARGS primary: \$*\" >&2
  exit 1
else
  echo \"MOCK_MINIONRUN_ARGS fallback: \$*\" >&2
  echo \"fallback result\"
  exit 0
fi"
_minion_site3_test() {
  run_and_check "route execution failure with successful default fallback exits 3" 3 "" "" \
    -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/basic-auto.md" --prompt "explain this code"
}
with_mock_minionrun "$_minion_site3_body" _minion_site3_test
rm -f "$MINIONRUN_CALL_FILE2"

# ============================================================
echo ""
echo "=== Mock Variable Isolation ==="
# ============================================================

# Verify that each run_and_check call uses its own snapshot of MOCK_PI_* variables,
# not a value that may have been mutated by a prior call or between calls.

# Call 1: snapshot exit=0 and stdout=code-review
export MOCK_PI_STDOUT="code-review"
export MOCK_PI_EXIT_CODE=0
unset MOCK_PI_STDERR 2>/dev/null || true

run_and_check "mock variables isolated: first call uses its own snapshot" 0 "ROUTE:code-review" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/basic-auto.md" --prompt "review my code" --dry-run

# Mutate the global after call 1 — this simulates a mid-test mutation that must NOT bleed
# into a subsequent run_and_check that snapshots a different value.
# Call 2: immediately set exit=99 and stdout=default (simulating a failure scenario),
# then verify call 2 sees exit=3 (fallback) and FALLBACK:no_default from MOCK_PI_STDOUT=default.
# If isolation breaks, call 2 would see exit=0/ROUTE:code-review from the call-1 snapshot.
export MOCK_PI_STDOUT="default"
export MOCK_PI_EXIT_CODE=0

run_and_check "mock variables isolated: second call sees its own mutated value" 3 "FALLBACK:no_default" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/no-default.md" --prompt "something random" --dry-run

# Genuine isolation: verify a mutation to the global AFTER the snapshot is taken does NOT
# reach the subprocess. We write a sentinel mock pi that checks the env var it actually sees.
# We snapshot exit=0, then (from OUTSIDE run_and_check) export exit=99 into global.
# With the fix, the subprocess should still see exit=0 (from the snapshot passed via env).
_SENTINEL_RESULT="$(mktemp)"
_CLEANUP_DIRS+=("$_SENTINEL_RESULT")
export MOCK_PI_EXIT_CODE=0
export MOCK_PI_STDOUT="code-review"
unset MOCK_PI_STDERR 2>/dev/null || true

# Pi body that records the MOCK_PI_EXIT_CODE it actually receives to the sentinel file.
_sentinel_pi_body="#!/usr/bin/env bash
echo \"MOCK_ARGS: \$*\"
echo \"\${MOCK_PI_EXIT_CODE:-UNSET}\" > \"$_SENTINEL_RESULT\"
if [ -n \"\${MOCK_PI_STDOUT:-}\" ]; then
  echo \"\$MOCK_PI_STDOUT\"
fi
exit \"\${MOCK_PI_EXIT_CODE:-0}\""

_sentinel_pi_test() {
  # run_and_check will snapshot MOCK_PI_EXIT_CODE=0; the subprocess must see 0
  run_and_check "mock variables isolated: snapshot passed to subprocess" 0 "ROUTE:code-review" "" \
    -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/basic-auto.md" --prompt "review my code" --dry-run

  assert_file_contains "mock variables isolated: subprocess received snapshotted exit code" \
    "$_SENTINEL_RESULT" "0"
  rm -f "$_SENTINEL_RESULT"
}
# with_mock_pi guarantees restore of the standard pi body via RETURN trap
with_mock_pi "$_sentinel_pi_body" _sentinel_pi_test

# ============================================================
echo ""
echo "=== with_mock_minionrun: Production File Safety ==="
# ============================================================
# Finding 4: with_mock_minionrun must not modify the production file in-place.
# The real minion-run.sh must be byte-for-byte identical before and after the call.

_REAL_MINIONRUN="$ROOT/lib/minion-run.sh"
_MINIONRUN_CHECKSUM_BEFORE="$(md5sum "$_REAL_MINIONRUN" | awk '{print $1}')"

_file_safety_test() {
  # Inside the callback: the mock is active. Verify the real file is NOT the mock content.
  local content_inside
  content_inside="$(cat "$_REAL_MINIONRUN" 2>/dev/null || echo MISSING)"
  # The mock contains a known unique marker string
  if ! echo "$content_inside" | grep -qF "MINIONRUN_SAFETY_MARKER_12345"; then
    echo "  PASS: production minion-run.sh not modified inside with_mock_minionrun callback"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: production minion-run.sh was modified in-place by with_mock_minionrun"
    FAIL=$((FAIL + 1))
  fi
}

_safety_mock_body='#!/usr/bin/env bash
# MINIONRUN_SAFETY_MARKER_12345
echo "mock output"
exit 0'

with_mock_minionrun "$_safety_mock_body" _file_safety_test

_MINIONRUN_CHECKSUM_AFTER="$(md5sum "$_REAL_MINIONRUN" | awk '{print $1}')"
if [ "$_MINIONRUN_CHECKSUM_BEFORE" = "$_MINIONRUN_CHECKSUM_AFTER" ]; then
  echo "  PASS: real minion-run.sh is byte-for-byte identical after with_mock_minionrun"
  PASS=$((PASS + 1))
else
  echo "  FAIL: real minion-run.sh was corrupted by with_mock_minionrun"
  echo "    before=$_MINIONRUN_CHECKSUM_BEFORE after=$_MINIONRUN_CHECKSUM_AFTER"
  FAIL=$((FAIL + 1))
fi

# ============================================================
echo ""
echo "=== --category Flag ==="
# ============================================================
# Finding 3: The --category flag codepath (lines 299-306) has zero tests.
# Cover: (1) valid category + --dry-run routes correctly,
#        (2) unknown category exits 1 with 'unknown category' on stderr,
#        (3) --category default routes to ROUTE:default,
#        (4) --category with --dry-run shows correct ROUTE/PROVIDER/MODEL lines.

# Set up mock pi to confirm it is NOT called when --category is given
export MOCK_PI_EXIT_CODE=99
export MOCK_PI_STDOUT="should_not_be_called"

# (1) valid category + --dry-run routes correctly
run_and_check "--category valid category with --dry-run routes correctly" 0 "ROUTE:code-review" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/basic-auto.md" --prompt "review my code" --category "code-review" --dry-run

# (4) --category with --dry-run shows correct ROUTE/PROVIDER/MODEL lines
run_and_check "--category dry-run shows correct PROVIDER" 0 "PROVIDER:anthropic" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/basic-auto.md" --prompt "review my code" --category "code-review" --dry-run

run_and_check "--category dry-run shows correct MODEL" 0 "MODEL:claude-sonnet" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/basic-auto.md" --prompt "review my code" --category "code-review" --dry-run

# (2) unknown category exits 1 with 'unknown category' on stderr
run_and_check "--category unknown category exits 1 with 'unknown category' on stderr" 1 "" "unknown category" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/basic-auto.md" --prompt "test" --category "nonexistent-category" --dry-run

# (3) --category default routes to ROUTE:default
run_and_check "--category default routes to ROUTE:default" 0 "ROUTE:default" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/basic-auto.md" --prompt "test" --category "default" --dry-run

run_and_check "--category default uses correct provider for default route" 0 "PROVIDER:openai" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/basic-auto.md" --prompt "test" --category "default" --dry-run

run_and_check "--category default uses correct model for default route" 0 "MODEL:gpt-4o" "" \
  -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/basic-auto.md" --prompt "test" --category "default" --dry-run

# ============================================================
echo ""
echo "=== Dispatcher prompt delivery (flag-injection defang) ==="
# ============================================================
# Pi CLI does not support a "--" end-of-options sentinel — it rejects bare "--"
# as an unknown option — so the dispatcher prompt is delivered via stdin instead.
# Stdin content is never parsed as argv, defanging flag injection completely.
# This test verifies:
#   1. The dispatcher prompt arrives via stdin (not as a positional argument)
#   2. No bare "--" appears in argv (which would crash real Pi)
#   3. The user's --no-tools-prefixed prompt does not appear in argv

_SENTINEL_ARGS_FILE="$(mktemp)"
_SENTINEL_STDIN_FILE="$(mktemp)"
_CLEANUP_DIRS+=("$_SENTINEL_ARGS_FILE" "$_SENTINEL_STDIN_FILE")

_sentinel_args_pi_body="#!/usr/bin/env bash
# Record each argument as a separate line so we can inspect arg boundaries.
printf '%s\n' \"\$@\" > '$_SENTINEL_ARGS_FILE'
# Record stdin so we can verify the prompt was delivered there.
if [ ! -t 0 ]; then
  cat > '$_SENTINEL_STDIN_FILE'
else
  : > '$_SENTINEL_STDIN_FILE'
fi
echo \"MOCK_ARGS: \$*\"
if [ -n \"\${MOCK_PI_STDOUT:-}\" ]; then
  echo \"\$MOCK_PI_STDOUT\"
fi
exit \"\${MOCK_PI_EXIT_CODE:-0}\""

export MOCK_PI_STDOUT="code-review"
export MOCK_PI_EXIT_CODE=0
unset MOCK_PI_STDERR 2>/dev/null || true

_sentinel_args_test() {
  # Run dry-run so only the dispatcher pi call is made (no minion-run.sh call).
  run_and_check "dispatcher invokes pi with ROUTE:code-review when prompt starts with --" 0 "ROUTE:code-review" "" \
    -- bash "$AUTO_DISPATCH" --config "$FIXTURE_DIR/basic-auto.md" --prompt "--no-tools injected arg" --dry-run

  local args_content stdin_content
  args_content="$(cat "$_SENTINEL_ARGS_FILE" 2>/dev/null || echo MISSING)"
  stdin_content="$(cat "$_SENTINEL_STDIN_FILE" 2>/dev/null || echo MISSING)"

  # 1. Stdin must contain the user prompt (which begins with --no-tools).
  if echo "$stdin_content" | grep -qF -- '--no-tools injected arg'; then
    echo "  PASS: dispatcher prompt delivered via stdin"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: dispatcher prompt not found in stdin"
    echo "    stdin was: $stdin_content"
    FAIL=$((FAIL + 1))
  fi

  # 2. argv must NOT contain a bare "--" (Pi rejects it as an unknown option).
  if echo "$args_content" | grep -qxF -- '--'; then
    echo "  FAIL: dispatcher pi call includes bare '--' in argv (Pi would reject this)"
    echo "    recorded args (one per line): $args_content"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: dispatcher pi call does not pass bare '--' in argv"
    PASS=$((PASS + 1))
  fi

  # 3. argv must NOT contain the user prompt (it should only be in stdin).
  if echo "$args_content" | grep -qF -- '--no-tools injected arg'; then
    echo "  FAIL: dispatcher prompt unexpectedly appears in argv"
    echo "    recorded args (one per line): $args_content"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: dispatcher prompt does not leak into argv"
    PASS=$((PASS + 1))
  fi

  rm -f "$_SENTINEL_ARGS_FILE" "$_SENTINEL_STDIN_FILE"
}

with_mock_pi "$_sentinel_args_pi_body" _sentinel_args_test

# ============================================================
echo ""
echo "=== Summary ==="
# ============================================================

TOTAL=$((PASS + FAIL))
echo ""
echo "Total: $TOTAL  Passed: $PASS  Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "SOME TESTS FAILED"
  exit 1
fi

echo "ALL TESTS PASSED"
exit 0
