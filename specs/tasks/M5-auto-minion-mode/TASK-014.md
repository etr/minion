# TASK-014: Shell-based UserPromptSubmit hook for auto-minion mode

**Milestone:** M5 — Auto-Minion Mode
**Estimate:** S
**Status:** Complete
**Depends on:** TASK-012

---

## Goal

Implement a shell-based `UserPromptSubmit` hook that intercepts user prompts when auto-minion mode is enabled and dispatches them to the appropriate AI model via `lib/auto-dispatch.sh`. The hook runs entirely in bash (no Claude involvement except for inherit-dispatcher classification) and outputs JSON with `additionalContext` for Claude to present.

## Deliverables

- `hooks/hooks.json` — registers `lib/auto-minion-hook.sh` as a `UserPromptSubmit` shell hook
- `lib/auto-minion-hook.sh` — shell-based hook: reads JSON from stdin, checks enabled state, bypasses slash commands, classifies (inherit via `claude -p` or external dispatcher via Pi), executes routed model, outputs JSON with `additionalContext`
- `test/test-auto-minion-hook.sh` — tests for all hook paths: disabled, bypass, error handling, inherit dispatcher, external dispatcher, native route, fallback, show-routing

## Hook Behavior

On every user message:
1. Read JSON from stdin; extract `user_prompt` via jq
2. Check for `.auto-enabled` marker file (project-local or user-global)
3. If not found: exit 0 with no output (Claude handles normally)
4. Bypass slash commands (messages starting with `/`) and empty messages
5. If `dispatcher: inherit`: run `auto-dispatch.sh --dry-run` to get categories + base64-encoded dispatcher prompt, classify via `claude -p`, validate category, then run `auto-dispatch.sh --category`
6. Otherwise (external dispatcher): run `auto-dispatch.sh` end-to-end
7. Output JSON: `{ "hookSpecificOutput": { "hookEventName": "UserPromptSubmit", "additionalContext": "..." } }`

## Acceptance Criteria

- Hook triggers only when `.auto-enabled` marker exists
- Hook passes through silently when auto mode is disabled
- Hook bypasses slash commands
- Hook handles both inherit and external dispatcher configurations
- Hook outputs `auto-minion-result` tag when external model succeeds
- Hook outputs `auto-minion-routing` tag when route resolves to Claude (native)
- Hook outputs `auto-minion-error` tag on config validation errors
- Hook respects `show-routing` config flag
- Hook checks both project-local and user-global marker paths in order
- All paths covered by `test/test-auto-minion-hook.sh`
