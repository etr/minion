---
name: delegate-to-minion
description: This skill should be used when the user asks to "delegate a task", "run a minion", "use pi to run", "send to another model", or wants to dispatch work to an external AI model via Pi CLI. Handles mode detection, minion file resolution, prompt composition, error handling, and Pi availability checks.
user-invocable: false
---

# Delegate to Minion Skill

Core execution logic for dispatching tasks to external AI models via Pi CLI.

## Execution Flow

### 1. Check Pi Availability
<!-- TODO (TASK-002): Implement Pi CLI detection -->
Check if `pi` is available in PATH:
```bash
command -v pi
```
- If not found: offer installation instructions from shittycodingagent.ai
- If user declines: abort with clear message that Pi is required

### 2. Detect Invocation Mode
<!-- TODO (TASK-004): Implement mode detection logic -->
Determine whether the user is using:
- **Inline mode**: `--provider`, `--model`, and prompt are provided directly
- **Minion file mode**: a minion name or file path is provided

### 3. Inline Invocation (Mode 1)
<!-- TODO (TASK-004): Implement inline invocation -->
Validate that all three required parameters are present: `provider`, `model`, `prompt`.
If any are missing, report which parameter is missing and show usage examples.

Construct Pi CLI command:
```bash
pi --provider <provider> --model <model> "<prompt>"
```

### 4. Minion File Resolution (Mode 2)
<!-- TODO (TASK-005): Implement minion file resolution -->
Resolve the minion file by checking in order:
1. Argument as absolute path (if starts with `/`)
2. `./.claude/minions/<name>.md` (project-local)
3. `~/.claude/minions/<name>.md` (user-global)

If not found at any path: report the paths searched and fail with actionable error.

### 5. Parse Minion File Frontmatter
<!-- TODO (TASK-006): Implement frontmatter parsing -->
Parse YAML frontmatter for Pi CLI parameters:
- Required: `provider`, `model`
- Optional: `thinking`, `tools`, `no-tools`, `no-session`, `extensions` (list), `skills` (list), `max-turns`, `append-system-prompt`, `stream`

If required fields missing: report which fields and abort.

### 6. Compose Prompt
<!-- TODO (TASK-007): Implement prompt composition -->
Combine the minion's base prompt (markdown body after frontmatter) with any caller-provided extra input:
- If extra input provided: base prompt + "\n\n" + extra input
- If no extra input: use base prompt as-is

### 7. Execute via Pi CLI
<!-- TODO (TASK-004/TASK-007): Implement Pi execution -->
Invoke `lib/minion-run.sh` via the Bash tool with the resolved parameters.

Capture Pi's full stdout and return it into the conversation context.

On failure (non-zero exit code): surface stderr and exit code to the user.
