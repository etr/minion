### TASK-004: Skill inline invocation flow

**Milestone:** M2 - Inline Invocation
**Component:** delegate-to-minion skill, /minion command
**Estimate:** M

**Goal:**
Wire the command and skill together so inline invocation executes Pi and returns output to Claude's context.

**Action Items:**
- [ ] Update COMMAND.md to detect inline mode (presence of `--provider`/`--model` flags in args)
- [ ] Update SKILL.md to invoke `lib/minion-run.sh` via Bash tool with inline params after Pi check passes
- [ ] Return Pi's full output to Claude's conversation context
- [ ] Handle missing param errors: show which param is missing and usage examples
- [ ] Handle Pi execution failure: surface stderr and exit code to user

**Dependencies:**
- Blocked by: TASK-002, TASK-003
- Blocks: TASK-005

**Acceptance Criteria:**
- `/minion --provider openai --model gpt-4 "what is 2+2"` returns Pi's response in Claude's conversation
- Missing `--model` shows usage help with both invocation modes
- Pi non-zero exit shows stderr and exit code
- Output is in Claude's context (Claude can reason about it in subsequent turns)

**Related Requirements:** PRD-MIN-REQ-004, PRD-MIN-REQ-005, PRD-MIN-REQ-014, PRD-MIN-REQ-015
**Related Decisions:** DR-002, DR-004

**Status:** Not Started
