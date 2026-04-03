#!/usr/bin/env bash
#
# Validates that SKILL.md contains complete minion file resolution instructions (TASK-005).
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

# Helper: assert something about the Minion File Resolution section (between ### 4. and ### 5.)
check_section4() {
  local description="$1"
  local assertion="$2"
  check "$description" env SKILL_FILE="$SKILL_FILE" python3 -c "
import os, re
content = open(os.environ['SKILL_FILE']).read()
m = re.search(r'### 4\. Minion File Resolution.*?\n(.*?)### 5\.', content, re.DOTALL)
section = m.group(1) if m else ''
$assertion
"
}

echo "=== Minion File Resolution Validation (TASK-005) ==="
echo ""

echo "-- SKILL.md Section 4: Minion File Resolution --"

check_section4 "TODO placeholder has been removed" \
  "assert 'TODO (TASK-005)' not in section"

check_section4 "detects absolute path by leading /" \
  "assert 'starts with' in section.lower() and '/' in section"

check_section4 "uses test -f for file existence check" \
  "assert 'test -f' in section"

check_section4 "checks .claude/minions/<name>.md in project directory" \
  "assert '.claude/minions/' in section and '<name>.md' in section.lower() or '.claude/minions/' in section"

check_section4 "checks home directory as fallback" \
  "s = section; assert 'HOME' in s or '~/' in s, f'expected HOME or ~/ in section'"

check_section4 "resolution order: absolute before project-local before user-global" \
  "lines = section.split('\\n'); text = section.lower(); abs_pos = text.find('absolute'); proj_pos = text.find('project'); home_pos = max(text.find('user-global'), text.find('home'), text.find('global')); assert abs_pos < proj_pos < home_pos, f'order: abs={abs_pos} proj={proj_pos} home={home_pos}'"

check_section4 "error reports searched locations" \
  "s = section.lower(); assert 'not found' in s or 'no minion' in s or 'could not' in s; assert 'search' in s or 'checked' in s or 'looked' in s"

check_section4 "error suggests creating a minion file" \
  "s = section.lower(); assert 'create' in s"

check_section4 "passes resolved absolute path forward" \
  "s = section.lower(); assert 'resolved' in s and ('absolute path' in s or 'path' in s)"

check_section4 "uses single-quoted variable assignment for security" \
  "assert \"'<\" in section or \"MINION_NAME='\" in section or \"single-quoted\" in section.lower() or \"single quote\" in section.lower()"

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
