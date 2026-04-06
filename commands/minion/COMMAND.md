---
name: minion
description: Delegate a task to any AI model via Pi CLI. Supports inline mode (--provider X --model Y "prompt"), minion-file mode (name-or-path [extra input]), mixed mode (minion file + inline overrides), and auto mode (auto on/off/status).
argument-hint: "<minion-name> [extra input]  |  --provider <p> --model <m> [--claude-skills a,b] [--pi-skills c,d] \"<prompt>\"  |  <minion-name> --provider <p> [--model <m>] [overrides...]  |  auto on|off|status"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Skill"]
---

# /minion Command

You are the entry point for the minion delegation plugin. Parse the user's arguments and dispatch to the `delegate-to-minion` skill.

## Argument Parsing

Examine the user's arguments to determine the invocation mode.

### Recognised Flags

The following flags are inline-mode flags (any of them, when present, indicates the user is providing an inline override):

`--provider`, `--model`, `--prompt`, `--thinking`, `--tools`, `--no-tools`, `--no-session`, `--max-turns`, `--append-system-prompt`, `--stream`, `--extensions`, `--pi-skills`, `--claude-skills`

### Detection Rule

1. If the first argument is `auto`, this is **auto-minion mode**.
2. Otherwise, scan for the inline-mode flags listed above.
3. Mode determination:
   - **Pure inline mode** — at least one inline flag is present AND no leading positional argument (or the only positional is a free-text prompt at the end). Use the inline values directly.
   - **Mixed mode** — at least one inline flag is present AND a non-flag positional argument appears first (it is the minion name). The minion file is loaded, and the inline flags override the file's values for those fields.
   - **Pure minion file mode** — no inline flags are present and the first positional is the minion name.

In short: a leading non-flag positional → minion name; presence of any inline flag → use overrides.

### Auto-Minion Mode Extraction

If the first argument is `auto`, extract the subcommand from the second argument:

1. **subcommand** — the second argument: `on`, `off`, or `status`. If absent, treat as missing.

## Auto-Minion Dispatch

If auto-minion mode was detected, invoke the `auto-minion` skill:

```
Skill(skill="auto-minion")
```

State the parsed results: "Auto-minion subcommand: `<on|off|status>`."

Then stop. Do not proceed to inline or minion file dispatch.

### Inline / Mixed Mode Extraction

Extract any inline override values from the recognised flags above. Each flag value is the immediately following argument. Boolean flags (`--no-tools`, `--no-session`, `--stream`) take no value.

For list flags (`--extensions`, `--pi-skills`, `--claude-skills`), the value is a comma-separated list (e.g., `--claude-skills foo,bar`).

If a leading non-flag positional argument is present, treat it as a **minion name** (mixed mode); the minion file will be loaded and inline values will override the file values for those fields. Any trailing non-flag positional (after the flags) is treated as the prompt or extra-input depending on context — pass it as `--prompt` for inline-only mode, or as `--extra-input` for mixed mode.

### Minion File Mode Extraction (no inline flags)

Extract the following from the arguments:

1. **minion_name** — the first positional argument (e.g., `security-reviewer`)
2. **extra_input** — everything after the minion name, joined as a single string. May be empty.

## Dispatch

**If auto-minion mode**: dispatch was already handled above. Do not proceed further.

**If inline or minion file mode**: invoke the `delegate-to-minion` skill and pass the parsed parameters as structured context.

Call the Skill tool:
```
Skill(skill="delegate-to-minion")
```

When you invoke the skill, state the parsed results explicitly so the skill can act on them:

<!-- Mode handoff protocol: the skill's Step 2 pattern-matches these exact phrases. Do not change the wording without updating SKILL.md Step 2. -->
- **Inline mode:** "Inline mode. Provider: `<value or missing>`. Model: `<value or missing>`. Prompt: `<value or missing>`. Overrides: `<list of any other inline flags and their values, or none>`."
- **Minion file mode:** "Minion file mode. Minion name: `<value>`. Extra input: `<value or none>`. Overrides: `<list of any inline flag overrides, or none>`."

If overrides are present in either mode, the skill will pass them through to `lib/minion-run.sh` alongside the file or inline arguments.

The skill handles all execution logic from here: Pi availability checks, validation, error messaging, and Pi invocation.

## Usage Examples

### Inline Mode

Specify provider, model, and prompt directly on the command line:

```
/minion --provider openai --model gpt-4 "Explain the builder pattern in Go"
```

```
/minion --provider anthropic --model claude-3-opus "Review this PR for security issues"
```

### Minion File Mode

Use a stored minion file by name. The minion file contains the provider, model, and base prompt:

```
/minion security-reviewer
```

Add extra input to supplement the minion's base prompt:

```
/minion security-reviewer "review auth.py for injection vulnerabilities"
```

```
/minion code-reviewer "focus on error handling in lib/parser.sh"
```

### Mixed Mode (minion file + inline overrides)

Combine a stored minion file with inline overrides. Inline values replace the file's values for those specific fields:

```
/minion security-reviewer --provider anthropic --model claude-opus-4-6
```

```
/minion code-reviewer --claude-skills hook-development "review hooks/auto-minion-hook.sh"
```

```
/minion security-reviewer --pi-skills owasp-top-10,injection-checks
```

For list overrides (`--extensions`, `--pi-skills`, `--claude-skills`), the inline value REPLACES the file's value entirely (no append).

### Loading Claude Skills

The `--claude-skills` flag (and the matching `claude-skills:` frontmatter field) loads Claude Code skill bodies into the prompt as a `## Available Skills` preamble:

```
/minion --provider anthropic --model claude-opus-4-6 --claude-skills hook-development "Design a new hook"
```

Skills are resolved from project-local (`./.claude/skills/`), user-global (`~/.claude/skills/`), or the plugin cache (`~/.claude/plugins/cache/`). Use `plugin:skill` syntax to scope to a specific plugin (e.g., `plugin-dev:hook-development`).

### Auto-Minion Mode

Enable automatic prompt routing:

```
/minion auto on
```

Check status:

```
/minion auto status
```

Disable:

```
/minion auto off
```
