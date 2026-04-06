---
name: auto-minion
description: Manages auto-minion mode — automatic prompt routing to external AI models via Pi CLI. Handles enable/disable/status and prompt dispatch with fallback to Claude.
user-invocable: false
---

# Auto-Minion Skill

Manages auto-minion mode: enabling/disabling, showing status, and dispatching prompts to the appropriate model based on category-based routing rules.

## Execution Flow

### 1. Determine Action

Read the context passed by the `/minion` command or the auto-minion hook to determine the action:

- If the context contains **"auto-minion subcommand: on"**: proceed to **Step 2** (Enable).
- If the context contains **"auto-minion subcommand: off"**: proceed to **Step 3** (Disable).
- If the context contains **"auto-minion subcommand: status"**: proceed to **Step 4** (Status).
- If the context contains **"auto-minion dispatch"** followed by a prompt: proceed to **Step 5** (Dispatch).
- Otherwise: show usage help:

> **Auto-minion mode** routes every prompt to the best model automatically.
>
> **Usage:**
> - `/minion auto on` — Enable auto-minion mode
> - `/minion auto off` — Disable auto-minion mode
> - `/minion auto status` — Show current configuration

### 2. Enable Auto-Minion Mode

#### 2a. Check Pi Availability

Run this check using the Bash tool:
```bash
command -v pi
```

**If `pi` is NOT found**: present the Pi installation guidance (same as delegate-to-minion skill Step 1) and abort.

#### 2b. Resolve Auto Config

Look for the auto-minion configuration file in order:

```bash
if test -f "./.claude/minions/auto.md"; then
  echo "FOUND:$(pwd)/.claude/minions/auto.md"
elif test -f "$HOME/.claude/minions/auto.md"; then
  echo "FOUND:$HOME/.claude/minions/auto.md"
else
  echo "NOT_FOUND"
fi
```

**If `NOT_FOUND`**: inform the user and offer to copy the example:

> **No auto-minion config found.** Searched:
>
> - `./.claude/minions/auto.md` (project-local)
> - `~/.claude/minions/auto.md` (user-global)
>
> Would you like me to copy the example config to get started?

If the user accepts, copy the example. The plugin root is the directory containing this skill (two levels up from `skills/auto-minion/`). Use the `CLAUDE_PLUGIN_DIR` environment variable if available, otherwise resolve relative to the skill file:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
mkdir -p .claude/minions
cp "$PLUGIN_ROOT/examples/auto.md" .claude/minions/auto.md
```

Then inform the user to edit it and re-run `/minion auto on`.

**If found**: proceed to 2c.

#### 2c. Validate Config

Run a dry-run dispatch to validate the config is parseable:

```bash
bash lib/auto-dispatch.sh --config "<resolved_path>" --prompt "test" --dry-run
```

**If exit code is 1**: the config has errors. Show stderr and suggest the user fix the config.

**If exit code is 0 or 3**: config is valid.

#### 2d. Write Marker File

Write the `.auto-enabled` marker file to persist the enabled state. Use the same directory as the resolved config.

First validate that `<resolved_path>` is an absolute path (starts with `/`) and contains no newline characters. If either check fails, abort with an error.

```bash
CONFIG_DIR="$(dirname "<resolved_path>")"
printf 'config=%s\n' "<resolved_path>" > "$CONFIG_DIR/.auto-enabled"
```

#### 2e. Show Confirmation

Parse the config to show a summary. Run:

```bash
bash lib/auto-dispatch.sh --config "<resolved_path>" --prompt "test" --dry-run 2>/dev/null
```

Present the enabled state to the user:

> **Auto-minion mode enabled.**
>
> Config: `<resolved_path>`
> Dispatcher: `<provider>/<model>` (or `inherit`)
> Routes:
>   - `<category>` → `<provider>/<model>` (for each configured category)
> Default: `<provider>/<model>`
>
> Every prompt will be automatically classified and routed.
> Use `/minion auto off` to disable.

### 3. Disable Auto-Minion Mode

Remove all `.auto-enabled` marker files:

```bash
rm -f ./.claude/minions/.auto-enabled "$HOME/.claude/minions/.auto-enabled" 2>/dev/null
echo "done"
```

Present:

> **Auto-minion mode disabled.** Prompts will be handled by Claude directly.

### 4. Show Status

Check for the marker file and display current configuration:

```bash
if test -f "./.claude/minions/.auto-enabled"; then
  echo "ENABLED:project-local"
  cat "./.claude/minions/.auto-enabled"
elif test -f "$HOME/.claude/minions/.auto-enabled"; then
  echo "ENABLED:user-global"
  cat "$HOME/.claude/minions/.auto-enabled"
else
  echo "DISABLED"
fi
```

**If `DISABLED`**: inform the user:

> **Auto-minion mode is OFF.** Use `/minion auto on` to enable.

**If `ENABLED`**: read the config path from the marker, run a dry-run dispatch, and present the same summary as Step 2e but prefixed with "Auto-minion mode is ON."

### 5. Dispatch Prompt

This step is invoked by the auto-minion hook when auto mode is active.

#### 5a. Read Config Path

The hook provides the config path. Read it from the marker file if needed:

```bash
if test -f "./.claude/minions/.auto-enabled"; then
  cat "./.claude/minions/.auto-enabled"
elif test -f "$HOME/.claude/minions/.auto-enabled"; then
  cat "$HOME/.claude/minions/.auto-enabled"
fi
```

Extract the `config=` value.

#### 5b. Execute Auto-Dispatch

Write the user prompt to a temporary file to avoid any shell quoting issues, then pass it via `--prompt` using a `$(cat ...)` substitution:

```bash
PROMPT_FILE="$(mktemp)"
printf '%s' '<user_prompt>' > "$PROMPT_FILE"
AUTO_CONFIG='<config_path>'
bash lib/auto-dispatch.sh --config "$AUTO_CONFIG" --prompt "$(cat "$PROMPT_FILE")"
rm -f "$PROMPT_FILE"
```

Pass `<config_path>` using single-quote assignment as shown — config paths are validated as absolute paths with no special characters.

#### 5c. Parse Output

The output from `auto-dispatch.sh` has a header section and a body section separated by `---`.

Parse the header lines:
- `ROUTE:<category>` — which category was matched
- `PROVIDER:<provider>` or `PROVIDER:inherit` — the provider for the routed model
- `MODEL:<model>` or `MODEL:inherit` — the model for the routed model
- `MINION:<name>` — if routing to a minion file
- `FALLBACK:<reason>` — `none`, `dispatcher_failed`, `dispatcher_unrecognized`, `no_default`
- `DISPATCHER:inherit` — dispatcher needs inline classification (see 5d)
- `NEEDS_NATIVE_HANDLING` — Claude should handle the prompt directly
- `NEEDS_INLINE_CLASSIFICATION` — Claude should classify the prompt (see 5d)

The body (after `---`) is the Pi output from the routed model.

#### 5d. Handle "inherit" Dispatcher

If the output contains `DISPATCHER:inherit` and `NEEDS_INLINE_CLASSIFICATION`:

The dispatcher prompt is provided in the output. Read the categories list and the user's prompt.

Classify the prompt yourself by examining the user's prompt against the available categories. Output the category name. Then re-invoke auto-dispatch with a `--category` override (or simply invoke `minion-run.sh` directly for the matched category's provider/model).

In practice: read the category list, decide which category best matches the user's prompt, then execute the corresponding model via Pi CLI using `lib/minion-run.sh`.

#### 5e. Handle "inherit" Route

If `PROVIDER:inherit` and `MODEL:inherit`: the prompt should be handled by Claude Code's native model. Simply pass through — do not invoke Pi. Present:

> [auto-minion → `<category>` via Claude (native)]

Then let Claude handle the prompt directly in conversation.

#### 5f. Present Results

**On success (exit 0):**

If `show-routing` is enabled in the config, present the routing attribution before the output:

> [auto-minion → `<category>` via `<provider>`/`<model>`]
>
> <Pi output>

If `show-routing` is not enabled, present the Pi output directly without attribution.

Do not summarize or modify Pi's output. Present it verbatim.

**On exit 3 (dispatcher failed, used default):**

> [auto-minion → default (dispatcher unavailable) via `<provider>`/`<model>`]
>
> <Pi output>

**On exit 4 (all routes failed):**

> **Auto-minion routing failed.** Both the routed model and default model returned errors.
> Falling back to Claude (native).

Then handle the user's prompt directly with Claude — respond to their original prompt as Claude normally would.

**On exit 1 (config error):**

> **Auto-minion config error:** `<stderr>`
>
> Please check your auto-minion config or disable auto mode with `/minion auto off`.
