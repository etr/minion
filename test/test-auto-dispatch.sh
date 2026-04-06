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

# --- Mock Pi setup ---
MOCK_DIR="$(mktemp -d)"
FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "$MOCK_DIR" "$FIXTURE_DIR"' EXIT

# Mock pi script: echoes received args, supports configurable exit code and response
cat > "$MOCK_DIR/pi" <<'MOCKEOF'
#!/usr/bin/env bash
echo "MOCK_ARGS: $*"
if [ -n "${MOCK_PI_STDERR:-}" ]; then
  echo "$MOCK_PI_STDERR" >&2
fi
if [ -n "${MOCK_PI_STDOUT:-}" ]; then
  echo "$MOCK_PI_STDOUT"
fi
exit "${MOCK_PI_EXIT_CODE:-0}"
MOCKEOF
chmod +x "$MOCK_DIR/pi"

export PATH="$MOCK_DIR:$PATH"

# --- Test helpers ---

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
