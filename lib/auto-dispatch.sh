#!/usr/bin/env bash
# auto-dispatch.sh — Mechanical layer for auto-minion mode.
# Parses auto.md config, invokes dispatcher model via Pi, resolves route,
# optionally executes the routed model via minion-run.sh.
#
# No UX, no prompting — exit codes and stdout/stderr only.
#
# Usage:
#   Classify only:    auto-dispatch.sh --config <path> --prompt <text> --dry-run
#   Classify + exec:  auto-dispatch.sh --config <path> --prompt <text>
#
# Exit codes:
#   0   — Success (routed model executed or dry-run classification returned)
#   1   — Validation error (bad config, missing fields)
#   2   — Unknown flag / flag conflict
#   3   — Dispatcher failed, used default route (still succeeded)
#   4   — All routes failed, needs ultimate fallback (inherit/Claude)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONFIG_PATH=""
USER_PROMPT=""
DRY_RUN=false
OVERRIDE_CATEGORY=""

# --- Built-in category descriptions ---
# These are the dispatcher descriptions used for classification.
# Custom categories provide their own description in the config.
declare -A BUILTIN_DESCRIPTIONS=(
  [code-review]="Reviewing, auditing, or analyzing existing code for bugs, style, performance, or security"
  [code-generation]="Writing new code, functions, classes, modules, or features from scratch"
  [testing]="Writing, analyzing, or running tests, test fixtures, or test strategies"
  [documentation]="Writing or improving documentation, comments, READMEs, or API docs"
  [explanation]="Explaining code, concepts, errors, architecture, or design patterns"
  [refactoring]="Restructuring or reorganizing existing code without changing behavior"
)

# --- Argument parsing ---
while [ $# -gt 0 ]; do
  case "$1" in
    --config)
      [ $# -ge 2 ] || { echo "missing value for --config" >&2; exit 2; }
      CONFIG_PATH="$2"
      shift 2
      ;;
    --prompt)
      [ $# -ge 2 ] || { echo "missing value for --prompt" >&2; exit 2; }
      USER_PROMPT="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --category)
      [ $# -ge 2 ] || { echo "missing value for --category" >&2; exit 2; }
      OVERRIDE_CATEGORY="$2"
      shift 2
      ;;
    -*)
      echo "unknown flag: $1" >&2
      exit 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

# --- Validate required args ---
if [ -z "$CONFIG_PATH" ]; then
  echo "missing: --config" >&2
  exit 1
fi
if [ -z "$USER_PROMPT" ]; then
  echo "missing: --prompt" >&2
  exit 1
fi
if [ ! -f "$CONFIG_PATH" ]; then
  echo "config file not found: $CONFIG_PATH" >&2
  exit 1
fi

# --- Parse config frontmatter ---
FRONTMATTER="$(awk 'BEGIN{c=0} /^---[[:space:]]*$/{c++;next} c==1{print} c>=2{exit}' "$CONFIG_PATH")"
BODY="$(awk 'BEGIN{c=0} /^---[[:space:]]*$/{c++;next} c>=2{print}' "$CONFIG_PATH")"
BODY="$(echo "$BODY" | sed '1{/^$/d}')"

# Parse a simple field from frontmatter (top-level only)
parse_field() {
  if ! echo "$1" | grep -qE '^[a-zA-Z0-9_-]+$'; then
    return 1
  fi
  echo "$FRONTMATTER" | sed -n "s/^${1}: *//p"
}

# Parse a nested field (one level deep, e.g., "dispatcher:\n  provider: X")
# Usage: parse_nested_field <parent> <child>
parse_nested_field() {
  local parent="$1"
  local child="$2"
  echo "$FRONTMATTER" | awk -v parent="$parent" -v child="$child" '
    BEGIN { in_block=0 }
    $0 ~ "^" parent ":" { in_block=1; next }
    in_block && /^[^ #]/ { exit }
    in_block && $0 ~ "^  " child ": " {
      sub("^  " child ": *", "")
      print
      exit
    }
  '
}

# Check if a top-level key has value "inherit" (single-line form)
is_inherit() {
  local val
  val="$(echo "$FRONTMATTER" | sed -n "s/^${1}: *//p")"
  [ "$val" = "inherit" ]
}

# --- Parse dispatcher config ---
DISPATCHER_INHERIT=false
DISPATCHER_PROVIDER=""
DISPATCHER_MODEL=""

validate_identifier() {
  local val="$1"
  local label="$2"
  if ! echo "$val" | grep -qE '^[a-zA-Z0-9._-]+$'; then
    echo "invalid $label: '$val' (must match [a-zA-Z0-9._-]+)" >&2
    exit 1
  fi
}

if is_inherit "dispatcher"; then
  DISPATCHER_INHERIT=true
else
  DISPATCHER_PROVIDER="$(parse_nested_field dispatcher provider)"
  DISPATCHER_MODEL="$(parse_nested_field dispatcher model)"
  if [ -z "$DISPATCHER_PROVIDER" ] || [ -z "$DISPATCHER_MODEL" ]; then
    echo "missing dispatcher provider or model in config" >&2
    exit 1
  fi
  validate_identifier "$DISPATCHER_PROVIDER" "dispatcher provider"
  validate_identifier "$DISPATCHER_MODEL" "dispatcher model"
fi

# --- Parse default route ---
DEFAULT_INHERIT=false
DEFAULT_PROVIDER=""
DEFAULT_MODEL=""

if is_inherit "default"; then
  DEFAULT_INHERIT=true
else
  DEFAULT_PROVIDER="$(parse_nested_field default provider)"
  DEFAULT_MODEL="$(parse_nested_field default model)"
  # Default is optional; if missing we rely on ultimate fallback
  if [ -n "$DEFAULT_PROVIDER" ]; then
    validate_identifier "$DEFAULT_PROVIDER" "default provider"
  fi
  if [ -n "$DEFAULT_MODEL" ]; then
    validate_identifier "$DEFAULT_MODEL" "default model"
  fi
fi

# --- Parse categories ---
# Extract category names and their provider/model/description from the config.
# Categories are under the "categories:" block. Each category is indented 2 spaces.
# A category can be "inherit" or have nested provider/model fields.

declare -A CAT_PROVIDER
declare -A CAT_MODEL
declare -A CAT_DESCRIPTION
declare -a CAT_NAMES=()
declare -A CAT_INHERIT
declare -A CAT_MINION

# Parse categories block
IN_CATEGORIES=false
CURRENT_CAT=""
while IFS= read -r line; do
  # Detect start of categories block
  if [[ "$line" =~ ^categories: ]]; then
    IN_CATEGORIES=true
    continue
  fi

  # Exit categories block on next top-level key
  if $IN_CATEGORIES && [[ "$line" =~ ^[a-zA-Z] ]]; then
    break
  fi

  if ! $IN_CATEGORIES; then
    continue
  fi

  # Category name (2-space indent, no further indent)
  if [[ "$line" =~ ^\ \ ([a-zA-Z0-9_-]+):\ *(.*)$ ]]; then
    CURRENT_CAT="${BASH_REMATCH[1]}"
    local_val="${BASH_REMATCH[2]}"
    CAT_NAMES+=("$CURRENT_CAT")
    CAT_INHERIT[$CURRENT_CAT]=false

    # Check for single-line "inherit"
    if [ "$local_val" = "inherit" ]; then
      CAT_INHERIT[$CURRENT_CAT]=true
    fi
    continue
  fi

  # Nested field under current category (4-space indent)
  if [ -n "$CURRENT_CAT" ] && [[ "$line" =~ ^\ \ \ \ ([a-zA-Z0-9_-]+):\ *(.+)$ ]]; then
    local_key="${BASH_REMATCH[1]}"
    local_value="${BASH_REMATCH[2]}"
    # Strip surrounding quotes if present
    local_value="${local_value#\"}"
    local_value="${local_value%\"}"
    case "$local_key" in
      provider)    CAT_PROVIDER[$CURRENT_CAT]="$local_value" ;;
      model)       CAT_MODEL[$CURRENT_CAT]="$local_value" ;;
      description) CAT_DESCRIPTION[$CURRENT_CAT]="$local_value" ;;
      minion)      CAT_MINION[$CURRENT_CAT]="$local_value" ;;
    esac
  fi
done <<< "$FRONTMATTER"

# Validate: each non-inherit category must have provider+model or minion
for cat in "${CAT_NAMES[@]}"; do
  if [ "${CAT_INHERIT[$cat]}" = "true" ]; then
    continue
  fi
  if [ -n "${CAT_MINION[$cat]:-}" ]; then
    validate_identifier "${CAT_MINION[$cat]}" "category '$cat' minion"
    continue
  fi
  if [ -z "${CAT_PROVIDER[$cat]:-}" ] || [ -z "${CAT_MODEL[$cat]:-}" ]; then
    echo "category '$cat' missing provider/model (and no minion: reference)" >&2
    exit 1
  fi
  validate_identifier "${CAT_PROVIDER[$cat]}" "category '$cat' provider"
  validate_identifier "${CAT_MODEL[$cat]}" "category '$cat' model"
done

# Validate: custom categories (not built-in) must have a description
for cat in "${CAT_NAMES[@]}"; do
  if [ -z "${BUILTIN_DESCRIPTIONS[$cat]:-}" ] && [ -z "${CAT_DESCRIPTION[$cat]:-}" ]; then
    echo "custom category '$cat' requires a description field" >&2
    exit 1
  fi
done

# --- Category membership check ---
# Returns 0 if the given name is a known category (or "default"), 1 otherwise.
is_valid_category() {
  local name="$1"
  [ "$name" = "default" ] && return 0
  local cat
  for cat in "${CAT_NAMES[@]}"; do
    [ "$cat" = "$name" ] && return 0
  done
  return 1
}

# --- Build category list for dispatcher prompt ---
# TRUST BOUNDARY: category descriptions come directly from the user-authored config file.
# The user who writes the config is the same user running the tool, so these values are
# trusted. The sanitization below (newline stripping, 200-char truncation) is a
# defense-in-depth measure, not a security boundary. Anyone with write access to the
# config file can influence the dispatcher prompt. Review your auto.md before use.
build_category_list() {
  for cat in "${CAT_NAMES[@]}"; do
    local desc="${CAT_DESCRIPTION[$cat]:-${BUILTIN_DESCRIPTIONS[$cat]:-}}"
    # Sanitize description: strip newlines and limit to 200 characters
    desc="${desc//$'\n'/ }"
    desc="${desc//$'\r'/ }"
    desc="${desc:0:200}"
    printf -- '- %s: %s\n' "$cat" "$desc"
  done
}

CATEGORY_LIST="$(build_category_list)"

# --- Compose dispatcher prompt ---
compose_dispatcher_prompt() {
  local template="$BODY"
  # Replace {{categories}} and {{prompt}} placeholders.
  # Both substitutions happen inside double-quoted parameter expansion — no word splitting.
  # printf '%s' is used to avoid echo interpreting escape sequences or flags in the result.
  local result
  result="${template/\{\{categories\}\}/$CATEGORY_LIST}"
  result="${result/\{\{prompt\}\}/$USER_PROMPT}"
  printf '%s\n' "$result"
}

DISPATCHER_PROMPT="$(compose_dispatcher_prompt)"

# --- Run dispatcher ---
ROUTED_CATEGORY=""
FALLBACK_REASON="none"

if [ -n "$OVERRIDE_CATEGORY" ]; then
  # Category provided via --category flag — skip dispatcher entirely
  if ! is_valid_category "$OVERRIDE_CATEGORY"; then
    echo "unknown category: $OVERRIDE_CATEGORY" >&2
    echo "valid categories: ${CAT_NAMES[*]} default" >&2
    exit 1
  fi
  ROUTED_CATEGORY="$OVERRIDE_CATEGORY"
elif $DISPATCHER_INHERIT; then
  # Dispatcher is "inherit" — output prompt and categories for Claude to classify.
  # DISPATCHER_PROMPT embeds free-text user input via $USER_PROMPT. To prevent a user
  # message containing a newline followed by a protocol header (e.g. "CATEGORIES:") from
  # injecting fake structured lines into this output, we base64-encode the prompt.
  # The hook decodes it with: printf '%s' "$B64_VALUE" | base64 -d
  DISPATCHER_PROMPT_B64="$(printf '%s' "$DISPATCHER_PROMPT" | base64 -w0 2>/dev/null || printf '%s' "$DISPATCHER_PROMPT" | base64)"
  echo "DISPATCHER:inherit"
  echo "CATEGORIES:${CAT_NAMES[*]}"
  printf 'DISPATCHER_PROMPT_B64:%s\n' "$DISPATCHER_PROMPT_B64"
  # In dry-run mode, that's all we output
  if $DRY_RUN; then
    exit 0
  fi
  # When inherit, the skill handles classification — we can't do it in bash
  # Output a special marker so the skill knows to classify inline
  echo "---"
  echo "NEEDS_INLINE_CLASSIFICATION"
  exit 0
else
  # Invoke Pi with dispatcher model.
  # USER_PROMPT is embedded in DISPATCHER_PROMPT. Double-quoting prevents word splitting/globbing.
  # Safety assumes Pi does not shell-evaluate its arguments.
  DISPATCH_OUTPUT=""
  DISPATCH_EXIT=0
  DISPATCH_OUTPUT="$(pi --provider "$DISPATCHER_PROVIDER" --model "$DISPATCHER_MODEL" \
    --no-session --no-tools "$DISPATCHER_PROMPT" 2>/dev/null)" || DISPATCH_EXIT=$?

  if [ $DISPATCH_EXIT -ne 0 ] || [ -z "$DISPATCH_OUTPUT" ]; then
    # Dispatcher failed — fall back to default
    FALLBACK_REASON="dispatcher_failed"
    ROUTED_CATEGORY="default"
  else
    # Take the last non-empty line (models may output extra text), trim whitespace, lowercase
    ROUTED_CATEGORY="$(echo "$DISPATCH_OUTPUT" | grep -v '^[[:space:]]*$' | tail -1 | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"

    # Validate against known categories
    if ! is_valid_category "$ROUTED_CATEGORY"; then
      # Unrecognized response — fall back to default
      FALLBACK_REASON="dispatcher_unrecognized"
      ROUTED_CATEGORY="default"
    fi
  fi
fi

# --- Resolve route ---
ROUTE_PROVIDER=""
ROUTE_MODEL=""
ROUTE_INHERIT=false
ROUTE_MINION=""

if [ "$ROUTED_CATEGORY" = "default" ]; then
  if $DEFAULT_INHERIT; then
    ROUTE_INHERIT=true
  elif [ -n "$DEFAULT_PROVIDER" ] && [ -n "$DEFAULT_MODEL" ]; then
    ROUTE_PROVIDER="$DEFAULT_PROVIDER"
    ROUTE_MODEL="$DEFAULT_MODEL"
  else
    # No default configured — signal ultimate fallback
    ROUTE_INHERIT=true
    FALLBACK_REASON="no_default"
  fi
else
  if [ "${CAT_INHERIT[$ROUTED_CATEGORY]}" = "true" ]; then
    ROUTE_INHERIT=true
  elif [ -n "${CAT_MINION[$ROUTED_CATEGORY]:-}" ]; then
    ROUTE_MINION="${CAT_MINION[$ROUTED_CATEGORY]}"
  else
    ROUTE_PROVIDER="${CAT_PROVIDER[$ROUTED_CATEGORY]}"
    ROUTE_MODEL="${CAT_MODEL[$ROUTED_CATEGORY]}"
  fi
fi

# --- Output route header ---
echo "ROUTE:$ROUTED_CATEGORY"
if $ROUTE_INHERIT; then
  echo "PROVIDER:inherit"
  echo "MODEL:inherit"
elif [ -n "$ROUTE_MINION" ]; then
  echo "MINION:$ROUTE_MINION"
else
  echo "PROVIDER:$ROUTE_PROVIDER"
  echo "MODEL:$ROUTE_MODEL"
fi
echo "FALLBACK:$FALLBACK_REASON"

# --- Dry-run: stop here ---
if $DRY_RUN; then
  if [ "$FALLBACK_REASON" != "none" ]; then
    exit 3
  fi
  exit 0
fi

echo "---"

# --- Execute routed model ---
if $ROUTE_INHERIT; then
  # Signal to skill that Claude should handle this natively
  echo "NEEDS_NATIVE_HANDLING"
  if [ "$FALLBACK_REASON" != "none" ]; then
    exit 3
  fi
  exit 0
fi

EXEC_EXIT=0
if [ -n "$ROUTE_MINION" ]; then
  # Execute via minion file — resolve the minion name first
  MINION_FILE=""
  if [ -f "./.claude/minions/${ROUTE_MINION}.md" ]; then
    MINION_FILE="$(pwd)/.claude/minions/${ROUTE_MINION}.md"
  elif [ -f "$HOME/.claude/minions/${ROUTE_MINION}.md" ]; then
    MINION_FILE="$HOME/.claude/minions/${ROUTE_MINION}.md"
  else
    echo "minion file not found for: $ROUTE_MINION" >&2
    echo "searched: ./.claude/minions/${ROUTE_MINION}.md" >&2
    echo "searched: $HOME/.claude/minions/${ROUTE_MINION}.md" >&2
    # Try default route as fallback
    if [ -n "$DEFAULT_PROVIDER" ] && [ -n "$DEFAULT_MODEL" ]; then
      bash "$SCRIPT_DIR/minion-run.sh" --provider "$DEFAULT_PROVIDER" --model "$DEFAULT_MODEL" --prompt "$USER_PROMPT" || EXEC_EXIT=$?
    else
      exit 4
    fi
  fi

  if [ -n "$MINION_FILE" ]; then
    bash "$SCRIPT_DIR/minion-run.sh" --file "$MINION_FILE" --extra-input "$USER_PROMPT" || EXEC_EXIT=$?
  fi
else
  # Execute via inline mode
  bash "$SCRIPT_DIR/minion-run.sh" --provider "$ROUTE_PROVIDER" --model "$ROUTE_MODEL" --prompt "$USER_PROMPT" || EXEC_EXIT=$?
fi

if [ $EXEC_EXIT -ne 0 ]; then
  # Route execution failed — try default if we haven't already
  if [ "$ROUTED_CATEGORY" != "default" ] && [ -n "$DEFAULT_PROVIDER" ] && [ -n "$DEFAULT_MODEL" ]; then
    echo "" >&2
    echo "route '$ROUTED_CATEGORY' failed (exit $EXEC_EXIT), trying default route" >&2
    bash "$SCRIPT_DIR/minion-run.sh" --provider "$DEFAULT_PROVIDER" --model "$DEFAULT_MODEL" --prompt "$USER_PROMPT" || {
      echo "default route also failed (exit $?)" >&2
      exit 4
    }
    exit 3
  fi
  exit 4
fi

if [ "$FALLBACK_REASON" != "none" ]; then
  exit 3
fi
exit 0
