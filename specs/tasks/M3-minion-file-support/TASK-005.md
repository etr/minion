### TASK-005: Minion file resolution

**Milestone:** M3 - Minion File Support
**Component:** delegate-to-minion skill
**Estimate:** S

**Goal:**
Resolve a minion name or path to an actual file on disk using the 3-tier lookup order.

**Action Items:**
- [ ] In SKILL.md, add resolution logic when first arg is not `--provider` (minion-file mode)
- [ ] If arg starts with `/`: treat as absolute path, check file exists
- [ ] Else check `./.claude/minions/<name>.md`
- [ ] Else check `~/.claude/minions/<name>.md`
- [ ] On resolution failure: report all paths searched and abort with actionable error
- [ ] Pass resolved absolute path to `minion-run.sh`

**Dependencies:**
- Blocked by: TASK-004
- Blocks: TASK-007

**Acceptance Criteria:**
- Absolute path `/home/user/my-minion.md` resolves directly
- Name `security-reviewer` resolves from `./.claude/minions/security-reviewer.md` if present
- Name falls back to `~/.claude/minions/security-reviewer.md` when project-local missing
- Nonexistent name shows all 3 paths that were searched
- Error message suggests creating a minion file

**Related Requirements:** PRD-MIN-REQ-006, PRD-MIN-REQ-007
**Related Decisions:** DR-002

**Status:** Not Started
