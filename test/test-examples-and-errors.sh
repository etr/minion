#!/usr/bin/env bash
#
# Tests for TASK-008: Example minion files and error UX.
# Validates example files, error message quality in minion-run.sh, and SKILL.md error guidance.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MINION_RUN="$ROOT/lib/minion-run.sh"
SKILL_FILE="$ROOT/skills/delegate-to-minion/SKILL.md"

PASS=0
FAIL=0

# Mock Pi setup
MOCK_DIR="$(mktemp -d)"
trap 'rm -rf "$MOCK_DIR"' EXIT

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

# run_and_check — run a command and verify exit code, stdout pattern, stderr pattern
# Usage: run_and_check "desc" expected_exit "stdout_pat" "stderr_pat" -- cmd args...
run_and_check() {
  local description="$1"
  local expected_exit="$2"
  local stdout_pattern="$3"
  local stderr_pattern="$4"
  shift 4
  # consume the -- separator
  if [ "${1:-}" = "--" ]; then shift; fi

  local stdout stderr actual_exit
  stdout="$("$@" 2>"$MOCK_DIR/_stderr" || true)"
  actual_exit=${PIPESTATUS[0]:-$?}
  stderr="$(cat "$MOCK_DIR/_stderr")"

  # Re-run to get real exit code
  "$@" >"$MOCK_DIR/_stdout" 2>"$MOCK_DIR/_stderr"
  actual_exit=$?
  stdout="$(cat "$MOCK_DIR/_stdout")"
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
      echo "    exit: expected=$expected_exit actual=$actual_exit"
    fi
    if [ -n "$stdout_pattern" ] && ! echo "$stdout" | grep -qF -- "$stdout_pattern"; then
      echo "    stdout missing: '$stdout_pattern'"
    fi
    if [ -n "$stderr_pattern" ] && ! echo "$stderr" | grep -qF -- "$stderr_pattern"; then
      echo "    stderr missing: '$stderr_pattern'"
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

# Helper: assert something about a section of SKILL.md using Python
check_skill_section() {
  local description="$1"
  local section_regex="$2"
  local assertion="$3"
  check "$description" env SKILL_FILE="$SKILL_FILE" python3 -c "
import os, re
content = open(os.environ['SKILL_FILE']).read()
m = re.search(r'$section_regex', content, re.DOTALL)
section = m.group(1) if m else ''
assert section, 'Section not found'
$assertion
"
}

echo "=== TASK-008: Example Minion Files and Error UX ==="
echo ""

# ============================================================
# Phase 1: Example file validation
# ============================================================
echo "-- Example file validation --"

EXAMPLE_SR="$ROOT/examples/security-reviewer.md"
EXAMPLE_CE="$ROOT/examples/code-explainer.md"

check "security-reviewer.md exists" test -f "$EXAMPLE_SR"
check "code-explainer.md exists" test -f "$EXAMPLE_CE"

# Frontmatter validation with Python
check "security-reviewer has provider field" python3 -c "
c = open('$EXAMPLE_SR').read()
parts = c.split('---', 2)
assert len(parts) >= 3, 'no frontmatter delimiters'
fm = parts[1]
assert 'provider:' in fm, 'missing provider field'
"

check "security-reviewer has model field" python3 -c "
c = open('$EXAMPLE_SR').read()
parts = c.split('---', 2)
fm = parts[1]
assert 'model:' in fm, 'missing model field'
"

check "security-reviewer has non-empty body" python3 -c "
c = open('$EXAMPLE_SR').read()
parts = c.split('---', 2)
assert len(parts) >= 3, 'no body'
body = parts[2].strip()
assert len(body) > 20, 'body too short'
"

check "security-reviewer references security concepts" python3 -c "
c = open('$EXAMPLE_SR').read().lower()
assert 'security' in c or 'vulnerabilit' in c or 'owasp' in c, 'no security concepts'
"

check "code-explainer has provider field" python3 -c "
c = open('$EXAMPLE_CE').read()
parts = c.split('---', 2)
assert len(parts) >= 3, 'no frontmatter delimiters'
fm = parts[1]
assert 'provider:' in fm, 'missing provider field'
"

check "code-explainer has model field" python3 -c "
c = open('$EXAMPLE_CE').read()
parts = c.split('---', 2)
fm = parts[1]
assert 'model:' in fm, 'missing model field'
"

check "code-explainer has non-empty body" python3 -c "
c = open('$EXAMPLE_CE').read()
parts = c.split('---', 2)
assert len(parts) >= 3, 'no body'
body = parts[2].strip()
assert len(body) > 20, 'body too short'
"

check "code-explainer references explanation concepts" python3 -c "
c = open('$EXAMPLE_CE').read().lower()
assert 'explain' in c or 'plain language' in c or 'understand' in c, 'no explanation concepts'
"

# ============================================================
# Phase 2: Example files work with minion-run.sh
# ============================================================
echo ""
echo "-- Example files work with minion-run.sh --"

run_and_check \
  "security-reviewer passes provider and model to mock pi" \
  0 \
  "--provider" \
  "" \
  -- bash "$MINION_RUN" --file "$EXAMPLE_SR"

run_and_check \
  "security-reviewer passes model to mock pi" \
  0 \
  "--model" \
  "" \
  -- bash "$MINION_RUN" --file "$EXAMPLE_SR"

run_and_check \
  "code-explainer passes provider and model to mock pi" \
  0 \
  "--provider" \
  "" \
  -- bash "$MINION_RUN" --file "$EXAMPLE_CE"

run_and_check \
  "code-explainer passes model to mock pi" \
  0 \
  "--model" \
  "" \
  -- bash "$MINION_RUN" --file "$EXAMPLE_CE"

# ============================================================
# Phase 3: SKILL.md copy instructions
# ============================================================
echo ""
echo "-- SKILL.md copy instructions --"

check "SKILL.md contains section about example files" python3 -c "
c = open('$SKILL_FILE').read().lower()
assert 'example' in c and 'minion' in c and ('file' in c or 'using' in c), 'no example file section'
"

check "SKILL.md references examples/ directory" python3 -c "
c = open('$SKILL_FILE').read()
assert 'examples/' in c, 'does not reference examples/ directory'
"

check "SKILL.md references .claude/minions/ as target" python3 -c "
c = open('$SKILL_FILE').read()
assert '.claude/minions/' in c, 'does not reference .claude/minions/ target'
"

check "SKILL.md mentions copy action" python3 -c "
c = open('$SKILL_FILE').read().lower()
assert 'copy' in c or 'cp ' in c, 'does not mention copy action'
"

# ============================================================
# Phase 4: Error message quality in minion-run.sh
# ============================================================
echo ""
echo "-- Error message quality in minion-run.sh --"

# Missing frontmatter fields (missing both)
MINFILE_NOBOTH="$(create_minion_file "---
---
Just a body.")"

run_and_check \
  "missing both frontmatter fields: stderr contains 'missing'" \
  1 \
  "" \
  "missing" \
  -- bash "$MINION_RUN" --file "$MINFILE_NOBOTH"

# Check that the missing message mentions both fields
check "missing both: stderr lists 'provider'" python3 -c "
import subprocess
r = subprocess.run(['bash', '$MINION_RUN', '--file', '$MINFILE_NOBOTH'], capture_output=True, text=True)
assert 'provider' in r.stderr, f'stderr={r.stderr!r}'
"

check "missing both: stderr lists 'model'" python3 -c "
import subprocess
r = subprocess.run(['bash', '$MINION_RUN', '--file', '$MINFILE_NOBOTH'], capture_output=True, text=True)
assert 'model' in r.stderr, f'stderr={r.stderr!r}'
"

# Missing frontmatter fields (missing just provider)
MINFILE_NOPROV="$(create_minion_file "---
model: gpt-4
---
Just a body.")"

check "missing provider only: stderr contains 'provider'" python3 -c "
import subprocess
r = subprocess.run(['bash', '$MINION_RUN', '--file', '$MINFILE_NOPROV'], capture_output=True, text=True)
assert r.returncode == 1
assert 'provider' in r.stderr, f'stderr={r.stderr!r}'
"

check "missing provider only: stderr does NOT contain 'model'" python3 -c "
import subprocess
r = subprocess.run(['bash', '$MINION_RUN', '--file', '$MINFILE_NOPROV'], capture_output=True, text=True)
assert 'model' not in r.stderr, f'stderr should not mention model: {r.stderr!r}'
"

# File not found
check "file not found: stderr contains 'not found'" python3 -c "
import subprocess
r = subprocess.run(['bash', '$MINION_RUN', '--file', '/nonexistent/path/foo.md'], capture_output=True, text=True)
assert r.returncode == 1
assert 'not found' in r.stderr.lower(), f'stderr={r.stderr!r}'
"

check "file not found: stderr contains the path" python3 -c "
import subprocess
r = subprocess.run(['bash', '$MINION_RUN', '--file', '/nonexistent/path/foo.md'], capture_output=True, text=True)
assert '/nonexistent/path/foo.md' in r.stderr, f'stderr={r.stderr!r}'
"

# Missing inline params (missing all)
check "missing all inline: stderr contains 'missing'" python3 -c "
import subprocess
r = subprocess.run(['bash', '$MINION_RUN'], capture_output=True, text=True)
assert r.returncode == 1
assert 'missing' in r.stderr.lower(), f'stderr={r.stderr!r}'
"

check "missing all inline: stderr lists provider, model, prompt" python3 -c "
import subprocess
r = subprocess.run(['bash', '$MINION_RUN'], capture_output=True, text=True)
assert 'provider' in r.stderr, f'stderr={r.stderr!r}'
assert 'model' in r.stderr, f'stderr={r.stderr!r}'
assert 'prompt' in r.stderr, f'stderr={r.stderr!r}'
"

# Missing inline params (missing just prompt)
check "missing prompt only: stderr contains 'prompt'" python3 -c "
import subprocess
r = subprocess.run(['bash', '$MINION_RUN', '--provider', 'openai', '--model', 'gpt-4'], capture_output=True, text=True)
assert r.returncode == 1
assert 'prompt' in r.stderr, f'stderr={r.stderr!r}'
"

check "missing prompt only: stderr does NOT mention 'provider'" python3 -c "
import subprocess
r = subprocess.run(['bash', '$MINION_RUN', '--provider', 'openai', '--model', 'gpt-4'], capture_output=True, text=True)
assert 'provider' not in r.stderr, f'stderr should not mention provider: {r.stderr!r}'
"

# Pi failure passthrough
MINFILE_PIFAIL="$(create_minion_file "---
provider: openai
model: gpt-4
---
test prompt")"

check "pi failure: exit code passes through" python3 -c "
import subprocess, os
env = os.environ.copy()
env['MOCK_PI_EXIT_CODE'] = '42'
env['MOCK_PI_STDERR'] = 'pi error detail'
r = subprocess.run(['bash', '$MINION_RUN', '--file', '$MINFILE_PIFAIL'], capture_output=True, text=True, env=env)
assert r.returncode == 42, f'exit={r.returncode}'
"

check "pi failure: stderr preserved" python3 -c "
import subprocess, os
env = os.environ.copy()
env['MOCK_PI_EXIT_CODE'] = '42'
env['MOCK_PI_STDERR'] = 'pi error detail'
r = subprocess.run(['bash', '$MINION_RUN', '--file', '$MINFILE_PIFAIL'], capture_output=True, text=True, env=env)
assert 'pi error detail' in r.stderr, f'stderr={r.stderr!r}'
"

# ============================================================
# Phase 5: Error message quality in SKILL.md
# ============================================================
echo ""
echo "-- Error message quality in SKILL.md --"

# Pi missing section
check_skill_section \
  "Pi missing section: contains 'not installed' or 'not found'" \
  '### 1\. Check Pi Availability(.*?)###' \
  "s = section.lower()
assert 'not installed' in s or 'not found' in s, 'Pi missing section needs not installed/not found'"

check_skill_section \
  "Pi missing section: contains 'install'" \
  '### 1\. Check Pi Availability(.*?)###' \
  "s = section.lower()
assert 'install' in s, 'Pi missing section needs install guidance'"

check_skill_section \
  "Pi missing section: contains URL" \
  '### 1\. Check Pi Availability(.*?)###' \
  "assert 'shittycodingagent.ai' in section, 'Pi missing section needs install URL'"

# Missing inline params section
check_skill_section \
  "Missing inline params section: contains usage or example" \
  '### 3\. Inline Invocation(.*?)###' \
  "s = section.lower()
assert 'usage' in s or 'example' in s, 'inline section needs usage guidance'"

# File not found section (capture up to next section-level ### N.)
check_skill_section \
  "File not found section: contains 'not found'" \
  '### 4\. Minion File Resolution(.*?)### \d' \
  "s = section.lower()
assert 'not found' in s, 'file resolution section needs not found error'"

check_skill_section \
  "File not found section: contains actionable guidance" \
  '### 4\. Minion File Resolution(.*?)### \d' \
  "s = section.lower()
assert 'create' in s or 'add' in s or 'check' in s, 'file resolution section needs actionable guidance'"

# Exit code 1 handling — missing frontmatter
check_skill_section \
  "Exit code 1 section: contains guidance about required fields" \
  '#### On failure(.*?)$' \
  "s = section.lower()
assert 'provider' in s or 'required' in s or 'frontmatter' in s or 'missing' in s, 'exit code 1 handling needs field guidance'"

check_skill_section \
  "Exit code 1 section: contains troubleshooting for pi failures" \
  '#### On failure(.*?)$' \
  "s = section.lower()
assert 'exit code' in s, 'failure section needs exit code mention'
assert 'credential' in s or 'provider' in s or 'check' in s or 'troubleshoot' in s, 'failure section needs troubleshooting guidance'"

# Enhanced exit code 1: missing frontmatter template with example
check_skill_section \
  "Exit code 1 section: missing frontmatter shows example frontmatter" \
  '#### On failure(.*?)$' \
  "assert 'provider:' in section and 'model:' in section, 'exit code 1 handling needs example frontmatter with provider: and model:'"

# Enhanced exit code 1: file-not-found handling references the path
check_skill_section \
  "Exit code 1 section: file-not-found guidance references file path" \
  '#### On failure(.*?)$' \
  "s = section.lower()
assert 'file not found' in s or 'not found' in s, 'exit code 1 handling needs file-not-found template'"

# ============================================================
# Summary
# ============================================================
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  echo "TESTS FAILED"
  exit 1
else
  echo "ALL TESTS PASSED"
  exit 0
fi
