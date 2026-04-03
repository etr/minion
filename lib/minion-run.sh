#!/usr/bin/env bash
# minion-run.sh — Mechanical layer: parse args, construct Pi CLI command, execute.
# No UX, no prompting — exit codes and stdout/stderr only.
#
# Usage:
#   Inline mode: minion-run.sh --provider <val> --model <val> --prompt <val>
#   File mode:   minion-run.sh --file <path>
#
# Exit codes:
#   0   — Pi succeeded
#   1   — Validation error (missing required params, file not found)
#   2   — Unknown flag / flag conflict
#   N   — Pi's exit code passed through
set -uo pipefail

PROVIDER=""
MODEL=""
PROMPT=""
FILE_PATH=""

# --- Argument parsing ---
while [ $# -gt 0 ]; do
  case "$1" in
    --provider)
      [ $# -ge 2 ] || { echo "missing value for --provider" >&2; exit 2; }
      PROVIDER="$2"
      shift 2
      ;;
    --model)
      [ $# -ge 2 ] || { echo "missing value for --model" >&2; exit 2; }
      MODEL="$2"
      shift 2
      ;;
    --prompt)
      [ $# -ge 2 ] || { echo "missing value for --prompt" >&2; exit 2; }
      PROMPT="$2"
      shift 2
      ;;
    --file)
      [ $# -ge 2 ] || { echo "missing value for --file" >&2; exit 2; }
      FILE_PATH="$2"
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

# --- Mutual exclusivity check ---
if [ -n "$FILE_PATH" ] && { [ -n "$PROVIDER" ] || [ -n "$MODEL" ] || [ -n "$PROMPT" ]; }; then
  echo "--file cannot be combined with --provider, --model, or --prompt" >&2
  exit 2
fi

# --- Branch: file mode vs inline mode ---
if [ -n "$FILE_PATH" ]; then
  # --- File mode ---

  # Check file exists
  if [ ! -f "$FILE_PATH" ]; then
    echo "file not found: $FILE_PATH" >&2
    exit 1
  fi

  # Extract frontmatter (lines between first and second ---)
  FRONTMATTER="$(awk 'BEGIN{c=0} /^---[[:space:]]*$/{c++;next} c==1{print} c>=2{exit}' "$FILE_PATH")"

  # Extract body (everything after second ---)
  BODY="$(awk 'BEGIN{c=0} /^---[[:space:]]*$/{c++;next} c>=2{print}' "$FILE_PATH")"
  # Trim one leading blank line from body (common frontmatter convention)
  BODY="$(echo "$BODY" | sed '1{/^$/d}')"

  # Parse string fields from frontmatter
  parse_field() {
    echo "$FRONTMATTER" | sed -n "s/^${1}: *//p"
  }

  PROVIDER="$(parse_field provider)"
  MODEL="$(parse_field model)"

  # Validate required fields
  missing=""
  [ -z "$PROVIDER" ] && missing="${missing:+$missing, }provider"
  [ -z "$MODEL" ]    && missing="${missing:+$missing, }model"

  if [ -n "$missing" ]; then
    echo "missing: $missing" >&2
    exit 1
  fi

  # Parse optional string fields
  THINKING="$(parse_field thinking)"
  TOOLS="$(parse_field tools)"
  MAX_TURNS="$(parse_field max-turns)"
  APPEND_SYSTEM_PROMPT="$(parse_field append-system-prompt)"

  # Parse boolean fields (emit bare --flag when "true", omit otherwise)
  NO_TOOLS="$(parse_field no-tools)"
  NO_SESSION="$(parse_field no-session)"
  STREAM="$(parse_field stream)"

  # Parse list fields: collect "  - item" lines following "fieldname:" line
  parse_list() {
    echo "$FRONTMATTER" | awk -v field="$1" '
      BEGIN { found=0 }
      $0 ~ "^" field ":" { found=1; next }
      found && /^  - / { sub(/^  - /, ""); print; next }
      found { exit }
    '
  }

  # Build command
  cmd=(pi --provider "$PROVIDER" --model "$MODEL")

  # Optional string flags
  [ -n "$THINKING" ]             && cmd+=(--thinking "$THINKING")
  [ -n "$TOOLS" ]                && cmd+=(--tools "$TOOLS")
  [ -n "$MAX_TURNS" ]            && cmd+=(--max-turns "$MAX_TURNS")
  [ -n "$APPEND_SYSTEM_PROMPT" ] && cmd+=(--append-system-prompt "$APPEND_SYSTEM_PROMPT")

  # Boolean flags
  [ "$NO_TOOLS" = "true" ]   && cmd+=(--no-tools)
  [ "$NO_SESSION" = "true" ] && cmd+=(--no-session)
  [ "$STREAM" = "true" ]     && cmd+=(--stream)

  # List flags: extensions -> -e per entry
  while IFS= read -r item; do
    [ -n "$item" ] && cmd+=(-e "$item")
  done < <(parse_list extensions)

  # List flags: skills -> --skill per entry
  while IFS= read -r item; do
    [ -n "$item" ] && cmd+=(--skill "$item")
  done < <(parse_list skills)

  # Append body as prompt if non-empty
  if [ -n "$BODY" ]; then
    cmd+=("$BODY")
  fi

  # Execute
  "${cmd[@]}"
  exit $?

else
  # --- Inline mode ---
  missing=""
  [ -z "$PROVIDER" ] && missing="${missing:+$missing, }provider"
  [ -z "$MODEL" ]    && missing="${missing:+$missing, }model"
  [ -z "$PROMPT" ]   && missing="${missing:+$missing, }prompt"

  if [ -n "$missing" ]; then
    echo "missing: $missing" >&2
    exit 1
  fi

  cmd=(pi --provider "$PROVIDER" --model "$MODEL" "$PROMPT")
  "${cmd[@]}"
  exit $?
fi
