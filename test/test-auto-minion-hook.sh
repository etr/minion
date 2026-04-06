#!/usr/bin/env bash
#
# Tests for lib/auto-minion-hook.sh — auto-minion pre-message hook logic.
# Tests the shell-side hook: enabled check, bypass, dispatcher type routing.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_SCRIPT="$ROOT/lib/auto-minion-hook.sh"
AUTO_DISPATCH="$ROOT/lib/auto-dispatch.sh"

PASS=0
FAIL=0

# --- Cleanup accumulator ---
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

_STANDARD_PI_BODY='#!/usr/bin/env bash
echo "MOCK_ARGS: $*"
if [ -n "${MOCK_PI_STDERR:-}" ]; then
  echo "$MOCK_PI_STDERR" >&2
fi
if [ -n "${MOCK_PI_STDOUT:-}" ]; then
  echo "$MOCK_PI_STDOUT"
fi
exit "${MOCK_PI_EXIT_CODE:-0}"'

printf '%s\n' "$_STANDARD_PI_BODY" > "$MOCK_DIR/pi"
chmod +x "$MOCK_DIR/pi"
export PATH="$MOCK_DIR:$PATH"

# --- Test workspace ---
WORK_DIR="$(mktemp -d)"
_CLEANUP_DIRS+=("$WORK_DIR")

# --- Test helpers ---
run_hook() {
  local message="$1"
  shift
  printf '%s' "$message" | (cd "$WORK_DIR" && bash "$HOOK_SCRIPT" "$@")
}

run_and_check() {
  local description="$1"
  local message="$2"
  local expected_exit="$3"
  local stdout_pattern="$4"
  local negative_pattern="${5:-}"

  local stdout actual_exit
  set +e
  stdout="$(run_hook "$message" 2>/dev/null)"
  actual_exit=$?
  set -e

  local all_pass=true

  if [ "$actual_exit" != "$expected_exit" ]; then
    all_pass=false
  fi

  if [ -n "$stdout_pattern" ] && ! echo "$stdout" | grep -qF -- "$stdout_pattern"; then
    all_pass=false
  fi

  if [ -n "$negative_pattern" ] && echo "$stdout" | grep -qF -- "$negative_pattern"; then
    all_pass=false
  fi

  if $all_pass; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    echo "    expected exit=$expected_exit got=$actual_exit"
    if [ -n "$stdout_pattern" ]; then
      echo "    expected pattern: $stdout_pattern"
    fi
    if [ -n "$negative_pattern" ]; then
      echo "    should NOT contain: $negative_pattern"
    fi
    echo "    actual stdout: $stdout"
    FAIL=$((FAIL + 1))
  fi
}

# run_hook_with_home: runs hook with a custom HOME directory, captures both stdout and stderr
run_hook_with_home() {
  local message="$1"
  local home_dir="$2"
  printf '%s' "$message" | (cd "$WORK_DIR" && HOME="$home_dir" bash "$HOOK_SCRIPT")
}

run_and_check_combined() {
  local description="$1"
  local message="$2"
  local expected_exit="$3"
  local stdout_pattern="$4"
  local negative_pattern="${5:-}"

  local output actual_exit
  set +e
  output="$(run_hook "$message" 2>&1)"
  actual_exit=$?
  set -e

  local all_pass=true

  if [ "$actual_exit" != "$expected_exit" ]; then
    all_pass=false
  fi

  if [ -n "$stdout_pattern" ] && ! echo "$output" | grep -qF -- "$stdout_pattern"; then
    all_pass=false
  fi

  if [ -n "$negative_pattern" ] && echo "$output" | grep -qF -- "$negative_pattern"; then
    all_pass=false
  fi

  if $all_pass; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    echo "    expected exit=$expected_exit got=$actual_exit"
    if [ -n "$stdout_pattern" ]; then
      echo "    expected pattern: $stdout_pattern"
    fi
    if [ -n "$negative_pattern" ]; then
      echo "    should NOT contain: $negative_pattern"
    fi
    echo "    actual output (stdout+stderr): $output"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================
echo "=== Disabled State ==="
# ============================================================

# No .auto-enabled file exists
rm -rf "$WORK_DIR/.claude"

run_and_check "outputs DISABLED when no marker file" \
  "hello world" 0 "STATUS:DISABLED"

# ============================================================
echo ""
echo "=== Bypass Conditions ==="
# ============================================================

# Create a valid config and marker file
mkdir -p "$WORK_DIR/.claude/minions"
cat > "$WORK_DIR/.claude/minions/auto.md" <<'EOF'
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
Classify. Categories: {{categories}}. Prompt: {{prompt}}
EOF
printf 'config=%s\n' "$WORK_DIR/.claude/minions/auto.md" > "$WORK_DIR/.claude/minions/.auto-enabled"

run_and_check "bypasses empty message" \
  "" 0 "STATUS:BYPASS"

run_and_check "bypasses /minion command" \
  "/minion security-reviewer" 0 "STATUS:BYPASS"

run_and_check "bypasses /minion auto off" \
  "/minion auto off" 0 "STATUS:BYPASS"

run_and_check "bypasses any slash command" \
  "/help" 0 "STATUS:BYPASS"

run_and_check "bypasses slash command with args" \
  "/commit -m 'fix bug'" 0 "STATUS:BYPASS"

run_and_check "does NOT bypass regular message" \
  "review my code please" 0 "" "STATUS:BYPASS"

# ============================================================
echo ""
echo "=== Error Handling ==="
# ============================================================

# Marker points to nonexistent config
printf 'config=/nonexistent/auto.md\n' > "$WORK_DIR/.claude/minions/.auto-enabled"

run_and_check "errors when config file missing" \
  "hello" 0 "STATUS:ERROR"

run_and_check "includes config path in error" \
  "hello" 0 "MSG:Config file not found: /nonexistent/auto.md"

# Relative config path must be rejected (Finding 3: CONFIG_PATH must be absolute)
printf 'config=relative/path/auto.md\n' > "$WORK_DIR/.claude/minions/.auto-enabled"

run_and_check "errors when config path is relative (not absolute)" \
  "hello" 0 "STATUS:ERROR"

run_and_check "error message mentions absolute path requirement" \
  "hello" 0 "MSG:Config path must be absolute"

# Restore valid config
printf 'config=%s\n' "$WORK_DIR/.claude/minions/auto.md" > "$WORK_DIR/.claude/minions/.auto-enabled"

# ============================================================
echo ""
echo "=== HOME Directory Fallback ==="
# ============================================================

# Finding 8: HOME-directory .auto-enabled fallback path
# Remove project-local marker, put it in a custom HOME dir, assert hook reads from there

rm -rf "$WORK_DIR/.claude"

HOME_DIR="$(mktemp -d)"
_CLEANUP_DIRS+=("$HOME_DIR")
mkdir -p "$HOME_DIR/.claude/minions"

# Create config in the HOME dir
cat > "$HOME_DIR/.claude/minions/auto.md" <<'EOF'
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
Classify. Categories: {{categories}}. Prompt: {{prompt}}
EOF
printf 'config=%s\n' "$HOME_DIR/.claude/minions/auto.md" > "$HOME_DIR/.claude/minions/.auto-enabled"

# Run with no project-local .claude dir and with HOME pointing to our temp dir
actual_exit=0
set +e
home_output="$(printf '%s' "review my code" | (cd "$WORK_DIR" && HOME="$HOME_DIR" bash "$HOOK_SCRIPT" 2>/dev/null))"
actual_exit=$?
set -e

if echo "$home_output" | grep -qF "STATUS:NEEDS_CLASSIFICATION"; then
  echo "  PASS: reads config from HOME/.claude/minions when no project-local marker"
  PASS=$((PASS + 1))
else
  echo "  FAIL: reads config from HOME/.claude/minions when no project-local marker"
  echo "    exit=$actual_exit output=$home_output"
  FAIL=$((FAIL + 1))
fi

if echo "$home_output" | grep -qF "CONFIG:$HOME_DIR/.claude/minions/auto.md"; then
  echo "  PASS: CONFIG path from HOME dir fallback is correct"
  PASS=$((PASS + 1))
else
  echo "  FAIL: CONFIG path from HOME dir fallback is correct"
  echo "    output=$home_output"
  FAIL=$((FAIL + 1))
fi

# Restore project-local marker and config
mkdir -p "$WORK_DIR/.claude/minions"
cat > "$WORK_DIR/.claude/minions/auto.md" <<'EOF'
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
Classify. Categories: {{categories}}. Prompt: {{prompt}}
EOF
printf 'config=%s\n' "$WORK_DIR/.claude/minions/auto.md" > "$WORK_DIR/.claude/minions/.auto-enabled"

# ============================================================
echo ""
echo "=== Inherit Dispatcher ==="
# ============================================================

cat > "$WORK_DIR/.claude/minions/auto.md" <<'EOF'
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
Classify. Categories: {{categories}}. Prompt: {{prompt}}
EOF

run_and_check "inherit dispatcher outputs NEEDS_CLASSIFICATION" \
  "review my code" 0 "STATUS:NEEDS_CLASSIFICATION"

run_and_check "inherit dispatcher includes SHOW_ROUTING" \
  "review my code" 0 "SHOW_ROUTING:true"

run_and_check "inherit dispatcher includes CONFIG path" \
  "review my code" 0 "CONFIG:$WORK_DIR/.claude/minions/auto.md"

run_and_check "inherit dispatcher includes DISPATCHER:inherit from auto-dispatch" \
  "review my code" 0 "DISPATCHER:inherit"

run_and_check "inherit dispatcher includes CATEGORIES" \
  "review my code" 0 "CATEGORIES:"

# Finding 5: inherit-dispatcher path with a broken config should emit STATUS:ERROR,
# not STATUS:NEEDS_CLASSIFICATION with incomplete data.
# We test this by pointing to a config that auto-dispatch.sh rejects at validation time
# (invalid provider identifier fails validation and exits 1).
cat > "$WORK_DIR/.claude/minions/broken.md" <<'EOF'
---
dispatcher: inherit

default:
  provider: "invalid provider with spaces"
  model: gpt-4o

categories:
  code-review:
    provider: anthropic
    model: claude-sonnet-4-20250514

show-routing: true
---
Classify. Categories: {{categories}}. Prompt: {{prompt}}
EOF
printf 'config=%s\n' "$WORK_DIR/.claude/minions/broken.md" > "$WORK_DIR/.claude/minions/.auto-enabled"

run_and_check "inherit dispatcher with invalid config emits STATUS:ERROR not NEEDS_CLASSIFICATION" \
  "review my code" 0 "STATUS:ERROR" "STATUS:NEEDS_CLASSIFICATION"

# Restore valid inherit config and marker
cat > "$WORK_DIR/.claude/minions/auto.md" <<'EOF'
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
Classify. Categories: {{categories}}. Prompt: {{prompt}}
EOF
printf 'config=%s\n' "$WORK_DIR/.claude/minions/auto.md" > "$WORK_DIR/.claude/minions/.auto-enabled"

# ============================================================
echo ""
echo "=== External Dispatcher: Successful Dispatch ==="
# ============================================================

cat > "$WORK_DIR/.claude/minions/auto.md" <<'EOF'
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
Classify. Categories: {{categories}}. Prompt: {{prompt}}
EOF

export MOCK_PI_STDOUT="code-review"
export MOCK_PI_EXIT_CODE=0
unset MOCK_PI_STDERR 2>/dev/null || true

run_and_check "external dispatch outputs DISPATCHED" \
  "review my code" 0 "STATUS:DISPATCHED"

run_and_check "external dispatch includes EXIT code" \
  "review my code" 0 "EXIT:0"

run_and_check "external dispatch includes SHOW_ROUTING" \
  "review my code" 0 "SHOW_ROUTING:true"

run_and_check "external dispatch includes ROUTE header" \
  "review my code" 0 "ROUTE:code-review"

# Finding 7: STDERR propagation — when Pi writes to stderr during dispatch,
# the hook should include a STDERR: line in its output.
export MOCK_PI_STDERR="some warning from pi"
export MOCK_PI_STDOUT="code-review"
export MOCK_PI_EXIT_CODE=0

run_and_check "external dispatch propagates Pi stderr as STDERR: line" \
  "review my code" 0 "STDERR:some warning from pi"

unset MOCK_PI_STDERR 2>/dev/null || true

# ============================================================
echo ""
echo "=== External Dispatcher: Native Route ==="
# ============================================================

cat > "$WORK_DIR/.claude/minions/auto.md" <<'EOF'
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

export MOCK_PI_STDOUT="code-review"
export MOCK_PI_EXIT_CODE=0

run_and_check "native route outputs STATUS:NATIVE" \
  "review my code" 0 "STATUS:NATIVE"

run_and_check "native route includes CATEGORY" \
  "review my code" 0 "CATEGORY:code-review"

run_and_check "native route includes FALLBACK" \
  "review my code" 0 "FALLBACK:none"

run_and_check "native route includes SHOW_ROUTING" \
  "review my code" 0 "SHOW_ROUTING:true"

# ============================================================
echo ""
echo "=== External Dispatcher: Fallback Cases ==="
# ============================================================

# Restore non-inherit config
cat > "$WORK_DIR/.claude/minions/auto.md" <<'EOF'
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

show-routing: true
---
Classify. Categories: {{categories}}. Prompt: {{prompt}}
EOF

# Dispatcher fails → default route used.
# Use a sentinel mock: first pi call (dispatcher) fails, second (route exec) succeeds.
# Capture output once and check both assertions against it (Finding 9: avoids duplicated sentinel).
install_sentinel_mock() {
  local sentinel_file="$1"
  cat > "$MOCK_DIR/pi" <<PIEOF
#!/usr/bin/env bash
if [ ! -f '$sentinel_file' ]; then
  touch '$sentinel_file'
  exit 1
else
  echo "fallback output"
  exit 0
fi
PIEOF
  chmod +x "$MOCK_DIR/pi"
}

SENTINEL_FILE="$(mktemp)"
rm -f "$SENTINEL_FILE"
_CLEANUP_DIRS+=("$SENTINEL_FILE")
install_sentinel_mock "$SENTINEL_FILE"

# Run the hook once and check both EXIT:3 and FALLBACK:dispatcher_failed in one output
FALLBACK_OUTPUT=""
set +e
FALLBACK_OUTPUT="$(run_hook "test prompt" 2>/dev/null)"
set -e
rm -f "$SENTINEL_FILE"

if echo "$FALLBACK_OUTPUT" | grep -qF "EXIT:3"; then
  echo "  PASS: dispatcher failure outputs DISPATCHED with EXIT:3"
  PASS=$((PASS + 1))
else
  echo "  FAIL: dispatcher failure outputs DISPATCHED with EXIT:3"
  echo "    output=$FALLBACK_OUTPUT"
  FAIL=$((FAIL + 1))
fi

if echo "$FALLBACK_OUTPUT" | grep -qF "FALLBACK:dispatcher_failed"; then
  echo "  PASS: dispatcher failure includes FALLBACK:dispatcher_failed"
  PASS=$((PASS + 1))
else
  echo "  FAIL: dispatcher failure includes FALLBACK:dispatcher_failed"
  echo "    output=$FALLBACK_OUTPUT"
  FAIL=$((FAIL + 1))
fi

# Restore standard mock
printf '%s\n' "$_STANDARD_PI_BODY" > "$MOCK_DIR/pi"
chmod +x "$MOCK_DIR/pi"

# ============================================================
echo ""
echo "=== Show-Routing Config ==="
# ============================================================

cat > "$WORK_DIR/.claude/minions/auto.md" <<'EOF'
---
dispatcher: inherit

default:
  provider: openai
  model: gpt-4o

categories:
  code-review:
    provider: anthropic
    model: claude-sonnet-4-20250514

show-routing: false
---
Classify. Categories: {{categories}}. Prompt: {{prompt}}
EOF

run_and_check "show-routing:false is passed through" \
  "review my code" 0 "SHOW_ROUTING:false"

# ============================================================
echo ""
echo "=== --category Flag on auto-dispatch.sh ==="
# ============================================================

cat > "$WORK_DIR/.claude/minions/auto.md" <<'EOF'
---
dispatcher: inherit

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
Classify. Categories: {{categories}}. Prompt: {{prompt}}
EOF

# --category skips dispatcher, goes straight to route resolution
set +e
CATEGORY_OUTPUT="$(bash "$AUTO_DISPATCH" --config "$WORK_DIR/.claude/minions/auto.md" --prompt "test" --category "code-review" --dry-run 2>/dev/null)"
CATEGORY_EXIT=$?
set -e

if [ $CATEGORY_EXIT -eq 0 ] && echo "$CATEGORY_OUTPUT" | grep -qF "ROUTE:code-review"; then
  echo "  PASS: --category routes to specified category"
  PASS=$((PASS + 1))
else
  echo "  FAIL: --category routes to specified category"
  echo "    exit=$CATEGORY_EXIT output=$CATEGORY_OUTPUT"
  FAIL=$((FAIL + 1))
fi

if echo "$CATEGORY_OUTPUT" | grep -qF "PROVIDER:anthropic"; then
  echo "  PASS: --category resolves correct provider"
  PASS=$((PASS + 1))
else
  echo "  FAIL: --category resolves correct provider"
  echo "    output=$CATEGORY_OUTPUT"
  FAIL=$((FAIL + 1))
fi

# --category with invalid category name
set +e
INVALID_OUTPUT="$(bash "$AUTO_DISPATCH" --config "$WORK_DIR/.claude/minions/auto.md" --prompt "test" --category "nonexistent" --dry-run 2>&1)"
INVALID_EXIT=$?
set -e

if [ $INVALID_EXIT -eq 1 ] && echo "$INVALID_OUTPUT" | grep -qF "unknown category"; then
  echo "  PASS: --category rejects unknown category"
  PASS=$((PASS + 1))
else
  echo "  FAIL: --category rejects unknown category"
  echo "    exit=$INVALID_EXIT output=$INVALID_OUTPUT"
  FAIL=$((FAIL + 1))
fi

# --category with "default" routes to default
set +e
DEFAULT_OUTPUT="$(bash "$AUTO_DISPATCH" --config "$WORK_DIR/.claude/minions/auto.md" --prompt "test" --category "default" --dry-run 2>/dev/null)"
DEFAULT_EXIT=$?
set -e

if [ $DEFAULT_EXIT -eq 0 ] && echo "$DEFAULT_OUTPUT" | grep -qF "ROUTE:default"; then
  echo "  PASS: --category accepts 'default'"
  PASS=$((PASS + 1))
else
  echo "  FAIL: --category accepts 'default'"
  echo "    exit=$DEFAULT_EXIT output=$DEFAULT_OUTPUT"
  FAIL=$((FAIL + 1))
fi

# --category skips inherit dispatcher (no DISPATCHER:inherit in output)
set +e
SKIP_OUTPUT="$(bash "$AUTO_DISPATCH" --config "$WORK_DIR/.claude/minions/auto.md" --prompt "test" --category "code-review" --dry-run 2>/dev/null)"
set -e

if ! echo "$SKIP_OUTPUT" | grep -qF "DISPATCHER:inherit"; then
  echo "  PASS: --category skips inherit dispatcher path"
  PASS=$((PASS + 1))
else
  echo "  FAIL: --category skips inherit dispatcher path"
  echo "    output=$SKIP_OUTPUT"
  FAIL=$((FAIL + 1))
fi

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
