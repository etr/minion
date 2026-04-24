---
name: Minion Plugin Setup
description: Minion is a Claude Code plugin (markdown+JSON+bash). No package manager. Tests are bash scripts in test/. Worktrees at .worktrees/.
type: project
---

Minion is a Claude Code plugin that bridges to Pi CLI for multi-model delegation.

**Why:** Enables dispatching tasks to any AI model without leaving Claude Code.

**How to apply:**
- No npm/yarn/pip -- pure markdown + JSON + bash project
- Tests: each `test/test-*.sh` is independently runnable. Run them all in a loop to verify everything green. There is no aggregator script.
- Tests use a mock `pi` binary on PATH (`MOCK_DIR=$(mktemp -d); cat > "$MOCK_DIR/pi" <<'EOF'...echo "MOCK_ARGS: $*"...EOF; chmod +x; export PATH="$MOCK_DIR:$PATH"`). Never hit the real Pi CLI in tests.
- Plugin structure follows Claude Code conventions: `.claude-plugin/plugin.json`, `commands/<name>/COMMAND.md`, `skills/<name>/SKILL.md`, `lib/`
- COMMAND.md frontmatter: name, description, argument-hint, allowed-tools
- SKILL.md frontmatter: name, description, user-invocable
- Worktree dir: `.worktrees/` (gitignored)
- Base branch at start: `master` (initial commit is on master, main branch is `main`)
- `lib/minion-run.sh` uses `set -uo pipefail` (no `-e`). Don't accidentally add `set -e`.
- Frontmatter is FLAT YAML parsed with sed/awk. List fields use `  - item` (two-space indent). The `parse_field` helper validates field names against `^[a-zA-Z0-9_-]+$` to prevent sed regex injection.
- Skill name validation for path traversal: `^[a-zA-Z0-9._-]+$` (allows dots).
- When capturing function output via `$(...)` in bash, `exit N` inside the function only exits the subshell — propagate the rc explicitly via `RC=$?; [ "$RC" != 0 ] && exit "$RC"`.
- Tests use `grep -qF -- "---"` (the `--` is required when the pattern starts with `-`).
