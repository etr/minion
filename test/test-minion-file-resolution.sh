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

check_section4 "Section 4 exists and is non-empty" \
  "assert section, 'Section 4 not found in SKILL.md'"

check_section4 "TODO placeholder has been removed" \
  "assert 'TODO (TASK-005)' not in section"

check_section4 "detects absolute path by leading /" \
  "assert 'starts with' in section.lower() and '/' in section"

check_section4 "uses test -f for file existence check" \
  "assert 'test -f' in section"

check_section4 "checks .claude/minions/<name>.md in project directory" \
  "assert ('.claude/minions/' in section) and ('<name>.md' in section.lower())"

check_section4 "checks home directory as fallback" \
  "s = section; assert 'HOME' in s or '~/' in s, f'expected HOME or ~/ in section'"

check_section4 "resolution order: absolute before project-local before user-global" \
  "text = section.lower()
abs_pos = text.find('absolute')
proj_pos = text.find('project-local')
global_pos = text.find('user-global')
assert abs_pos >= 0, 'absolute not found'
assert proj_pos >= 0, 'project-local not found'
assert global_pos >= 0, 'user-global not found'
assert abs_pos < proj_pos < global_pos, f'order: abs={abs_pos} proj={proj_pos} global={global_pos}'
"

check_section4 "error reports searched locations" \
  "s = section.lower()
assert 'not found' in s or 'no minion' in s or 'could not' in s
assert 'search' in s or 'checked' in s or 'looked' in s
assert '.claude/minions/' in section, 'error section must reference .claude/minions/ path pattern'
# Both project-local and user-global paths must appear in the not-found error output
assert 'HOME' in section or '~/' in section, 'error output must show the user-global path (HOME or ~/)'
"

check_section4 "Case A absolute-path-not-found has an error message" \
  "import re
case_a = re.search(r'Case A.*?Case B', section, re.DOTALL)
assert case_a, 'Case A section not found'
case_a_text = case_a.group(0).lower()
assert 'not found' in case_a_text or 'does not exist' in case_a_text or 'could not' in case_a_text, 'Case A must report an error when the absolute path does not exist'
"

check_section4 "error suggests creating a minion file" \
  "s = section.lower(); assert 'create' in s"

check_section4 "passes resolved absolute path forward" \
  "s = section.lower(); assert 'resolved' in s and ('absolute path' in s or 'path' in s)"

check_section4 "uses single-quoted variable assignment for security" \
  "assert \"'<\" in section or \"MINION_NAME='\" in section or \"single-quoted\" in section.lower() or \"single quote\" in section.lower()"

check_section4 "Case A test -f uses double-quoted variable (not single-quoted)" \
  "import re
# Find the Case A bash snippet - the test -f for absolute path
# It must use double quotes around the variable, not single quotes
case_a = re.search(r'Case A.*?Case B', section, re.DOTALL)
assert case_a, 'Case A section not found'
case_a_text = case_a.group(0)
# Must NOT have test -f with single-quoted variable
assert \"test -f '\$MINION_NAME'\" not in case_a_text, 'test -f uses single-quoted variable - shell will not expand it'
# Must have test -f with double-quoted variable
assert 'test -f \"\$MINION_NAME\"' in case_a_text, 'test -f must use double-quoted variable for expansion'
"

check_section4 "validates minion name against path traversal" \
  "s = section.lower()
assert 'path traversal' in s or ('valid' in s and ('character' in s or 'alphanumeric' in s)) or 'grep' in section, 'must validate minion name characters to prevent path traversal'
"

check_section4 "structured output protocol tokens FOUND:, NOT_FOUND, and SEARCHED: are present" \
  "assert 'FOUND:' in section, 'section must contain FOUND: token for machine-readable output'
assert 'NOT_FOUND' in section, 'section must contain NOT_FOUND token for machine-readable output'
assert 'SEARCHED:' in section, 'section must contain SEARCHED: token for machine-readable output'
"

check_section4 "invalid name error message references allowed characters" \
  "import re
# Find the validation-fail area: text after the grep validation through the next heading or Case boundary
fail_area = re.search(r'(validation fails|invalid|not valid|not allowed).*?(####|\Z)', section, re.DOTALL | re.IGNORECASE)
assert fail_area, 'Could not find validation-fail area in section 4'
fail_text = fail_area.group(0).lower()
# The error message must use descriptive language about allowed characters (not just a regex class)
assert 'letter' in fail_text or 'alphanumeric' in fail_text or 'hyphens' in fail_text, \
  'error message for invalid names must use descriptive language (letters, alphanumeric, or hyphens) to explain allowed characters'
# The section must also contain the character class pattern for the actual validation
assert '[a-zA-Z0-9' in section, 'section must contain character class pattern [a-zA-Z0-9 for validation'
"

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
