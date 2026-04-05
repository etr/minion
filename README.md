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

Minion supports two invocation modes: **inline mode** for one-off tasks, and **minion file mode** for reusable delegation patterns.

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

## Examples

The plugin ships with ready-to-use example minion files in the `examples/` directory:

- **`security-reviewer.md`** -- Reviews code for security vulnerabilities using OWASP Top 10 categories. Reports findings by severity with remediation guidance.
- **`code-explainer.md`** -- Explains code in plain language with step-by-step breakdowns, key design decisions, dependencies, and edge cases.

To use an example, copy it to your minions directory:

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
