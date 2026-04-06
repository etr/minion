---
name: auto-minion-hook
description: Pre-message hook that intercepts user prompts when auto-minion mode is enabled and routes them through the auto-dispatch pipeline.
hook: pre-message
allowed-tools: ["Bash", "Read", "Skill"]
---

# Auto-Minion Pre-Message Hook

This hook fires before each user message is processed. When auto-minion mode is enabled, it intercepts the prompt and routes it through the auto-dispatch pipeline.

## Hook Logic

### 1. Check if Auto-Minion Mode is Enabled

```bash
if test -f "./.claude/minions/.auto-enabled"; then
  echo "ENABLED"
  cat "./.claude/minions/.auto-enabled"
elif test -f "$HOME/.claude/minions/.auto-enabled"; then
  echo "ENABLED"
  cat "$HOME/.claude/minions/.auto-enabled"
else
  echo "DISABLED"
fi
```

**If `DISABLED`**: do nothing. Let the message pass through to Claude normally.

**If `ENABLED`**: proceed to Step 2.

### 2. Check for Bypass

The following should NOT be intercepted by auto-minion — let them pass through to normal handling:

- Messages that start with `/minion` (the user is explicitly using the minion command)
- Messages that start with `/` (any other slash command)
- Empty messages

If the user's message matches any bypass condition, do nothing and let it pass through.

### 3. Dispatch

The user's message should be routed through the auto-minion dispatch pipeline.

Invoke the `auto-minion` skill with the dispatch context:

```
Skill(skill="auto-minion")
```

State: "Auto-minion dispatch. Prompt: `<user's message>`."

The skill handles everything from here: config resolution, dispatcher invocation, route execution, fallback, and result presentation.
