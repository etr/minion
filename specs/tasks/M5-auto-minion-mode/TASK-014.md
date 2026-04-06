# TASK-014: hooks/auto-minion.md pre-message hook

**Milestone:** M5 — Auto-Minion Mode
**Estimate:** S
**Status:** Complete
**Depends on:** TASK-012

---

## Goal

Implement `hooks/auto-minion.md` — a pre-message hook that intercepts user prompts when auto-minion mode is enabled and dispatches them to the auto-minion skill.

## Deliverables

- `hooks/auto-minion.md` — pre-message hook definition

## Hook Behavior

On every user message:
1. Check for `.auto-enabled` marker file (project-local or user-global)
2. If not found: pass through (do nothing)
3. If found: extract config path and dispatch to auto-minion skill with `auto-minion dispatch` context

## Acceptance Criteria

- Hook triggers only when `.auto-enabled` marker exists
- Hook passes the user's original prompt to the auto-minion skill
- Hook passes through silently when auto mode is disabled
- Hook checks both project-local and user-global marker paths in order
