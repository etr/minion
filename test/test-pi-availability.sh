#!/usr/bin/env bash
#
# Validates that SKILL.md contains complete Pi CLI detection instructions (TASK-002).
# Exit 0 if all checks pass, non-zero otherwise.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

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

SKILL_FILE="$ROOT/skills/delegate-to-minion/SKILL.md"

# Helper: assert something about the Pi Availability section (between ### 1. and ### 2.)
check_section1() {
  local description="$1"
  local assertion="$2"
  check "$description" python3 -c "
import re
content = open('$SKILL_FILE').read()
m = re.search(r'### 1\. Check Pi Availability\n(.*?)### 2\.', content, re.DOTALL)
section = m.group(1) if m else ''
$assertion
"
}

echo "=== Pi Availability Check Validation (TASK-002) ==="
echo ""

echo "-- SKILL.md Section 1: Check Pi Availability --"

check_section1 "TODO placeholder has been removed" \
  "assert 'TODO (TASK-002)' not in section"

check_section1 "contains 'command -v pi' detection command" \
  "assert 'command -v pi' in section"

check_section1 "contains shittycodingagent.ai install link" \
  "assert 'shittycodingagent.ai' in section"

check_section1 "contains 'Pi is required' abort message" \
  "assert 'Pi is required' in section"

check_section1 "describes proceed silently when Pi is found" \
  "s = section.lower(); assert 'proceed' in s and 'silent' in s"

check_section1 "describes install attempt on user acceptance" \
  "s = section.lower(); assert 'install' in s and 'accept' in s"

check_section1 "describes abort on user decline" \
  "s = section.lower(); assert 'decline' in s"

echo ""

# --- Summary ---
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  echo "VALIDATION FAILED"
  exit 1
else
  echo "ALL CHECKS PASSED"
  exit 0
fi
