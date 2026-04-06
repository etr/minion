---
# Auto-minion configuration
# Copy to .claude/minions/auto.md (project-local) or ~/.claude/minions/auto.md (user-global)

# Dispatcher: the model that classifies prompts into categories.
# Should be fast and cheap — it runs on every request.
# Set to "inherit" to use Claude Code's current model (no Pi call).
dispatcher:
  provider: openai
  model: gpt-4o-mini

# Default: used when no category matches the prompt.
default:
  provider: openai
  model: gpt-4o

# Categories: assign a provider/model to each task type.
# Built-in categories have pre-defined descriptions for the dispatcher.
# Omit a category to exclude it from routing (prompt falls to default).
# Set a category to "inherit" to let Claude Code handle it directly.
categories:
  code-review:
    provider: anthropic
    model: claude-sonnet-4-20250514
  code-generation:
    provider: anthropic
    model: claude-sonnet-4-20250514
  testing:
    provider: openai
    model: gpt-4o
  documentation:
    provider: openai
    model: gpt-4o-mini
  explanation:
    provider: openai
    model: gpt-4o-mini
  refactoring:
    provider: anthropic
    model: claude-sonnet-4-20250514

# Custom categories (require a description field):
#  translation:
#    description: "Translating code between programming languages"
#    provider: google
#    model: gemini-2.5-pro

# TRUST BOUNDARY: Category descriptions are included verbatim in the dispatcher
# prompt. Because the config file is user-authored and only the user who writes
# it can influence the dispatcher prompt, this is by design. Review your
# descriptions before committing or sharing this file.

# Show routing decision before output (true/false)
show-routing: true
---
You are a task classifier. Given a user prompt, output ONLY the category name that best matches.

Available categories:
{{categories}}

If no category matches well, output: default

User prompt:
{{prompt}}
