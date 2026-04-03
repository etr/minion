---
name: minion
description: Delegate a task to any AI model via Pi CLI. Supports inline mode (--provider X --model Y "prompt") and minion-file mode (name-or-path [extra input]).
argument-hint: "--provider <provider> --model <model> \"<prompt>\"  OR  <minion-name> [extra input]"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Skill"]
---

# /minion Command

You are the entry point for the minion delegation plugin. Parse the user's arguments and dispatch to the `delegate-to-minion` skill.

## Argument Parsing

Examine the user's arguments to determine the invocation mode.

### Detection Rule

If the arguments contain the `--provider` or `--model` flag, this is **inline mode**.
Otherwise, this is **minion file mode**.

### Inline Mode Extraction

Extract the following from the arguments:

1. **provider** — the value immediately after `--provider` (e.g., `--provider openai` → `openai`)
2. **model** — the value immediately after `--model` (e.g., `--model gpt-4` → `gpt-4`)
3. **prompt** — the remaining argument that is not a flag or flag-value. This is typically a quoted string (e.g., `"Review this code"`). If there are multiple non-flag tokens, join them as a single prompt string.

It is acceptable for any of these to be absent at this stage; the skill will validate completeness and report errors.

### Minion File Mode Extraction

Extract the following from the arguments:

1. **minion_name** — the first positional argument (e.g., `security-reviewer`)
2. **extra_input** — everything after the minion name, joined as a single string. May be empty.

## Dispatch

Invoke the `delegate-to-minion` skill and pass the parsed parameters as structured context.

Call the Skill tool:
```
Skill(skill="delegate-to-minion")
```

When you invoke the skill, state the parsed results explicitly so the skill can act on them:

<!-- Mode handoff protocol: the skill's Step 2 pattern-matches these exact phrases. Do not change the wording without updating SKILL.md Step 2. -->
- **Inline mode:** "Inline mode. Provider: `<value or missing>`. Model: `<value or missing>`. Prompt: `<value or missing>`."
- **Minion file mode:** "Minion file mode. Minion name: `<value>`. Extra input: `<value or none>`."

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
