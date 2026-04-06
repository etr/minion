# TASK-012: skills/auto-minion/SKILL.md

**Milestone:** M5 — Auto-Minion Mode
**Estimate:** M
**Status:** Complete
**Depends on:** TASK-011

---

## Goal

Implement `skills/auto-minion/SKILL.md` — the UX layer for auto-minion mode. Handles enable/disable/status subcommands and prompt dispatch with fallback to Claude.

## Deliverables

- `skills/auto-minion/SKILL.md` — skill definition

## Actions

- **on**: Check Pi, resolve config, validate via dry-run, write `.auto-enabled` marker, show summary
- **off**: Remove `.auto-enabled` marker files
- **status**: Read marker file, show config and routing summary
- **dispatch**: Invoke `auto-dispatch.sh`, parse output, present results with routing attribution

## Marker File

Location: same directory as the resolved config (`./.claude/minions/.auto-enabled` or `~/.claude/minions/.auto-enabled`).

Format:
```
config=/absolute/path/to/auto.md
```

Written with `printf 'config=%s\n'` (not echo) for safety.

## Dispatch Flow

1. Read config path from marker file
2. Write prompt to temp file with `printf '%s'`, pass via `$(cat ...)`
3. Call `auto-dispatch.sh --config "$AUTO_CONFIG" --prompt "$(cat "$PROMPT_FILE")"`
4. Parse output: route headers + Pi result body
5. Present with routing attribution if `show-routing` is enabled
6. On exit 4: fall back to Claude natively

## Acceptance Criteria

- Enable flow validates config before writing marker
- Config path validated as absolute, newline-free before writing to marker
- Example config reference uses plugin-relative path resolution
- Dispatch uses temp-file pattern for prompt, not shell-embedded user input
- All fallback cases handled (exit 3: degraded success, exit 4: native fallback)
