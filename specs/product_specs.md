# EARS-based Product Requirements

**Doc status:** Draft 0.1
**Last updated:** 2026-04-02
**Owner:** TBD
**Audience:** Eng

---

## 0) How we'll write requirements (EARS cheat sheet)
- **Ubiquitous form:** "When <trigger> then the system shall <response>."
- **Optional elements:** [when/while/until/as soon as] <trigger>, [the] system shall <response> [<object>].
- **Style:** Clear, atomic, testable, technology-agnostic.

---

## 1) Product context
- **Vision:** Enable Claude Code users to delegate tasks to any AI model via Pi CLI without leaving the Claude Code environment.
- **Target users / segments:** Claude Code power users who need multi-model workflows (e.g., specialized models for coding, reasoning, or domain-specific tasks).
- **Key JTBDs:**
  - Dispatch a task to a specific provider/model from within Claude Code and get the result back in context.
  - Reuse stored minion definitions for repeatable multi-model delegation patterns.
- **North-star metrics:** Successful delegations per session; time saved vs manual context-switching.
- **Release strategy:** Single release as a Claude Code skill/plugin.

---

## 2) Non-functional & cross-cutting requirements
- **Isolation:** Minion files are user-scoped (project-local or user-home). No shared state between invocations.
- **Identity:** Relies on Pi's own authentication; the skill does not manage credentials.
- **Security:** The skill passes user-provided prompts to Pi CLI. No secrets are stored by the skill itself.
- **Latency:** Dependent on Pi CLI and upstream model latency; the skill adds no significant overhead.
- **Scalability:** N/A — single-user CLI tool.
- **Auditability:** Pi CLI output is returned to Claude's conversation context, providing a natural audit trail.

---

## 3) Feature list (living backlog)

### 3.1 Delegate to Minion

**Problem / outcome**
Claude Code users want to leverage multiple AI models for specialized tasks without leaving the Claude Code environment. A delegation skill that bridges Claude Code to Pi's multi-model CLI lets users dispatch tasks to any provider/model while keeping results in Claude's conversation context.

**In scope**
- Inline invocation with provider, model, and prompt as required params
- Stored minion file invocation with frontmatter (Pi CLI params) + body (base prompt)
- Minion file resolution: absolute path -> `./.claude/minions/` -> `~/.claude/minions/`
- Prompt composition: minion base prompt + caller-provided input (same pattern as Claude Code agents)
- Full Pi CLI parameter mapping in frontmatter (provider, model, thinking, tools, no-tools, no-session, extensions, skills, max-turns, append-system-prompt, stream)
- Pi availability detection with install offer
- Output returned to Claude's conversation context

**Out of scope**
- Building or wrapping Pi itself -- Pi is an external dependency
- Concurrent multi-model fan-out (running same prompt on multiple models simultaneously)
- Minion file creation wizard / scaffolding
- Pi authentication or credential management

**EARS Requirements**

*Pi Availability*

- `PRD-MIN-REQ-001` When the skill is invoked, then the system shall check whether the `pi` CLI binary is available in the user's PATH.
- `PRD-MIN-REQ-002` If `pi` is not found in PATH, then the system shall offer to install Pi and provide installation instructions from shittycodingagent.ai.
- `PRD-MIN-REQ-003` If the user declines Pi installation, then the system shall abort with a clear message that Pi is required.

*Inline Invocation (Mode 1)*

- `PRD-MIN-REQ-004` When the skill is invoked with `provider`, `model`, and `prompt` arguments, then the system shall construct and execute a Pi CLI command using those parameters.
- `PRD-MIN-REQ-005` If any of the three required inline parameters (`provider`, `model`, `prompt`) is missing, then the system shall report which parameter is missing and show usage examples.

*Minion File Resolution (Mode 2)*

- `PRD-MIN-REQ-006` When the skill is invoked with a minion name or path, then the system shall resolve the minion file by checking in order: (1) the argument as an absolute path, (2) `./.claude/minions/<name>.md`, (3) `~/.claude/minions/<name>.md`.
- `PRD-MIN-REQ-007` If no minion file is found at any resolution path, then the system shall report the paths searched and fail with an actionable error.

*Minion File Format*

- `PRD-MIN-REQ-008` When a minion file is loaded, then the system shall parse YAML frontmatter for Pi CLI parameters: `provider`, `model`, `thinking`, `tools`, `no-tools`, `no-session`, `extensions` (list), `skills` (list), `max-turns`, `append-system-prompt`, and `stream`.
- `PRD-MIN-REQ-009` When a minion file is loaded, then the system shall treat the markdown body (after frontmatter) as the base prompt.
- `PRD-MIN-REQ-010` If a minion file lacks the required `provider` or `model` frontmatter fields, then the system shall report the missing fields and abort.

*Prompt Composition*

- `PRD-MIN-REQ-011` When the skill is invoked with a minion file and additional caller input, then the system shall compose the final prompt by combining the minion's base prompt with the caller-provided input, following the same composition pattern used by Claude Code agents.
- `PRD-MIN-REQ-012` When the skill is invoked with a minion file and no additional input, then the system shall use the minion's base prompt as-is.

*Pi CLI Execution*

- `PRD-MIN-REQ-013` When executing a Pi command, then the system shall map each frontmatter parameter to its corresponding Pi CLI flag (e.g., `provider` -> `--provider`, `extensions` list -> `-e` per entry, `no-tools` boolean -> `--no-tools`).
- `PRD-MIN-REQ-014` When Pi execution completes, then the system shall capture Pi's full output and return it into Claude's conversation context.
- `PRD-MIN-REQ-015` If Pi execution fails (non-zero exit code), then the system shall surface Pi's stderr output to the user with the exit code.

**Acceptance criteria**
- Inline invocation with provider, model, and prompt produces a Pi CLI call and returns output to Claude context
- A minion file at `./.claude/minions/example.md` with valid frontmatter is resolved and executed correctly
- A minion file at `~/.claude/minions/example.md` is found when project-local doesn't exist
- Missing `pi` binary triggers install offer
- Missing required parameters produce clear error messages
- Caller input composes with minion base prompt
- All supported frontmatter fields map to correct Pi CLI flags

---

## 4) Traceability
- `PRD-MIN-REQ-001` through `PRD-MIN-REQ-015` — Delegate to Minion feature (Eng)

---

## 5) Open questions log
<!-- No open questions at this time -->
