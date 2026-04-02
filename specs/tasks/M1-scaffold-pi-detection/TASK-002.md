### TASK-002: Pi availability check with install offer

**Milestone:** M1 - Plugin Scaffold & Pi Detection
**Component:** delegate-to-minion skill
**Estimate:** S

**Goal:**
Detect whether Pi CLI is installed and guide the user to install it if missing.

**Action Items:**
- [x] In SKILL.md, add `which pi` / `command -v pi` check via Bash tool as first step
- [x] If Pi missing: present install offer with link to shittycodingagent.ai
- [x] If user accepts install: run Pi installation command
- [x] If user declines install: abort with clear message that Pi is required
- [x] If Pi is present: proceed silently to invocation logic

**Dependencies:**
- Blocked by: TASK-001
- Blocks: TASK-004

**Acceptance Criteria:**
- With Pi not in PATH: skill presents install offer with shittycodingagent.ai link
- Declining install: skill aborts with "Pi is required" message
- Accepting install: skill attempts installation
- With Pi in PATH: skill proceeds without any install prompts

**Related Requirements:** PRD-MIN-REQ-001, PRD-MIN-REQ-002, PRD-MIN-REQ-003
**Related Decisions:** DR-002

**Status:** In Progress
