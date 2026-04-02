### TASK-007: Prompt composition and minion-file mode end-to-end

**Milestone:** M3 - Minion File Support
**Component:** delegate-to-minion skill, lib/minion-run.sh
**Estimate:** M

**Goal:**
Compose the final prompt from minion body + caller input and wire the complete minion-file invocation flow.

**Action Items:**
- [ ] In `minion-run.sh`, add `--extra-input` argument for caller-provided text
- [ ] Compose prompt: base prompt (markdown body) + "\n\n" + extra input when both present
- [ ] Handle no-extra-input case: use base prompt as-is
- [ ] Update SKILL.md to detect minion-file mode (first arg is not `--provider`)
- [ ] Wire full flow: resolve file (TASK-005) → call `minion-run.sh --file <path> --extra-input "..."` → return output
- [ ] Update COMMAND.md to document both invocation modes with examples

**Dependencies:**
- Blocked by: TASK-005, TASK-006
- Blocks: TASK-008

**Acceptance Criteria:**
- `/minion security-reviewer "review auth.py"` composes "base prompt\n\nreview auth.py" and executes Pi
- `/minion security-reviewer` (no extra input) uses base prompt as-is
- Pi output returns to Claude's conversation context
- COMMAND.md shows usage examples for both inline and minion-file modes

**Related Requirements:** PRD-MIN-REQ-011, PRD-MIN-REQ-012, PRD-MIN-REQ-014
**Related Decisions:** DR-002, DR-004

**Status:** Not Started
