# System Architecture

**Version:** 0.1
**Last updated:** 2026-04-02
**Status:** Draft
**Owner:** TBD

---

## 1) Executive Summary

The delegate-to-minion plugin is a Claude Code plugin that bridges Claude Code to Pi CLI (shittycodingagent.ai), enabling multi-model delegation without leaving the Claude Code environment. The architecture is intentionally thin: a markdown command and skill handle UX and mode detection, while a bash helper script deterministically parses minion file frontmatter and constructs Pi CLI invocations. Pi's output is captured by the Bash tool and returned into Claude's conversation context.

The plugin is distributed via the groundwork marketplace at `etr/groundwork-marketplace`.

---

## 2) Architectural Drivers

### 2.1 Business Drivers
- Enable multi-model workflows from within Claude Code (PRD vision)
- Reusable minion definitions for repeatable delegation patterns (PRD JTBD)
- Zero context-switching — results come back into Claude's conversation

### 2.2 Quality Attributes (from PRD NFRs)
| Attribute | Requirement | Architecture Response |
|-----------|-------------|----------------------|
| Latency | No overhead beyond Pi + model latency | Thin bash script; no intermediary services |
| Isolation | User-scoped minion files, no shared state | File-based resolution per user/project |
| Security | No secrets stored by the skill | Delegates auth entirely to Pi CLI |
| Identity | Relies on Pi's auth; skill does not manage credentials | No credential storage or token handling in any plugin component; Pi CLI owns all provider authentication |
| Auditability | Pi output returned to Claude context as audit trail | Skill returns Pi stdout via Bash tool into Claude conversation; no separate log store needed |

### 2.3 Constraints
- Pi CLI must be installed on the user's machine
- Claude Code plugin system defines the extension points (skills, commands, hooks, lib)
- Bash must be available (universal on supported platforms)

---

## 3) System Overview

### 3.1 High-Level Architecture

```
User
  |
  +-- explicit invocation (/minion ...) ─────────────────────┐
  |                                                          |
  +-- auto mode (every prompt) ──────────────────────────────┤
       |                                                     |
       v                                                     v
hooks/hooks.json (UserPromptSubmit)             /minion command (COMMAND.md)
  |  shell hook runs auto-minion-hook.sh          |  parses arguments
  |  when .auto-enabled marker exists             |  (inline / minion-file / auto subcommand)
  v                                               v
lib/auto-minion-hook.sh               delegate-to-minion skill (SKILL.md)
  |  classify + dispatch in bash          |  UX, error handling, Pi install flow
  |  (claude -p for inherit dispatcher)   |
  v                                       v
lib/auto-dispatch.sh                  lib/minion-run.sh
  |  config parsing, dispatcher           |  frontmatter -> Pi CLI flags
  |  invocation, route resolution         |  prompt composition + Pi invocation
  v                                       v
Pi CLI (external)                     Pi CLI (external)
  |  dispatches to provider/model         |  dispatches to provider/model
  v                                       v
Output captured by Bash tool -> returned to Claude's context
```

### 3.2 Component Summary

| Component | Responsibility | Technology |
|-----------|---------------|------------|
| `/minion` command | User-facing entry point, argument parsing | Markdown (COMMAND.md) |
| `delegate-to-minion` skill | Execution logic, UX, error handling, Pi install flow, return Pi output to Claude's context | Markdown (SKILL.md) |
| `auto-minion` skill | Auto mode enable/disable/status UX, dispatch to auto-dispatch.sh, fallback to Claude | Markdown (SKILL.md) |
| `hooks/hooks.json` | Shell-based UserPromptSubmit hook registration | JSON |
| `auto-minion-hook.sh` | Shell-based hook: enabled check, bypass, dispatch (external + inherit via `claude -p`), JSON I/O | Bash |
| `minion-run.sh` | Minion file parsing, frontmatter-to-CLI mapping, Pi invocation | Bash |
| `auto-dispatch.sh` | Auto.md config parsing, dispatcher invocation, route resolution, routed model execution | Bash |
| Minion files | Reusable delegation definitions (frontmatter + prompt) | Markdown with YAML frontmatter |
| Auto config (auto.md) | Category routing rules, dispatcher config, prompt template | Markdown with YAML frontmatter |
| Pi CLI | External multi-model agent runner | External dependency |

---

## 4) Component Details

### 4.1 `/minion` Command

**Responsibility:** Parse user arguments and dispatch to the skill.

**Technology:** Claude Code command (COMMAND.md with frontmatter)

**Interfaces:**
- User invokes: `/minion [args]`
- Dispatches to: `delegate-to-minion` skill logic

**Key Design Notes:**
- Two invocation patterns detected from arguments:
  - Inline: `--provider X --model Y "prompt"` (all three required)
  - Minion file: `<name-or-path> [extra input]`
- Argument validation happens here before skill logic runs

**Related Requirements:** PRD-MIN-REQ-004, PRD-MIN-REQ-005, PRD-MIN-REQ-006

### 4.2 `delegate-to-minion` Skill

**Responsibility:** Core execution logic — mode detection, minion file resolution, prompt composition, error handling, and Pi availability checks.

**Technology:** Claude Code skill (SKILL.md)

**Interfaces:**
- Receives: parsed arguments from command or conversational invocation
- Calls: `lib/minion-run.sh` via Bash tool
- Returns: Pi output to Claude's conversation context

**Key Design Notes:**
- Checks for `pi` in PATH before any execution (PRD-MIN-REQ-001)
- If Pi missing: offers installation with instructions from shittycodingagent.ai (PRD-MIN-REQ-002)
- If user declines Pi installation: aborts with a clear message that Pi is required (PRD-MIN-REQ-003)
- Minion file resolution order: absolute path -> `./.claude/minions/<name>.md` -> `~/.claude/minions/<name>.md` (PRD-MIN-REQ-006)
- If no minion file found at any resolution path: reports the paths searched and fails with an actionable error (PRD-MIN-REQ-007)
- Prompt composition follows Claude Code agent pattern: base prompt (from minion body) + caller input appended (PRD-MIN-REQ-011)
- If minion file invoked with no additional input: uses the minion's base prompt as-is (PRD-MIN-REQ-012)
- Captures Pi's full stdout and returns it into Claude's conversation context (PRD-MIN-REQ-014)
- On Pi failure: surfaces stderr and exit code (PRD-MIN-REQ-015)

**Error handling pattern:** All error paths follow a common abort pattern — check condition, compose a user-facing message with actionable guidance (e.g., install instructions, paths searched, missing field names), and halt execution. This covers PRD-MIN-REQ-003, PRD-MIN-REQ-005, PRD-MIN-REQ-007, PRD-MIN-REQ-010, and PRD-MIN-REQ-015.

**Related Requirements:** PRD-MIN-REQ-001 through PRD-MIN-REQ-015

### 4.3 `lib/minion-run.sh`

**Responsibility:** Deterministic frontmatter parsing and Pi CLI construction. This is the mechanical layer — no UX, no prompting, no error messaging beyond exit codes.

**Technology:** Bash

**Interfaces:**
- Input: minion file path (or inline params) + optional extra prompt text
- Output: Pi's stdout (on success) or stderr + exit code (on failure)

**Key Design Notes:**
- Parses YAML frontmatter between `---` delimiters using `sed`/`awk`
- Maps frontmatter fields to Pi CLI flags:

| Frontmatter Field | Pi CLI Flag | Type |
|-------------------|-------------|------|
| `provider` | `--provider <value>` | string (required) |
| `model` | `--model <value>` | string (required) |
| `thinking` | `--thinking <value>` | string |
| `tools` | `--tools <value>` | string |
| `no-tools` | `--no-tools` | boolean flag |
| `no-session` | `--no-session` | boolean flag |
| `extensions` | `-e <value>` (per entry) | list |
| `skills` | `--skill <value>` (per entry) | list |
| `max-turns` | `--max-turns <value>` | string |
| `append-system-prompt` | `--append-system-prompt <value>` | string |
| `stream` | `--stream` | boolean flag |

- List fields (extensions, skills) are parsed line-by-line from YAML `- item` syntax
- Boolean fields are emitted as bare flags when truthy, omitted when falsy
- Validates required fields (provider, model); reports missing field names to stdout before exiting non-zero (PRD-MIN-REQ-010)
- Composes prompt: concatenates base prompt (markdown body) + blank line separator (`\n\n`) + extra input

**Related Requirements:** PRD-MIN-REQ-008, PRD-MIN-REQ-009, PRD-MIN-REQ-010, PRD-MIN-REQ-013

### 4.4 Minion Files

**Responsibility:** Store reusable delegation definitions.

**Technology:** Markdown with YAML frontmatter (same pattern as Claude Code agent files)

**Format:**
```markdown
---
provider: openai
model: gpt-4
no-session: true
extensions:
  - filesystem
  - web
---

You are a code reviewer specializing in security analysis.
Review the following code for OWASP Top 10 vulnerabilities.
```

**Resolution paths (in order):**
1. Absolute path (if argument starts with `/`)
2. `./.claude/minions/<name>.md` (project-local)
3. `~/.claude/minions/<name>.md` (user-global)

**Related Requirements:** PRD-MIN-REQ-006, PRD-MIN-REQ-007, PRD-MIN-REQ-008, PRD-MIN-REQ-009

### 4.5 `auto-minion` Skill

**Responsibility:** UX layer for auto-minion mode — enable/disable/status subcommands and prompt dispatch with fallback to Claude.

**Technology:** Claude Code skill (SKILL.md)

**Interfaces:**
- Receives: subcommand context from `/minion auto` command or auto-minion hook
- Calls: `lib/auto-dispatch.sh` via Bash tool
- Writes/reads: `.auto-enabled` marker file in minions directory

**Key Design Notes:**
- Enable flow: check Pi, resolve config, validate via dry-run, write marker with `printf`, show summary
- Config path validated as absolute path with no newline characters before writing marker
- Example config reference uses plugin-relative path resolution (not hardcoded relative path)
- Dispatch uses temp-file pattern for user prompt: `printf '%s' prompt > tmpfile; cat tmpfile`
- Fallback: exit 3 = degraded success (use default route), exit 4 = all routes failed (Claude handles natively)

**Related Requirements:** PRD-AUTO-REQ-001 through PRD-AUTO-REQ-016

### 4.6 `lib/auto-dispatch.sh`

**Responsibility:** Mechanical layer for auto-minion dispatch — config parsing, dispatcher invocation, route resolution, and execution.

**Technology:** Bash

**Interfaces:**
- Input: `--config <path>`, `--prompt <text>`, optional `--dry-run`, optional `--category <name>`
- Output: structured header lines + `---` separator + routed model output
- Exit codes: 0 (success), 1 (validation error), 2 (unknown flag), 3 (fallback used), 4 (all routes failed)
- `--category <name>`: when provided, skips the dispatcher entirely and routes directly to the named category (or `default`). Used by the hook when Claude itself is the dispatcher (`inherit` mode).

**Key Design Notes:**
- Config parsing handles `dispatcher`, `default`, `categories` blocks with nested YAML
- All provider/model values validated against `^[a-zA-Z0-9._-]+$` at parse time (PRD-AUTO-REQ-012)
- All minion names validated against `^[a-zA-Z0-9._-]+$` to prevent path traversal (PRD-AUTO-REQ-013)
- Category descriptions sanitized: newlines stripped, truncated to 200 chars (PRD-AUTO-REQ-014)
- `compose_dispatcher_prompt` uses `printf '%s\n'` (not echo) for safe output (PRD-AUTO-REQ-015)
- `inherit` form supported for dispatcher, default, and per-category
- Route execution failure tries default fallback; exits 3 (degraded) or 4 (all failed)

**Related Requirements:** PRD-AUTO-REQ-005 through PRD-AUTO-REQ-015

### 4.7 `hooks/hooks.json`

**Responsibility:** Register a shell-based `UserPromptSubmit` hook that runs `lib/auto-minion-hook.sh` on every user message.

**Technology:** Claude Code hooks.json (JSON)

**Interfaces:**
- Trigger: `UserPromptSubmit` event (every user message)
- Runs: `bash ${CLAUDE_PLUGIN_ROOT}/lib/auto-minion-hook.sh` with 300s timeout

**Key Design Notes:**
- Replaces the prompt-based `hooks/auto-minion.md` — all dispatch logic now runs in bash, saving tokens
- Claude is only involved when the hook outputs `additionalContext` (to present results or handle native routes)
- When disabled or bypassed, the script exits 0 with no output — zero token cost

**Related Requirements:** PRD-AUTO-REQ-005

### 4.7.5 `lib/auto-minion-hook.sh`

**Responsibility:** Shell-based hook logic — enabled check, bypass detection, config parsing, classification (external or inherit via `claude -p`), route execution, and JSON output formatting.

**Technology:** Bash (requires `jq` for JSON I/O)

**Interfaces:**
- Input: JSON on stdin (`{"hook_event_name": "UserPromptSubmit", "user_prompt": "...", ...}`)
- Output: JSON on stdout (`{"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": "..."}}`)
- When disabled/bypassed: exit 0 with no output

**Key Design Notes:**
- Config path read from `.auto-enabled` marker (project-local first, then `$HOME`-scoped)
- Config path validated as an absolute path before use (outputs error context JSON on failure)
- Frontmatter parsed once into `$FRONTMATTER` variable; `show-routing` and `dispatcher` extracted via `sed`
- For `dispatcher: inherit`: calls `auto-dispatch.sh --dry-run` to get categories/prompt, then `claude -p` to classify, then `auto-dispatch.sh --category` to execute
- For external dispatcher: calls `auto-dispatch.sh` for full dispatch, parses headers in a `while read` loop
- additionalContext uses XML-style tags: `<auto-minion-result>` (external model output), `<auto-minion-routing>` (native handling), `<auto-minion-error>` (errors)
- All error paths output context telling Claude to handle natively or show the error

**Related Requirements:** PRD-AUTO-REQ-005, PRD-AUTO-REQ-012

### 4.8 Auto Config (`auto.md`)

**Responsibility:** Store category routing rules and dispatcher configuration for auto-minion mode.

**Technology:** Markdown with YAML frontmatter

**Format:** YAML frontmatter with `dispatcher`, `default`, `categories`, `show-routing` blocks; body is the dispatcher prompt template with `{{categories}}` and `{{prompt}}` placeholders.

**Resolution paths (in order):**
1. `./.claude/minions/auto.md` (project-local)
2. `~/.claude/minions/auto.md` (user-global)

**Related Requirements:** PRD-AUTO-REQ-001, PRD-AUTO-REQ-002

---

## 5) Plugin Structure

```
minion/
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest (name, version, description)
├── commands/
│   └── minion/
│       └── COMMAND.md           # /minion command: inline, minion-file, auto subcommand
├── skills/
│   ├── delegate-to-minion/
│   │   └── SKILL.md             # Core delegation logic and UX
│   └── auto-minion/
│       └── SKILL.md             # Auto-minion: on/off/status + dispatch UX
├── hooks/
│   └── hooks.json               # Shell-based UserPromptSubmit hook registration
├── lib/
│   ├── minion-run.sh            # Bash helper: frontmatter parsing + Pi invocation
│   ├── auto-dispatch.sh         # Bash helper: config parsing + dispatcher + routing
│   └── auto-minion-hook.sh      # Bash helper: shell-side hook logic (enabled check, bypass, dispatch)
├── examples/
│   ├── security-reviewer.md     # Example minion file
│   ├── code-explainer.md        # Example minion file
│   └── auto.md                  # Example auto-minion configuration
├── test/
│   ├── validate-plugin-structure.sh
│   ├── test-readme-and-license.sh
│   ├── test-auto-dispatch.sh    # Tests for auto-dispatch.sh
│   └── test-auto-minion-hook.sh # Tests for auto-minion-hook.sh
├── CLAUDE.md                    # Plugin development notes
├── LICENSE
└── README.md
```

---

## 6) Integration Architecture

### 6.1 External Integrations

| System | Protocol | Purpose | Failure Handling |
|--------|----------|---------|------------------|
| Pi CLI | Shell subprocess | Multi-model execution | Check PATH; offer install if missing. Surface stderr + exit code on failure. |

### 6.2 Internal Communication

All communication is synchronous and in-process:
1. Command parses args -> passes to skill logic
2. Skill calls `lib/minion-run.sh` via Bash tool
3. Bash tool captures Pi's stdout/stderr
4. Skill returns output to Claude's conversation context

No async messaging, no queues, no inter-process communication beyond the Pi subprocess.

---

## 7) Security Considerations

- **No credential storage:** The plugin never stores API keys or tokens. Pi CLI manages its own authentication with providers.
- **Prompt pass-through:** User prompts are passed directly to Pi. The plugin does not log, cache, or persist prompts.
- **No network access:** The plugin itself makes no network calls. Only Pi CLI accesses external APIs.
- **File access:** The skill reads minion files from well-defined paths. No arbitrary file access beyond the resolution paths.

---

## 8) Decision Records

### DR-001: Delivery Vehicle

**Status:** Accepted
**Date:** 2026-04-02
**Context:** Need to decide how to package and distribute the delegate-to-minion capability for Claude Code users.

**Options Considered:**
1. **Full Claude Code Plugin** — Structured plugin with `plugin.json`, skills, commands, lib.
   - Pros: Installable via plugin system, extensible, can bundle examples and hooks
   - Cons: More boilerplate than a single file
2. **Standalone Skill File** — Single `.md` dropped in `~/.claude/skills/`.
   - Pros: Minimal setup
   - Cons: No structured distribution, can't bundle helpers or examples

**Decision:** Full Claude Code Plugin

**Rationale:** Distribution via the groundwork marketplace requires plugin format. Plugin structure is required to bundle `lib/minion-run.sh` (needed for PRD-MIN-REQ-008, PRD-MIN-REQ-013) and example minion files alongside the skill and command. Extensibility for future hooks (e.g., auto-detect delegation intent) is a bonus.

**Consequences:**
- Plugin must follow Claude Code plugin conventions
- Installable via `claude plugin install minion@groundwork-marketplace`

### DR-002: Skill Implementation Approach

**Status:** Accepted
**Date:** 2026-04-02
**Context:** The skill must parse minion files, map frontmatter to Pi CLI flags, and invoke Pi. This is partly mechanical (flag mapping) and partly intelligent (error UX, install flow).

**Options Considered:**
1. **Pure Markdown Skill** — All logic in the skill prompt; Claude reasons about each flag.
   - Pros: Simple, no script dependency
   - Cons: Non-deterministic flag mapping, harder to test
2. **Markdown Skill + Helper Script** — Skill handles UX; script handles parsing and invocation.
   - Pros: Deterministic parsing, testable, reduces token usage
   - Cons: Two codebases to maintain

**Decision:** Markdown Skill + Helper Script

**Rationale:** The frontmatter-to-CLI mapping (PRD-MIN-REQ-013) is mechanical — it should be deterministic, not subject to LLM interpretation. The skill focuses on what Claude is good at: UX, error messaging, conversational install flow.

**Consequences:**
- `lib/minion-run.sh` must be independently testable
- Skill and script have a clear contract: script accepts args, returns stdout/stderr + exit code

### DR-003: Helper Script Language

**Status:** Accepted
**Date:** 2026-04-02
**Context:** The helper script needs to parse YAML frontmatter, map params to CLI flags, and invoke Pi.

**Options Considered:**
1. **Bash** — Zero dependencies, natural CLI integration.
   - Pros: Universal, lightweight, native subprocess invocation
   - Cons: YAML parsing requires careful sed/awk work
2. **Python** — Robust YAML parsing via pyyaml.
   - Pros: Clean parsing, easy testing
   - Cons: Requires Python 3 + pyyaml dependency
3. **Node.js** — Good YAML libraries.
   - Pros: Likely available for Claude Code users
   - Cons: npm dependency management

**Decision:** Bash

**Rationale:** Frontmatter parsing (PRD-MIN-REQ-008) and flag mapping (PRD-MIN-REQ-013) are mechanical operations. The minion file frontmatter is flat (no nesting beyond simple lists), so bash can parse this reliably with `sed`/`awk`. Zero dependencies aligns with the plugin's lightweight nature and the bash-availability constraint. Pi is itself a CLI tool, so bash is the natural integration layer.

**Consequences:**
- Must handle YAML list syntax (`- item`) carefully in bash
- Boolean flags need truthy/falsy detection
- Testing requires bash test framework or integration tests via Pi

### DR-004: Include /minion Command

**Status:** Accepted
**Date:** 2026-04-02
**Context:** Users need a clear entry point for delegation. Skills can be invoked conversationally, but explicit invocation is important for a tool with specific argument patterns.

**Options Considered:**
1. **Skill only** — Users invoke via conversation or `/delegate-to-minion`.
   - Pros: Simpler plugin structure
   - Cons: No argument auto-completion, verbose invocation name
2. **Command + Skill** — `/minion` command for explicit invocation, skill for execution logic.
   - Pros: Short command name, argument parsing, auto-completion
   - Cons: Slightly more code

**Decision:** Command + Skill

**Rationale:** The two invocation modes defined in PRD-MIN-REQ-004 (inline) and PRD-MIN-REQ-006 (minion file) have distinct argument patterns that benefit from explicit command argument parsing. The Pi availability check (PRD-MIN-REQ-001) needs a clear entry point. `/minion` is concise and memorable. The skill remains the execution engine, keeping the command thin.

**Consequences:**
- Command is a thin dispatcher; skill contains all logic
- Both conversational and explicit invocation paths work

### DR-005: Dispatcher Model Architecture

**Status:** Accepted
**Date:** 2026-04-05
**Context:** Auto-minion needs a way to classify user prompts into routing categories. Two main architectures were considered.

**Options Considered:**
1. **External Dispatcher Model** — Use a configurable Pi-invoked model to classify prompts. Output is parsed to determine the route.
   - Pros: Flexible, any model can classify; classifier can be swapped without code changes
   - Cons: Extra Pi call adds latency; classifier can fail or return unexpected output
2. **Claude Inline Classification** — Claude (the host model) classifies prompts using the category list embedded in the skill.
   - Pros: No extra Pi call, zero latency overhead
   - Cons: Uses Claude Code tokens; not separable from the host LLM

**Decision:** Both, with `inherit` as escape hatch

**Rationale:** Externalizing the dispatcher gives users full control over the classifier model and cost. `dispatcher: inherit` lets users choose Claude inline classification when they prefer zero extra Pi calls. The two-layer architecture (external dispatcher + inherit fallback) keeps the system flexible without forcing users into a single model.

**Consequences:**
- `auto-dispatch.sh` must handle the `inherit` case by signaling `NEEDS_INLINE_CLASSIFICATION`
- The skill must handle inline classification when `inherit` is set
- Dispatcher failure must gracefully fall back to the default route (exit 3)

### DR-006: Input Validation Strategy for Auto-Dispatch

**Status:** Accepted
**Date:** 2026-04-05
**Context:** `auto-dispatch.sh` builds file paths and shell arguments from user-controlled YAML config values. Injection risks exist at: provider/model values (passed to Pi as CLI args), minion names (used in file path construction), and category descriptions (embedded in the dispatcher prompt).

**Decision:** Allowlist validation for identifiers; sanitization for free-text fields

**Rationale:**
- Provider, model, and minion name values have a well-defined safe character set (`[a-zA-Z0-9._-]+`). Allowlist validation is cheap, deterministic, and fails closed.
- Category descriptions are free-text (prompt injection risk against the dispatcher). Stripping newlines and limiting to 200 chars limits the blast radius without rejecting valid descriptions.
- Shell quoting in bash (double-quoted `"$VAR"`) prevents word splitting; the allowlist adds a second defense-in-depth layer.

**Consequences:**
- Provider/model values with spaces, semicolons, etc. are rejected at parse time with a clear error message
- Minion names with path separators (`/`, `..`) are rejected
- Description truncation may shorten very long descriptions; users should keep descriptions concise

---

## 9) Open Questions & Risks

| ID | Question/Risk | Impact | Mitigation | Owner |
|----|---------------|--------|------------|-------|
| AR-001 | Pi CLI installation method may vary across platforms | M | Skill detects OS and provides platform-specific install instructions | Eng |
| AR-002 | Pi CLI flag interface may change across versions | M | Pin to known Pi version in docs; minion-run.sh is easy to update | Eng |
| AR-003 | Large Pi outputs may hit Bash tool output limits | L | Document output size expectations; consider truncation for very large responses | Eng |

---

## 10) Appendices

### A. Glossary
- **Minion:** A stored delegation definition (frontmatter + prompt) that can be invoked by name
- **Pi:** Multi-model AI agent CLI tool (shittycodingagent.ai)
- **Provider:** An AI service backend (e.g., openai, anthropic, google)
- **Delegation:** Dispatching a task from Claude Code to another model via Pi

### B. References
- PRD: `specs/product_specs.md`
- Pi CLI: https://shittycodingagent.ai/
- Claude Code Plugin Docs: https://docs.anthropic.com/
- Groundwork Marketplace: `etr/groundwork-marketplace`
