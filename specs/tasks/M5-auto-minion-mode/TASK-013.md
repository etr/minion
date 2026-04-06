# TASK-013: COMMAND.md update for auto subcommand

**Milestone:** M5 — Auto-Minion Mode
**Estimate:** S
**Status:** Complete
**Depends on:** TASK-012

---

## Goal

Update `commands/minion/COMMAND.md` to document and dispatch the `auto` subcommand.

## Deliverables

- Updated `commands/minion/COMMAND.md` with auto subcommand detection and dispatch

## Subcommand

```
/minion auto on       — Enable auto-minion mode
/minion auto off      — Disable auto-minion mode
/minion auto status   — Show current configuration
```

## Dispatch Logic

When the first argument is `auto`, dispatch to the `auto-minion` skill with the subcommand context:
```
auto-minion subcommand: <on|off|status>
```

## Acceptance Criteria

- `auto on`, `auto off`, `auto status` detected and dispatched to auto-minion skill
- Other arguments continue to dispatch to delegate-to-minion skill as before
- Help text updated to show three invocation modes
