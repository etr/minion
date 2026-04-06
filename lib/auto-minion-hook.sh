#!/usr/bin/env bash
# auto-minion-hook.sh — Shell-based UserPromptSubmit hook for auto-minion mode.
# Receives JSON on stdin from Claude Code hook system, does all mechanical work
# in bash, and outputs JSON with hookSpecificOutput/additionalContext.
#
# Claude is only involved when:
#   1. Claude IS the dispatcher (inherit) — classified via `claude -p`
#   2. Claude IS the execution model (route resolves to inherit) — prompt passes through
#   3. An external model handled the prompt — Claude presents additionalContext verbatim
#
# Input (stdin JSON):
#   { "hook_event_name": "UserPromptSubmit", "user_prompt": "...", ... }
#
# Output (stdout JSON):
#   { "hookSpecificOutput": { "hookEventName": "UserPromptSubmit", "additionalContext": "..." } }
#
# When disabled or bypassed: exit 0 with no output. Claude handles normally.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# AUTO_DISPATCH_DIR: if set, use this directory to locate auto-dispatch.sh instead of SCRIPT_DIR.
# This allows tests to provide a mock auto-dispatch.sh without modifying the real lib/ file.
_AUTO_DISPATCH_DIR="${AUTO_DISPATCH_DIR:-$SCRIPT_DIR}"

# --- Read JSON input from stdin ---
INPUT_JSON="$(cat)"

# Extract user_prompt via jq
if ! command -v jq >/dev/null 2>&1; then
  # jq not available — can't parse hook input, let Claude handle normally
  exit 0
fi

USER_MESSAGE="$(printf '%s' "$INPUT_JSON" | jq -r '.user_prompt // empty')"

# --- Helper: output JSON with additionalContext ---
output_context() {
  local context="$1"
  printf '%s' "$context" | jq -Rs '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: .}}'
}

# --- Helper: escape angle brackets for safe embedding in XML-like context blocks ---
escape_xml() {
  printf '%s' "$1" | sed 's/</\&lt;/g; s/>/\&gt;/g'
}

# --- Helper: handle the result of an auto-dispatch.sh invocation ---
# Parses headers (before ---), checks NEEDS_NATIVE_HANDLING, handles error exits,
# extracts body, formats attribution, and calls output_context.
# Arguments:
#   $1 — dispatch output (stdout from auto-dispatch.sh)
#   $2 — dispatch exit code
#   $3 — dispatch stderr (already XML-escaped)
#   $4 — category label fallback (used in attribution when ROUTE_CAT is empty)
#   $5 — dispatcher_unavailable_on_exit3: "true" to use "dispatcher unavailable" attribution for exit 3
handle_dispatch_result() {
  local output="$1"
  local exit_code="$2"
  local stderr_escaped="$3"
  local cat_fallback="$4"
  local unavail_on_exit3="${5:-false}"

  # Extract headers (before ---) — safe from body injection
  local headers
  headers="$(printf '%s' "$output" | sed -n '/^---$/q;p')"

  local route_cat route_provider route_model
  route_cat="$(printf '%s' "$headers" | sed -n 's/^ROUTE://p')"
  route_provider="$(printf '%s' "$headers" | sed -n 's/^PROVIDER://p')"
  route_model="$(printf '%s' "$headers" | sed -n 's/^MODEL://p')"
  # Validate header values against safe character set
  echo "$route_cat"      | grep -qE '^[a-zA-Z0-9._-]*$' || route_cat=""
  echo "$route_provider" | grep -qE '^[a-zA-Z0-9._-]*$' || route_provider=""
  echo "$route_model"    | grep -qE '^[a-zA-Z0-9._-]*$' || route_model=""

  # Extract body after --- first (before any body-dependent checks)
  local body
  body="$(echo "$output" | sed -n '/^---$/,$ { /^---$/d; p; }')"

  # Check NEEDS_NATIVE_HANDLING — marker must appear in body only (not headers)
  if echo "$body" | grep -qF "NEEDS_NATIVE_HANDLING"; then
    if [ "$SHOW_ROUTING" = "true" ]; then
      output_context "<auto-minion-routing>
Route: ${route_cat:-$cat_fallback} → Claude (native)
Handle the user's prompt directly.
</auto-minion-routing>"
    else
      output_context "<auto-minion-routing>
Handle the user's prompt directly.
</auto-minion-routing>"
    fi
    exit 0
  fi

  # Check for all-routes-failed
  if [ "$exit_code" -eq 4 ]; then
    output_context "<auto-minion-routing>
Route: fallback (all routes failed) → Claude (native)
Handle the user's prompt directly.
</auto-minion-routing>"
    exit 0
  fi

  # Check for config validation error
  if [ "$exit_code" -eq 1 ]; then
    output_context "<auto-minion-error>
${stderr_escaped:-auto-dispatch.sh config error}
Check your auto-minion config or disable auto mode with /minion auto off.
</auto-minion-error>"
    exit 0
  fi

  # External model produced output — escape body before embedding in XML-like context block
  local body_escaped
  body_escaped="$(escape_xml "$body")"

  local attribution=""
  if [ "$SHOW_ROUTING" = "true" ]; then
    if [ "$unavail_on_exit3" = "true" ] && [ "$exit_code" -eq 3 ]; then
      attribution="Route: default (dispatcher unavailable) via ${route_provider}/${route_model}
"
    else
      attribution="Route: ${route_cat:-$cat_fallback} via ${route_provider}/${route_model}
"
    fi
  fi

  output_context "<auto-minion-result>
${attribution}Present the following output verbatim. Do not add your own response.
---
${body_escaped}
</auto-minion-result>"
  exit 0
}

# --- Check if auto-minion mode is enabled ---
CONFIG_PATH=""
if test -f "./.claude/minions/.auto-enabled"; then
  CONFIG_PATH="$(sed -n 's/^config=//p' "./.claude/minions/.auto-enabled")"
elif test -f "$HOME/.claude/minions/.auto-enabled"; then
  CONFIG_PATH="$(sed -n 's/^config=//p' "$HOME/.claude/minions/.auto-enabled")"
fi

if [ -z "$CONFIG_PATH" ]; then
  # Disabled — no output, exit 0
  exit 0
fi

# Validate CONFIG_PATH is an absolute path (must start with /)
config_path_escaped="$(escape_xml "$CONFIG_PATH")"
if [[ "$CONFIG_PATH" != /* ]]; then
  output_context "<auto-minion-error>
Config path must be absolute: $config_path_escaped
Check your auto-minion config or disable auto mode with /minion auto off.
</auto-minion-error>"
  exit 0
fi

if [ ! -f "$CONFIG_PATH" ]; then
  output_context "<auto-minion-error>
Config file not found: $config_path_escaped
Check your auto-minion config or disable auto mode with /minion auto off.
</auto-minion-error>"
  exit 0
fi

# --- Bypass checks ---
if [ -z "$USER_MESSAGE" ]; then
  # Empty message — no output, exit 0
  exit 0
fi

case "$USER_MESSAGE" in
  /*)
    # Slash command — no output, exit 0
    exit 0
    ;;
esac

# --- Parse config frontmatter once ---
FRONTMATTER="$(awk 'BEGIN{c=0} /^---[[:space:]]*$/{c++;next} c==1{print} c>=2{exit}' "$CONFIG_PATH")"

SHOW_ROUTING="$(echo "$FRONTMATTER" | sed -n 's/^show-routing: *//p')"
SHOW_ROUTING="${SHOW_ROUTING:-true}"

# --- Check dispatcher type ---
DISPATCHER_VAL="$(echo "$FRONTMATTER" | sed -n 's/^dispatcher: *//p')"

if [ "$DISPATCHER_VAL" = "inherit" ]; then
  # --- Inherit dispatcher: Claude classifies via `claude -p` ---

  # First, get categories and dispatcher prompt via dry-run
  DRY_RUN_STDERR_FILE="$(mktemp)"
  DRY_RUN_OUTPUT=""
  DRY_RUN_EXIT=0
  DRY_RUN_OUTPUT="$(bash "$_AUTO_DISPATCH_DIR/auto-dispatch.sh" --config "$CONFIG_PATH" --prompt "$USER_MESSAGE" --dry-run 2>"$DRY_RUN_STDERR_FILE")" || DRY_RUN_EXIT=$?
  DRY_RUN_STDERR="$(escape_xml "$(cat "$DRY_RUN_STDERR_FILE")")"
  rm -f "$DRY_RUN_STDERR_FILE"

  if [ "$DRY_RUN_EXIT" -ne 0 ]; then
    output_context "<auto-minion-error>
${DRY_RUN_STDERR:-auto-dispatch.sh failed with exit $DRY_RUN_EXIT}
Check your auto-minion config or disable auto mode with /minion auto off.
</auto-minion-error>"
    exit 0
  fi

  # Extract dispatcher prompt and categories from dry-run output.
  # DISPATCHER_PROMPT is base64-encoded (DISPATCHER_PROMPT_B64 field) to prevent
  # user input containing "CATEGORIES:" on a new line from injecting fake headers.
  DISPATCHER_PROMPT_B64="$(echo "$DRY_RUN_OUTPUT" | sed -n 's/^DISPATCHER_PROMPT_B64://p')"
  CATEGORIES="$(echo "$DRY_RUN_OUTPUT" | sed -n 's/^CATEGORIES://p')"

  # Decode the base64-encoded dispatcher prompt
  DISPATCHER_PROMPT=""
  if [ -n "$DISPATCHER_PROMPT_B64" ]; then
    DISPATCHER_PROMPT="$(printf '%s' "$DISPATCHER_PROMPT_B64" | base64 -d 2>/dev/null)" || DISPATCHER_PROMPT=""
  fi

  # Call claude -p to classify
  CLASSIFIED_CATEGORY=""
  if command -v claude >/dev/null 2>&1 && [ -n "$DISPATCHER_PROMPT" ]; then
    CLAUDE_OUTPUT="$(printf '%s' "$DISPATCHER_PROMPT" | claude -p 2>/dev/null)" || true
    # Take the last non-empty line, trim whitespace, lowercase
    CLASSIFIED_CATEGORY="$(echo "$CLAUDE_OUTPUT" | grep -v '^[[:space:]]*$' | tail -1 | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
  fi

  # Validate the classified category against a safe character set before using it.
  # This prevents shell injection if claude -p returns unexpected output containing
  # special characters, path separators, or argument-injection payloads.
  if [ -n "$CLASSIFIED_CATEGORY" ] && ! echo "$CLASSIFIED_CATEGORY" | grep -qE '^[a-zA-Z0-9_-]+$'; then
    CLASSIFIED_CATEGORY=""
  fi

  if [ -z "$CLASSIFIED_CATEGORY" ]; then
    # Classification failed — fallback: Claude handles natively
    output_context "<auto-minion-routing>
Route: fallback (classification failed) → Claude (native)
Handle the user's prompt directly.
</auto-minion-routing>"
    exit 0
  fi

  # Execute with the classified category
  ROUTE_STDERR_FILE="$(mktemp)"
  ROUTE_OUTPUT=""
  ROUTE_EXIT=0
  ROUTE_OUTPUT="$(bash "$_AUTO_DISPATCH_DIR/auto-dispatch.sh" --config "$CONFIG_PATH" --prompt "$USER_MESSAGE" --category "$CLASSIFIED_CATEGORY" 2>"$ROUTE_STDERR_FILE")" || ROUTE_EXIT=$?
  ROUTE_STDERR="$(escape_xml "$(cat "$ROUTE_STDERR_FILE")")"
  rm -f "$ROUTE_STDERR_FILE"

  handle_dispatch_result "$ROUTE_OUTPUT" "$ROUTE_EXIT" "$ROUTE_STDERR" "$CLASSIFIED_CATEGORY" "false"
fi

# --- External dispatcher: full dispatch ---
STDERR_FILE="$(mktemp)"
trap 'rm -f "$STDERR_FILE"' EXIT

DISPATCH_EXIT=0
DISPATCH_OUTPUT="$(bash "$_AUTO_DISPATCH_DIR/auto-dispatch.sh" --config "$CONFIG_PATH" --prompt "$USER_MESSAGE" 2>"$STDERR_FILE")" || DISPATCH_EXIT=$?
DISPATCH_STDERR="$(escape_xml "$(cat "$STDERR_FILE")")"

handle_dispatch_result "$DISPATCH_OUTPUT" "$DISPATCH_EXIT" "$DISPATCH_STDERR" "unknown" "true"
