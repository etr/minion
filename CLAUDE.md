# Minion Plugin - Development Notes

## Project Overview

Minion is a Claude Code plugin that bridges Claude Code to Pi CLI (shittycodingagent.ai), enabling multi-model delegation without leaving the Claude Code environment. Users can dispatch tasks to any AI model supported by Pi and get results back in their conversation context.

## Plugin Structure

```
minion/
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest
├── commands/
│   └── minion/
│       └── COMMAND.md           # /minion command (thin dispatcher)
├── skills/
│   └── delegate-to-minion/
│       └── SKILL.md             # Core execution logic
├── lib/
│   └── minion-run.sh            # Bash helper: frontmatter parsing + Pi invocation (TASK-003)
├── test/
│   └── validate-plugin-structure.sh  # Structure validation
├── CLAUDE.md                    # This file
└── specs/                       # Product specs, architecture, task definitions
```

## Component Formats

- **plugin.json**: Standard Claude Code plugin manifest (JSON)
- **COMMAND.md**: Markdown with YAML frontmatter. Frontmatter defines command metadata (name, description, argument-hint, allowed-tools). Body contains instructions for Claude.
- **SKILL.md**: Markdown with YAML frontmatter. Frontmatter defines skill metadata (name, description, user-invocable). Body contains the skill's execution instructions.
- **minion-run.sh**: Pure bash. Parses minion file YAML frontmatter, maps to Pi CLI flags, invokes Pi.

## Architecture Notes

### Two Invocation Modes
1. **Inline**: `/minion --provider openai --model gpt-4 "prompt"` - all params on command line
2. **Minion file**: `/minion security-reviewer [extra input]` - params from stored file

### Design Principles
- **Thin command + skill** (DR-004): The `/minion` command is a thin argument parser that dispatches to the `delegate-to-minion` skill. All execution logic lives in the skill.
- **Skill + bash helper** (DR-002): The skill handles UX (error messages, install flow, conversational interaction). The bash helper (`lib/minion-run.sh`) handles mechanical operations (frontmatter parsing, CLI flag mapping, Pi invocation) deterministically.
- **Bash for helpers** (DR-003): Zero dependency. Frontmatter is flat YAML, parseable with sed/awk.

### External Dependencies
- **Pi CLI**: Must be installed on user's machine. The plugin checks for `pi` in PATH and offers installation guidance if missing.

## Development Workflow

- Tests are in `test/`. Run `bash test/validate-plugin-structure.sh` to validate plugin structure.
- Task definitions are in `specs/tasks/`. Each task has its own directory under the milestone.
- This is a markdown + JSON + bash project. No package manager or build system.

## Task Roadmap

- TASK-001: Plugin directory structure and manifest (this task)
- TASK-002: Pi CLI detection and install flow
- TASK-003: lib/minion-run.sh bash helper
- TASK-004: Inline invocation mode
- TASK-005: Minion file resolution
- TASK-006: Frontmatter parsing
- TASK-007: Prompt composition and execution
