#!/usr/bin/env bash
# auto-minion-hook.sh — Shell-side logic for the auto-minion pre-message hook.
# Handles enabled check, bypass detection, dispatcher type check, and full
# dispatch for external dispatchers. Minimizes Claude's involvement by doing
# all mechanical work in bash.
#
# Reads user message from stdin (avoids argument quoting issues).
#
# Output format: structured STATUS lines followed by optional body.
#
#   STATUS:DISABLED              — auto mode not enabled, pass through
#   STATUS:BYPASS                — message matched a bypass condition
#   STATUS:NEEDS_CLASSIFICATION  — dispatcher is inherit, Claude should classify
#     (followed by auto-dispatch.sh dry-run output with category list)
#   STATUS:NATIVE                — route resolved to inherit, Claude handles natively
#     CATEGORY:<name>            — the matched category
#     FALLBACK:<reason>          — none, dispatcher_failed, etc.
#   STATUS:DISPATCHED            — external model executed, present output
#     EXIT:<code>                — auto-dispatch.sh exit code
#     (followed by auto-dispatch.sh output including headers + body)
#   STATUS:ERROR                 — config or runtime error
#     MSG:<message>              — error description
#
# Exit code is always 0 (errors are signaled via STATUS:ERROR).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read user message from stdin
USER_MESSAGE="$(cat)"

# --- Check if auto-minion mode is enabled ---
CONFIG_PATH=""
if test -f "./.claude/minions/.auto-enabled"; then
  CONFIG_PATH="$(sed -n 's/^config=//p' "./.claude/minions/.auto-enabled")"
elif test -f "$HOME/.claude/minions/.auto-enabled"; then
  CONFIG_PATH="$(sed -n 's/^config=//p' "$HOME/.claude/minions/.auto-enabled")"
fi

if [ -z "$CONFIG_PATH" ]; then
  echo "STATUS:DISABLED"
  exit 0
fi

# Validate CONFIG_PATH is an absolute path (must start with /)
if [[ "$CONFIG_PATH" != /* ]]; then
  echo "STATUS:ERROR"
  echo "MSG:Config path must be absolute: $CONFIG_PATH"
  exit 0
fi

if [ ! -f "$CONFIG_PATH" ]; then
  echo "STATUS:ERROR"
  echo "MSG:Config file not found: $CONFIG_PATH"
  exit 0
fi

# --- Bypass checks ---
if [ -z "$USER_MESSAGE" ]; then
  echo "STATUS:BYPASS"
  exit 0
fi

case "$USER_MESSAGE" in
  /*)
    echo "STATUS:BYPASS"
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
  # Claude is the dispatcher — output category info for Claude to classify
  # Capture stderr so validation failures produce STATUS:ERROR rather than
  # STATUS:NEEDS_CLASSIFICATION with incomplete data (Finding 5).
  INHERIT_STDERR_FILE="$(mktemp)"
  INHERIT_DRY_RUN_OUTPUT=""
  INHERIT_EXIT=0
  INHERIT_DRY_RUN_OUTPUT="$(bash "$SCRIPT_DIR/auto-dispatch.sh" --config "$CONFIG_PATH" --prompt "$USER_MESSAGE" --dry-run 2>"$INHERIT_STDERR_FILE")" || INHERIT_EXIT=$?
  INHERIT_STDERR="$(cat "$INHERIT_STDERR_FILE")"
  rm -f "$INHERIT_STDERR_FILE"
  if [ "$INHERIT_EXIT" -ne 0 ]; then
    echo "STATUS:ERROR"
    echo "MSG:${INHERIT_STDERR:-auto-dispatch.sh failed with exit $INHERIT_EXIT}"
    exit 0
  fi
  echo "STATUS:NEEDS_CLASSIFICATION"
  echo "SHOW_ROUTING:$SHOW_ROUTING"
  echo "CONFIG:$CONFIG_PATH"
  echo "$INHERIT_DRY_RUN_OUTPUT"
  exit 0
fi

# --- External dispatcher: full dispatch ---
STDERR_FILE="$(mktemp)"
trap 'rm -f "$STDERR_FILE"' EXIT

DISPATCH_EXIT=0
DISPATCH_OUTPUT="$(bash "$SCRIPT_DIR/auto-dispatch.sh" --config "$CONFIG_PATH" --prompt "$USER_MESSAGE" 2>"$STDERR_FILE")" || DISPATCH_EXIT=$?
DISPATCH_STDERR="$(cat "$STDERR_FILE")"

# Extract key headers from dispatch output in a single awk pass
NEEDS_NATIVE_HANDLING=false
ROUTE_CAT=""
FALLBACK_VAL=""
while IFS= read -r line; do
  case "$line" in
    NEEDS_NATIVE_HANDLING) NEEDS_NATIVE_HANDLING=true ;;
    ROUTE:*)               ROUTE_CAT="${line#ROUTE:}" ;;
    FALLBACK:*)            FALLBACK_VAL="${line#FALLBACK:}" ;;
  esac
done <<< "$DISPATCH_OUTPUT"

# Check for NEEDS_NATIVE_HANDLING — route resolved to inherit
if $NEEDS_NATIVE_HANDLING; then
  echo "STATUS:NATIVE"
  echo "SHOW_ROUTING:$SHOW_ROUTING"
  echo "CATEGORY:${ROUTE_CAT:-unknown}"
  echo "FALLBACK:${FALLBACK_VAL:-none}"
  exit 0
fi

# External route was executed (or failed)
echo "STATUS:DISPATCHED"
echo "SHOW_ROUTING:$SHOW_ROUTING"
echo "EXIT:$DISPATCH_EXIT"
if [ -n "$DISPATCH_STDERR" ]; then
  echo "STDERR:$DISPATCH_STDERR"
fi
echo "$DISPATCH_OUTPUT"
exit 0
