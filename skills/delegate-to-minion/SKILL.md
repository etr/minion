---
name: delegate-to-minion
description: This skill should be used when the user asks to "delegate a task", "run a minion", "use pi to run", "send to another model", or wants to dispatch work to an external AI model via Pi CLI. Handles mode detection, minion file resolution, prompt composition, error handling, and Pi availability checks.
user-invocable: false
---

# Delegate to Minion Skill

Core execution logic for dispatching tasks to external AI models via Pi CLI.

## Execution Flow

### 1. Check Pi Availability

Run this check using the Bash tool:
```bash
command -v pi
```

**If `pi` IS found** (exit code 0): proceed silently to Step 2. Do not print any message about Pi.

**If `pi` is NOT found** (non-zero exit code): present the following to the user:

> Pi CLI is not installed. Pi is required to delegate tasks to external models.
>
> You can install Pi from: https://shittycodingagent.ai (you may want to visit this URL in your browser first to verify the domain)
>
> Would you like me to attempt the installation now?

Then wait for the user's response:

- **If the user accepts** (yes, sure, ok, go ahead, install it, etc.):
  Run the Pi installation command via the Bash tool (the user will be prompted to review and approve before execution):
  ```bash
  curl -fsSL https://shittycodingagent.ai/install.sh | bash
  ```
  After installation, verify Pi is now available:
  ```bash
  command -v pi
  ```
  If verification fails, inform the user that installation did not succeed and suggest they install manually from https://shittycodingagent.ai, then abort.

- **If the user declines** (no, nope, cancel, skip, etc.):
  Respond with:
  > Pi is required to delegate tasks to external models. Please install Pi from https://shittycodingagent.ai and try again.

  Then abort. Do not proceed to any further steps.

### 2. Detect Invocation Mode

Read the context passed by the `/minion` command to determine the invocation mode:

<!-- Mode handoff protocol: these phrases are defined in COMMAND.md's Dispatch section. They must stay in sync. -->
- If the conversation context contains the phrase **"Inline mode"** followed by Provider, Model, and Prompt values: proceed to **Step 3** (Inline Invocation).
- If the conversation context contains the phrase **"Minion file mode"** followed by a Minion name: proceed to **Step 4** (Minion File Resolution).
- If the conversation context contains **neither** "Inline mode" **nor** "Minion file mode" (skill invoked directly without the command): ask the user what they want to delegate and which mode they prefer, showing both usage examples:

> **Inline mode:** `/minion --provider openai --model gpt-4 "your prompt here"`
> **Minion file mode:** `/minion <minion-name> [extra input]`

### 3. Inline Invocation (Mode 1)

Validate that all three required parameters are present: `provider`, `model`, and `prompt`.

**If any parameter is missing**, report exactly which parameter(s) are missing and show usage examples for both modes. Use this format:

> **Missing parameter(s):** `<list of missing params>`
>
> **Usage:**
> - Inline: `/minion --provider <provider> --model <model> "<prompt>"`
> - Minion file: `/minion <minion-name> [extra input]`
>
> **Example:**
> ```
> /minion --provider openai --model gpt-4 "Explain the builder pattern"
> ```

Then stop. Do not proceed to execution.

**If all three parameters are present**, proceed directly to **Step 7** (Execute via Pi CLI).

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

Invoke `lib/minion-run.sh` via the Bash tool with the resolved parameters.

**Before invoking**, verify the script exists from the current working directory:

```bash
test -f lib/minion-run.sh
```

If this fails, the working directory is not the plugin root. Inform the user that the plugin's `lib/minion-run.sh` could not be found and suggest they run the command from the plugin directory.

**Security:** To prevent shell injection, assign each user-supplied value to a shell variable using single quotes, then pass the variables to the script. Single-quoted assignments prevent `$(...)` command substitution, backtick expansion, and variable expansion. Never interpolate user values directly into double-quoted strings.

```bash
MINION_PROVIDER='<provider>'
MINION_MODEL='<model>'
MINION_PROMPT='<prompt>'
bash lib/minion-run.sh --provider "$MINION_PROVIDER" --model "$MINION_MODEL" --prompt "$MINION_PROMPT"
```

**Quoting rules:** The `<provider>` and `<model>` values are typically simple identifiers (e.g., `openai`, `gpt-4`) that need no escaping. For `<prompt>`, if the value contains single quotes, replace each `'` with `'\''` before embedding it in the single-quoted assignment.

#### On success (exit code 0):

Present Pi's stdout output to the user. The output is now part of the conversation context and available for Claude to reason about in subsequent turns. Format the response as:

> **Pi response** (via `<provider>/<model>`):
>
> <Pi's stdout output here>

Do not summarize or modify Pi's output. Present it verbatim.

#### On failure (exit code non-zero):

Surface the error clearly to the user with the exit code and any stderr output. Use this format:

> **Pi execution failed** (exit code `<N>`):
>
> <stderr output, if any>

Then provide guidance based on the exit code:
- **Exit code 1** (validation error from minion-run.sh): A required parameter was empty after extraction. Report what minion-run.sh said was missing.
- **Exit code 2** (unknown flag): An unrecognized flag was passed. Check the parameter values for accidental flag-like content.
- **Other exit codes**: These come from Pi itself. Suggest the user check their provider credentials, model name, or Pi CLI configuration.
