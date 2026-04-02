### TASK-001: Plugin directory structure and manifest

**Milestone:** M1 - Plugin Scaffold & Pi Detection
**Component:** Plugin structure
**Estimate:** S

**Goal:**
Establish the Claude Code plugin skeleton so it can be installed and recognized.

**Action Items:**
- [ ] Create `.claude-plugin/plugin.json` with name "minion", version "0.1.0", description, author
- [ ] Create `commands/minion/COMMAND.md` skeleton with frontmatter (name, description, argument hints for both modes)
- [ ] Create `skills/delegate-to-minion/SKILL.md` skeleton with frontmatter (name, description, when-to-use)
- [ ] Create `lib/` directory
- [ ] Create `CLAUDE.md` with plugin development notes

**Dependencies:**
- Blocked by: None
- Blocks: TASK-002, TASK-003

**Acceptance Criteria:**
- Plugin installs in Claude Code via `claude plugin install` (from local path)
- `/minion` appears in command list
- `delegate-to-minion` appears in skills list
- Typecheck passes (N/A — markdown + JSON only)

**Related Requirements:** DR-001, DR-004
**Related Decisions:** DR-001, DR-004

**Status:** Not Started
