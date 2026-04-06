# minion

Delegate tasks to any AI model via Pi CLI without leaving Claude Code.

Minion is a Claude Code plugin that bridges Claude Code to [Pi CLI](https://shittycodingagent.ai), enabling multi-model delegation. Dispatch a task to OpenAI, Google, Anthropic, or any provider Pi supports, and get the result back in your conversation context. Define reusable minion files to capture repeatable delegation patterns.

## Installation

Install from the groundwork marketplace:

```
claude plugin install minion@groundwork-marketplace
```

## Prerequisites

Minion requires [Pi CLI](https://shittycodingagent.ai) to be installed on your machine. Pi is the multi-model agent runner that minion delegates to.

Install Pi from: **https://shittycodingagent.ai**

If Pi is not found in your PATH when you run `/minion`, the plugin will offer installation guidance.

## Usage

Minion supports three invocation modes: **inline mode** for one-off tasks, **minion file mode** for reusable delegation patterns, and **auto mode** for automatic prompt routing.

### Inline Mode

Pass all parameters directly on the command line:

```
/minion --provider <provider> --model <model> "<prompt>"
```

**Examples:**

```
/minion --provider openai --model gpt-4 "Review this function for performance issues"
```

```
/minion --provider anthropic --model claude-sonnet-4-20250514 "Explain the error in auth.py"
```

```
/minion --provider google --model gemini-pro "Summarize the changes in the last 5 commits"
```

Inline mode is useful for ad-hoc tasks where you do not need to save the configuration for reuse.

### Minion File Mode

Invoke a stored minion file by name:

```
/minion <name> [extra input]
```

**Examples:**

```
/minion security-reviewer "Review auth.py for vulnerabilities"
```

```
/minion code-explainer "Explain the retry logic in lib/fetch.ts"
```

#### File Resolution Order

When you invoke a minion by name, the plugin searches for the file in this order:

1. **Absolute path** -- if the name starts with `/`, it is treated as a file path
2. **Project-local** -- `./.claude/minions/<name>.md`
3. **User-global** -- `~/.claude/minions/<name>.md`

The first match wins. If no file is found at any path, the plugin reports the paths it searched and fails with an actionable error.

## Minion File Format

A minion file is a Markdown document with YAML frontmatter. The frontmatter defines Pi CLI parameters; the body provides the base prompt.

```markdown
---
provider: openai
model: gpt-4
no-session: true
---
You are a code reviewer specializing in security analysis.
Review the provided code for OWASP Top 10 vulnerabilities.
```

The frontmatter fields map directly to Pi CLI flags. The body (everything after the closing `---`) becomes the base prompt sent to the model. If extra input is provided when invoking the minion, it is appended to the base prompt separated by a blank line.

### Frontmatter Fields

| Field | Pi CLI Flag | Type | Required | Description |
|-------|-------------|------|----------|-------------|
| `provider` | `--provider <value>` | string | Yes | AI provider (e.g., `openai`, `anthropic`, `google`) |
| `model` | `--model <value>` | string | Yes | Model name (e.g., `gpt-4`, `claude-sonnet-4-20250514`) |
| `thinking` | `--thinking <value>` | string | No | Enable extended thinking with the given budget |
| `tools` | `--tools <value>` | string | No | Tool configuration |
| `no-tools` | `--no-tools` | boolean | No | Disable all tools |
| `no-session` | `--no-session` | boolean | No | Run without session persistence |
| `extensions` | `-e <value>` (per entry) | list | No | Extensions to load (one `-e` flag per entry) |
| `skills` | `--skill <value>` (per entry) | list | No | Skills to enable (one `--skill` flag per entry) |
| `max-turns` | `--max-turns <value>` | string | No | Maximum number of agent turns |
| `append-system-prompt` | `--append-system-prompt <value>` | string | No | Text appended to the system prompt |
| `stream` | `--stream` | boolean | No | Stream output in real time |

Boolean fields (`no-tools`, `no-session`, `stream`) emit the bare CLI flag when set to `true` and are omitted when `false` or absent.

List fields (`extensions`, `skills`) use standard YAML list syntax:

```yaml
extensions:
  - filesystem
  - web
skills:
  - code-review
```

## Auto-Minion Mode

Auto-minion mode routes every prompt to the best model automatically, without requiring `/minion` invocations. When enabled, a pre-message hook intercepts each prompt, classifies it by category, and dispatches to the configured model.

### Enable / Disable / Status

```
/minion auto on       — Enable auto-minion mode
/minion auto off      — Disable auto-minion mode
/minion auto status   — Show current configuration and routing summary
```

### Configuration

Auto-minion requires a configuration file at `.claude/minions/auto.md` (project-local) or `~/.claude/minions/auto.md` (user-global). Copy the example to get started:

```bash
mkdir -p .claude/minions
cp examples/auto.md .claude/minions/auto.md
```

Then edit it and run `/minion auto on`.

### Config Format

```yaml
---
dispatcher:
  provider: openai
  model: gpt-4o-mini
# or: dispatcher: inherit  (Claude classifies inline — no extra Pi call)

default:
  provider: openai
  model: gpt-4o
# or: default: inherit

categories:
  # Built-in categories (no description needed):
  code-review:
    provider: anthropic
    model: claude-sonnet-4-20250514
  explanation:
    provider: openai
    model: gpt-4o-mini
  # Custom categories (description required):
  translation:
    description: "Translating code between programming languages"
    provider: google
    model: gemini-2.5-pro
  # Route to a stored minion file:
  security:
    description: "Security auditing and vulnerability review"
    minion: security-reviewer
  # Route back to Claude natively:
  creative-writing: inherit

show-routing: true
---
You are a task classifier. Output ONLY the category name.

Available categories:
{{categories}}

If no category matches well, output: default

User prompt:
{{prompt}}
```

### Built-in Categories

The following category names are recognized without a `description` field:

| Category | Description |
|----------|-------------|
| `code-review` | Reviewing, auditing, or analyzing existing code for bugs, style, performance, or security |
| `code-generation` | Writing new code, functions, classes, modules, or features from scratch |
| `testing` | Writing, analyzing, or running tests, test fixtures, or test strategies |
| `documentation` | Writing or improving documentation, comments, READMEs, or API docs |
| `explanation` | Explaining code, concepts, errors, architecture, or design patterns |
| `refactoring` | Restructuring or reorganizing existing code without changing behavior |

### Routing Attribution

When `show-routing: true` is set, each response is prefixed with a routing line:

```
[auto-minion → code-review via anthropic/claude-sonnet-4-20250514]
```

### Fallback Behavior

- If the dispatcher model fails, auto-minion falls back to the default route automatically.
- If the default route also fails, the prompt is handled by Claude natively.
- Use `/minion auto off` to disable auto mode at any time.

## Examples

The plugin ships with ready-to-use example files in the `examples/` directory:

- **`security-reviewer.md`** -- Reviews code for security vulnerabilities using OWASP Top 10 categories. Reports findings by severity with remediation guidance.
- **`code-explainer.md`** -- Explains code in plain language with step-by-step breakdowns, key design decisions, dependencies, and edge cases.
- **`auto.md`** -- Example auto-minion configuration with built-in categories, a custom category, and an `inherit` dispatcher.

To use a minion file example, copy it to your minions directory:

**Project-local** (for a specific project):

```bash
mkdir -p .claude/minions
cp examples/security-reviewer.md .claude/minions/
```

**User-global** (available across all projects):

```bash
mkdir -p ~/.claude/minions
cp examples/code-explainer.md ~/.claude/minions/
```

Then invoke by name:

```
/minion security-reviewer "Review auth.py for vulnerabilities"
/minion code-explainer "Explain the retry logic in lib/fetch.ts"
```

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
