---
name: auto-minion-hook
description: Pre-message hook that intercepts user prompts when auto-minion mode is enabled and routes them through the auto-dispatch pipeline.
hook: pre-message
allowed-tools: ["Bash", "Read", "Skill"]
---

# Auto-Minion Pre-Message Hook

This hook fires before each user message is processed. It delegates all mechanical work to `lib/auto-minion-hook.sh` and only involves Claude for result presentation or inherit-dispatcher classification.

## Hook Logic

### 1. Run the Hook Script

Write the user's message to a temporary file, then pipe it to the hook script:

```bash
PROMPT_FILE="$(mktemp)"
printf '%s' '<user_message>' > "$PROMPT_FILE"
bash lib/auto-minion-hook.sh < "$PROMPT_FILE"
```

Replace `<user_message>` with the actual user message. Use single-quote assignment to prevent shell expansion: assign the message to a variable with single quotes, write it with `printf '%s'`. If the message contains single quotes, replace each `'` with `'\''` before embedding in the single-quoted `printf` argument.

### 2. Interpret the Output

Read the `STATUS:` line from the script output and act accordingly:

#### `STATUS:DISABLED`

Auto-minion mode is not enabled. Do nothing — let the message pass through to normal handling.

#### `STATUS:BYPASS`

The message matched a bypass condition (slash command or empty). Do nothing — let the message pass through to normal handling.

#### `STATUS:ERROR`

A config or runtime error occurred. Read the `MSG:` line and present:

> **Auto-minion error:** `<message>`
>
> Check your auto-minion config or disable auto mode with `/minion auto off`.

#### `STATUS:DISPATCHED`

An external model handled the prompt. The output contains the full `auto-dispatch.sh` output with route headers and Pi response body.

Parse the output:
- `EXIT:<code>` — the auto-dispatch.sh exit code
- `SHOW_ROUTING:<true|false>` — whether to show routing attribution
- The route headers (`ROUTE:`, `PROVIDER:`, `MODEL:`, `FALLBACK:`) and body (after `---`) follow.

**On EXIT:0** (success):

If `SHOW_ROUTING:true`, present with attribution:

> [auto-minion → `<ROUTE>` via `<PROVIDER>`/`<MODEL>`]
>
> <body after --->

If `SHOW_ROUTING:false`, present the body directly without attribution.

Do not summarize or modify the output. Present it verbatim.

**On EXIT:3** (dispatcher failed, used default):

> [auto-minion → default (dispatcher unavailable) via `<PROVIDER>`/`<MODEL>`]
>
> <body after --->

**On EXIT:4** (all routes failed):

> **Auto-minion routing failed.** Both the routed model and default model returned errors.
> Falling back to Claude (native).

Then handle the user's prompt directly — respond as Claude normally would.

**On EXIT:1** (config error):

Read the `STDERR:` line and present:

> **Auto-minion config error:** `<stderr>`
>
> Check your auto-minion config or disable auto mode with `/minion auto off`.

#### `STATUS:NATIVE`

The route resolved to inherit — Claude should handle this prompt directly. Parse:
- `CATEGORY:<name>` — the matched category
- `FALLBACK:<reason>` — `none`, `dispatcher_failed`, `no_default`, etc.
- `SHOW_ROUTING:<true|false>`

If `SHOW_ROUTING:true`:

> [auto-minion → `<CATEGORY>` via Claude (native)]

Then handle the user's prompt directly as Claude normally would.

#### `STATUS:NEEDS_CLASSIFICATION`

The dispatcher is configured as `inherit` — Claude must classify the prompt. The output includes:
- `SHOW_ROUTING:<true|false>`
- `CONFIG:<path>` — the config file path
- `DISPATCHER:inherit`
- `CATEGORIES:<space-separated list>`
- `DISPATCHER_PROMPT:<prompt text>` — the classification prompt with categories and user prompt filled in

Read the categories list and the user's original prompt. Classify the prompt by deciding which category best matches. Then execute the matched category by running this exact bash snippet verbatim:

```bash
PROMPT_CONTENT="$(cat "$PROMPT_FILE")"
bash lib/auto-dispatch.sh --config "$CONFIG_PATH" --prompt "$PROMPT_CONTENT" --category "$CHOSEN_CATEGORY"
```

Where `CONFIG_PATH` comes from the `CONFIG:` line in the hook output, and `CHOSEN_CATEGORY` is the category name you selected.

IMPORTANT: Use this exact pattern. Do not inline the file contents or use string interpolation — always read from the temp file via command substitution into a variable, then pass the variable. Double-quoting prevents word splitting and globbing; safety assumes the shell does not evaluate the prompt contents as code.

After all processing is complete, clean up:

```bash
rm -f "$PROMPT_FILE"
```

Parse the output from this second invocation:
- If `NEEDS_NATIVE_HANDLING` appears: the matched category routes to Claude. Present with attribution if `SHOW_ROUTING:true`, then handle the prompt natively.
- Otherwise: the output contains route headers and Pi response body. Present using the same rules as `STATUS:DISPATCHED` above.
