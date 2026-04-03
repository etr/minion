### TASK-003: minion-run.sh with inline mode

**Milestone:** M2 - Inline Invocation
**Component:** lib/minion-run.sh
**Estimate:** M

**Goal:**
Create the bash helper script that accepts inline parameters and executes Pi CLI.

**Action Items:**
- [x] Create `lib/minion-run.sh` with argument parsing for `--provider`, `--model`, `--prompt`
- [x] Validate all three required params; exit non-zero with missing field names if any absent
- [x] Construct Pi CLI command: `pi --provider <val> --model <val> "<prompt>"`
- [x] Execute Pi and capture stdout/stderr
- [x] Exit with Pi's exit code; output Pi's stdout on success, stderr on failure
- [x] Make script executable (`chmod +x`)

**Dependencies:**
- Blocked by: TASK-001
- Blocks: TASK-004, TASK-006

**Acceptance Criteria:**
- `./lib/minion-run.sh --provider openai --model gpt-4 --prompt "hello"` constructs correct Pi command
- Missing `--model` exits non-zero with output containing "missing: model"
- Pi's stdout is passed through on success
- Pi's stderr is passed through on failure with matching exit code
- Script is executable

**Related Requirements:** PRD-MIN-REQ-004, PRD-MIN-REQ-013, PRD-MIN-REQ-015
**Related Decisions:** DR-002, DR-003

**Status:** Complete
