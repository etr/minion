### TASK-008: Example minion files and error UX

**Milestone:** M4 - Polish & Distribution
**Component:** examples/, delegate-to-minion skill
**Estimate:** M

**Goal:**
Provide example minion files and ensure all error paths produce clear, actionable messages.

**Action Items:**
- [ ] Create `examples/security-reviewer.md` — minion for code security review
- [ ] Create `examples/code-explainer.md` — minion that explains code in plain language
- [ ] Add instructions in SKILL.md for copying examples to `.claude/minions/`
- [ ] Audit all error paths: Pi missing, install declined, missing inline params, file not found, missing frontmatter fields, Pi failure
- [ ] Ensure each error message includes: what went wrong and what to do about it
- [ ] Test error messages are not truncated or unclear

**Dependencies:**
- Blocked by: TASK-007
- Blocks: TASK-009

**Acceptance Criteria:**
- Example minion files have valid frontmatter with provider, model, and sensible prompts
- Copying an example to `.claude/minions/` makes it invocable by name
- Each of the 6 error paths shows a clear, actionable message
- No error exits silently or with only a generic "error" message

**Related Requirements:** PRD-MIN-REQ-002, PRD-MIN-REQ-003, PRD-MIN-REQ-005, PRD-MIN-REQ-007, PRD-MIN-REQ-010, PRD-MIN-REQ-015
**Related Decisions:** DR-002

**Status:** Not Started
