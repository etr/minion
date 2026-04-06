# TASK-011: lib/auto-dispatch.sh bash helper

**Milestone:** M5 — Auto-Minion Mode
**Estimate:** L
**Status:** Complete
**Depends on:** TASK-010

---

## Goal

Implement `lib/auto-dispatch.sh` — the mechanical bash layer for auto-minion dispatch. Parses the auto.md config, invokes the dispatcher model via Pi, resolves the route, and optionally executes the routed model.

## Deliverables

- `lib/auto-dispatch.sh` — bash helper with config parsing, dispatch, and route execution

## Interface

```
Usage:
  auto-dispatch.sh --config <path> --prompt <text> [--dry-run]

Exit codes:
  0   — Success (routed model executed or dry-run classification returned)
  1   — Validation error (bad config, missing fields)
  2   — Unknown flag / flag conflict
  3   — Dispatcher failed or fallback used (still succeeded)
  4   — All routes failed, needs ultimate fallback (inherit/Claude)
```

## Output Protocol

Header lines (one per line):
- `ROUTE:<category>` — matched category or "default"
- `PROVIDER:<value>` or `PROVIDER:inherit`
- `MODEL:<value>` or `MODEL:inherit`
- `MINION:<name>` — when routing via minion file
- `FALLBACK:<reason>` — none, dispatcher_failed, dispatcher_unrecognized, no_default
- `DISPATCHER:inherit` — when dispatcher is inherited
- `NEEDS_INLINE_CLASSIFICATION` — Claude should classify
- `NEEDS_NATIVE_HANDLING` — Claude should handle natively

Separator: `---`

Body: Pi output from routed model execution.

## Acceptance Criteria

- Config parsing handles dispatcher, default, categories blocks
- Built-in category names recognized with pre-defined descriptions
- Custom categories require description field
- `inherit` form supported for dispatcher, default, and per-category
- `minion:` field supported in categories
- All provider/model values validated against `[a-zA-Z0-9._-]+`
- All minion names validated against `[a-zA-Z0-9._-]+`
- Category descriptions sanitized: newlines stripped, max 200 chars
- compose_dispatcher_prompt uses printf (not echo) for safe output
- Dry-run stops before execution, outputs headers only
- Route execution failure tries default fallback, exits 3 or 4
