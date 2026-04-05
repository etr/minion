#!/usr/bin/env bash
#
# Tests for TASK-009: README.md and LICENSE file.
# Validates README covers both invocation modes, minion file format, all
# frontmatter fields, examples, and installation. Validates LICENSE is MIT.
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

README="$ROOT/README.md"
LICENSE="$ROOT/LICENSE"

# ================================================================
echo "=== Phase 1: LICENSE file ==="
# ================================================================

check "LICENSE exists" test -f "$LICENSE"
check "LICENSE non-empty" test -s "$LICENSE"
check "contains 'MIT License'" grep -qi "MIT License" "$LICENSE"
check "contains copyright 'Sebastiano Merlino'" grep -q "Sebastiano Merlino" "$LICENSE"
check "contains 'Permission is hereby granted'" grep -q "Permission is hereby granted" "$LICENSE"
check "contains 'AS IS'" grep -q "AS IS" "$LICENSE"

# ================================================================
echo ""
echo "=== Phase 2: README existence ==="
# ================================================================

check "README.md exists" test -f "$README"
check "README.md non-empty (100+ lines)" bash -c "[ \$(wc -l < '$README') -ge 100 ]"
check "README starts with '# '" grep -qm1 '^# ' "$README"
check "title contains 'minion'" bash -c "head -1 '$README' | grep -qi 'minion'"

# ================================================================
echo ""
echo "=== Phase 3: Required sections (H2 headings) ==="
# ================================================================

check "has Installation section" grep -qE '^## .*[Ii]nstall' "$README"
check "has Usage section" grep -qE '^## .*[Uu]sage' "$README"
check "has Minion File Format section" grep -qiE '^##+ .*[Mm]inion [Ff]ile [Ff]ormat' "$README"
check "has Frontmatter Fields section" grep -qiE '^##+ .*[Ff]rontmatter [Ff]ield' "$README"

# ================================================================
echo ""
echo "=== Phase 4: Inline mode content ==="
# ================================================================

check "mentions --provider flag" grep -q "\-\-provider" "$README"
check "mentions --model flag" grep -q "\-\-model" "$README"
check "inline example with /minion --provider" grep -q "/minion --provider" "$README"
check "references 'inline'" grep -qi "inline" "$README"

# ================================================================
echo ""
echo "=== Phase 5: Minion-file mode content ==="
# ================================================================

check "references file mode" grep -qiE "minion[- ]file|file[- ]mode" "$README"
check "references .claude/minions/ path" grep -q "\.claude/minions/" "$README"
check "example like /minion security-reviewer or /minion <name>" grep -qE '/minion (security-reviewer|<[^>]+>)' "$README"
check "file resolution order mentioned" grep -qi "resolution" "$README"

# ================================================================
echo ""
echo "=== Phase 6: Frontmatter field table ==="
# ================================================================

# All 11 fields must appear
for field in provider model thinking tools no-tools no-session extensions skills max-turns append-system-prompt stream; do
  check "frontmatter field '$field' documented" grep -qw "$field" "$README"
done

check "table structure (pipe chars)" grep -q '|' "$README"
check "'required' keyword present in table" grep -qi "required" "$README"
check "'provider' row present in frontmatter table" grep -qiE '\|\s*`?provider`?' "$README"
check "'model' row present in frontmatter table" grep -qiE '\|\s*`?model`?' "$README"

# ================================================================
echo ""
echo "=== Phase 7: Examples section ==="
# ================================================================

check "references examples/ directory" grep -q "examples/" "$README"
check "references security-reviewer" grep -q "security-reviewer" "$README"
check "references code-explainer" grep -q "code-explainer" "$README"

# ================================================================
echo ""
echo "=== Phase 8: Installation command ==="
# ================================================================

check "exact install command" grep -q "claude plugin install minion@groundwork-marketplace" "$README"
check "Pi CLI prerequisite (pi or shittycodingagent)" grep -qE "shittycodingagent\.ai|\bpi\b.*CLI|Pi CLI" "$README"

# ================================================================
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  echo "VALIDATION FAILED"
  exit 1
fi
echo "ALL CHECKS PASSED"
