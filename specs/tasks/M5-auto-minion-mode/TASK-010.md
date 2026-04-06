# TASK-010: Auto-minion config format and example auto.md

**Milestone:** M5 — Auto-Minion Mode
**Estimate:** S
**Status:** Complete
**Depends on:** TASK-009

---

## Goal

Define the auto-minion configuration file format and create the example `examples/auto.md` that users can copy to get started with auto-minion mode.

## Deliverables

- `examples/auto.md` — example auto-minion configuration with comments explaining each field
- Config format documented: YAML frontmatter with `dispatcher`, `default`, `categories`, and `show-routing` blocks

## Config Format

```yaml
---
dispatcher:
  provider: <provider>
  model: <model>
# or: dispatcher: inherit  (Claude classifies inline)

default:
  provider: <provider>
  model: <model>
# or: default: inherit

categories:
  <builtin-name>:
    provider: <provider>
    model: <model>
  <custom-name>:
    description: "..."
    provider: <provider>
    model: <model>
  <any-name>: inherit
  <any-name>:
    minion: <minion-file-name>

show-routing: true|false
---
<dispatcher prompt template with {{categories}} and {{prompt}} placeholders>
```

## Acceptance Criteria

- `examples/auto.md` exists and is valid YAML frontmatter + prompt body
- All built-in category names documented: code-review, code-generation, testing, documentation, explanation, refactoring
- Custom categories require a `description` field
- `dispatcher: inherit` and `default: inherit` are valid single-line forms
- The prompt template uses `{{categories}}` and `{{prompt}}` placeholders
