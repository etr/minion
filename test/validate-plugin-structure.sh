#!/usr/bin/env bash
#
# Validates the plugin directory structure and manifest for TASK-001.
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

# Helper: assert a JSON field value in plugin.json
check_json_field() {
  local description="$1"
  local assertion="$2"
  check "$description" python3 -c "
import json
d = json.load(open('$ROOT/.claude-plugin/plugin.json'))
$assertion
"
}

# Helper: assert a frontmatter field exists (or matches value) in a markdown file
check_frontmatter() {
  local file="$1"
  local description="$2"
  local assertion="$3"
  check "$description" python3 -c "
import re
content = open('$file').read()
parts = content.split('---', 2)
fm = parts[1]
$assertion
"
}

echo "=== Plugin Structure Validation ==="
echo ""

# --- plugin.json ---
echo "-- plugin.json --"
PLUGIN_JSON="$ROOT/.claude-plugin/plugin.json"

check "plugin.json exists" test -f "$PLUGIN_JSON"
check "plugin.json is valid JSON" python3 -c "import json; json.load(open('$PLUGIN_JSON'))"
check_json_field "name is 'minion'" "assert d['name'] == 'minion'"
check_json_field "version follows semver X.Y.Z" "import re; assert re.match(r'^\d+\.\d+\.\d+$', d['version'])"
check_json_field "description is non-empty" "assert d.get('description', '').strip()"
check_json_field "author.name is non-empty" "assert d.get('author', {}).get('name', '').strip()"

echo ""

# --- COMMAND.md ---
echo "-- commands/minion/COMMAND.md --"
COMMAND_FILE="$ROOT/commands/minion/COMMAND.md"

check "COMMAND.md exists" test -f "$COMMAND_FILE"
check "has YAML frontmatter" python3 -c "
c = open('$COMMAND_FILE').read()
assert c.startswith('---') and len(c.split('---', 2)) >= 3
"
check_frontmatter "$COMMAND_FILE" "has 'description' field" \
  "assert re.search(r'^description:', fm, re.MULTILINE)"
check_frontmatter "$COMMAND_FILE" "has 'argument-hint' field" \
  "assert re.search(r'^argument-hint:', fm, re.MULTILINE)"

echo ""

# --- SKILL.md ---
echo "-- skills/delegate-to-minion/SKILL.md --"
SKILL_FILE="$ROOT/skills/delegate-to-minion/SKILL.md"

check "SKILL.md exists" test -f "$SKILL_FILE"
check "has YAML frontmatter" python3 -c "
c = open('$SKILL_FILE').read()
assert c.startswith('---') and len(c.split('---', 2)) >= 3
"
check_frontmatter "$SKILL_FILE" "name is 'delegate-to-minion'" \
  "m = re.search(r'^name:\s*(.+)$', fm, re.MULTILINE); assert m and m.group(1).strip() == 'delegate-to-minion'"
check_frontmatter "$SKILL_FILE" "has 'description' field" \
  "assert re.search(r'^description:', fm, re.MULTILINE)"

echo ""

# --- lib/ ---
echo "-- lib/ directory --"
check "lib/ directory exists" test -d "$ROOT/lib"

echo ""

# --- CLAUDE.md ---
echo "-- CLAUDE.md --"
check "CLAUDE.md exists" test -f "$ROOT/CLAUDE.md"
check "CLAUDE.md is non-empty" test -s "$ROOT/CLAUDE.md"

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
