---
name: minion
description: Delegate a task to any AI model via Pi CLI. Supports inline mode (--provider X --model Y "prompt") and minion-file mode (name-or-path [extra input]).
argument-hint: "--provider <provider> --model <model> \"<prompt>\"  OR  <minion-name> [extra input]"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Skill"]
---

# /minion Command

You are the entry point for the minion delegation plugin. Parse the user's arguments and dispatch to the `delegate-to-minion` skill.

## Argument Parsing

Detect which invocation mode the user intended:

### Mode 1: Inline
Arguments contain `--provider` and `--model` flags with a quoted prompt.
Example: `/minion --provider openai --model gpt-4 "Review this code for security issues"`

### Mode 2: Minion File
First argument is a minion name or path, optionally followed by extra input.
Example: `/minion security-reviewer Check the auth module`

## Dispatch

Once you have parsed the arguments, invoke the `delegate-to-minion` skill with the resolved parameters. The skill handles all execution logic: Pi availability checks, minion file resolution, prompt composition, and Pi invocation.

Call the Skill tool:
```
Skill(skill="delegate-to-minion")
```

Pass the parsed arguments as context in your conversation. The skill will take over from here.
