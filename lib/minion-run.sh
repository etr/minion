#!/usr/bin/env bash
# minion-run.sh — Mechanical layer: parse args, construct Pi CLI command, execute.
# No UX, no prompting — exit codes and stdout/stderr only.
#
# Modes:
#   Inline mode:  --provider X --model Y --prompt Z [--extra-input ...] [other flags]
#   File mode:    --file <path> [--extra-input ...] [override flags]
#   Mixed mode:   --file <path> + any subset of inline override flags
#
# Inline overrides (when used with --file) replace the file's value for that field.
# For list fields (extensions, pi-skills, claude-skills) the inline value REPLACES
# the file value (no append).
#
# Exit codes:
#   0   — Pi succeeded
#   1   — Validation error (missing required params, file not found, skill not found)
#   2   — Unknown flag / missing flag value
#   N   — Pi's exit code passed through
set -uo pipefail

# --- Inline-supplied values + "set" markers ---
PROVIDER=""; PROVIDER_SET=0
MODEL=""; MODEL_SET=0
PROMPT=""; PROMPT_SET=0
THINKING=""; THINKING_SET=0
TOOLS=""; TOOLS_SET=0
MAX_TURNS=""; MAX_TURNS_SET=0
APPEND_SYS=""; APPEND_SYS_SET=0
NO_TOOLS_FLAG=0
NO_SESSION_FLAG=0
STREAM_FLAG=0
EXTENSIONS_INLINE=""; EXTENSIONS_INLINE_SET=0
PI_SKILLS_INLINE=""; PI_SKILLS_INLINE_SET=0
CLAUDE_SKILLS_INLINE=""; CLAUDE_SKILLS_INLINE_SET=0
FILE_PATH=""
EXTRA_INPUT=""

# Split a comma-separated list into a newline-separated list (one entry per line)
csv_to_lines() {
  local input="$1"
  printf '%s' "$input" | tr ',' '\n'
}

# --- Argument parsing ---
while [ $# -gt 0 ]; do
  case "$1" in
    --provider)
      [ $# -ge 2 ] || { echo "missing value for --provider" >&2; exit 2; }
      PROVIDER="$2"; PROVIDER_SET=1
      shift 2
      ;;
    --model)
      [ $# -ge 2 ] || { echo "missing value for --model" >&2; exit 2; }
      MODEL="$2"; MODEL_SET=1
      shift 2
      ;;
    --prompt)
      [ $# -ge 2 ] || { echo "missing value for --prompt" >&2; exit 2; }
      PROMPT="$2"; PROMPT_SET=1
      shift 2
      ;;
    --thinking)
      [ $# -ge 2 ] || { echo "missing value for --thinking" >&2; exit 2; }
      THINKING="$2"; THINKING_SET=1
      shift 2
      ;;
    --tools)
      [ $# -ge 2 ] || { echo "missing value for --tools" >&2; exit 2; }
      TOOLS="$2"; TOOLS_SET=1
      shift 2
      ;;
    --max-turns)
      [ $# -ge 2 ] || { echo "missing value for --max-turns" >&2; exit 2; }
      MAX_TURNS="$2"; MAX_TURNS_SET=1
      shift 2
      ;;
    --append-system-prompt)
      [ $# -ge 2 ] || { echo "missing value for --append-system-prompt" >&2; exit 2; }
      APPEND_SYS="$2"; APPEND_SYS_SET=1
      shift 2
      ;;
    --no-tools)
      NO_TOOLS_FLAG=1
      shift
      ;;
    --no-session)
      NO_SESSION_FLAG=1
      shift
      ;;
    --stream)
      STREAM_FLAG=1
      shift
      ;;
    --extensions)
      [ $# -ge 2 ] || { echo "missing value for --extensions" >&2; exit 2; }
      EXTENSIONS_INLINE="$2"; EXTENSIONS_INLINE_SET=1
      shift 2
      ;;
    --pi-skills)
      [ $# -ge 2 ] || { echo "missing value for --pi-skills" >&2; exit 2; }
      PI_SKILLS_INLINE="$2"; PI_SKILLS_INLINE_SET=1
      shift 2
      ;;
    --claude-skills)
      [ $# -ge 2 ] || { echo "missing value for --claude-skills" >&2; exit 2; }
      CLAUDE_SKILLS_INLINE="$2"; CLAUDE_SKILLS_INLINE_SET=1
      shift 2
      ;;
    --file)
      [ $# -ge 2 ] || { echo "missing value for --file" >&2; exit 2; }
      FILE_PATH="$2"
      shift 2
      ;;
    --extra-input)
      [ $# -ge 2 ] || { echo "missing value for --extra-input" >&2; exit 2; }
      EXTRA_INPUT="$2"
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

# --- Frontmatter parsing helpers (only used if --file is given) ---

# Extract a flat string field from frontmatter (single-line value).
parse_field() {
  if ! echo "$1" | grep -qE '^[a-zA-Z0-9_-]+$'; then
    return 1
  fi
  echo "$FRONTMATTER" | sed -n "s/^${1}: *//p"
}

# Extract a list field: collect "  - item" lines following "fieldname:" line.
parse_list() {
  echo "$FRONTMATTER" | awk -v field="$1" '
    BEGIN { found=0 }
    $0 ~ "^" field ":" { found=1; next }
    found && /^  - / { sub(/^  - /, ""); print; next }
    found { exit }
  '
}

# --- File mode preparation: parse frontmatter into FILE_* variables ---
FILE_PROVIDER=""
FILE_MODEL=""
FILE_THINKING=""
FILE_TOOLS=""
FILE_MAX_TURNS=""
FILE_APPEND_SYS=""
FILE_NO_TOOLS=""
FILE_NO_SESSION=""
FILE_STREAM=""
FILE_EXTENSIONS=""    # newline-separated
FILE_PI_SKILLS=""     # newline-separated
FILE_CLAUDE_SKILLS="" # newline-separated
FILE_BODY=""

if [ -n "$FILE_PATH" ]; then
  if [ ! -f "$FILE_PATH" ]; then
    echo "file not found: $FILE_PATH" >&2
    exit 1
  fi

  FRONTMATTER="$(awk 'BEGIN{c=0} /^---[[:space:]]*$/{c++;next} c==1{print} c>=2{exit}' "$FILE_PATH")"
  FILE_BODY="$(awk 'BEGIN{c=0} /^---[[:space:]]*$/{c++;next} c>=2{print}' "$FILE_PATH")"
  # Trim one leading blank line from body (common frontmatter convention)
  FILE_BODY="$(echo "$FILE_BODY" | sed '1{/^$/d}')"

  FILE_PROVIDER="$(parse_field provider)"
  FILE_MODEL="$(parse_field model)"
  FILE_THINKING="$(parse_field thinking)"
  FILE_TOOLS="$(parse_field tools)"
  FILE_MAX_TURNS="$(parse_field max-turns)"
  FILE_APPEND_SYS="$(parse_field append-system-prompt)"
  FILE_NO_TOOLS="$(parse_field no-tools)"
  FILE_NO_SESSION="$(parse_field no-session)"
  FILE_STREAM="$(parse_field stream)"
  FILE_EXTENSIONS="$(parse_list extensions)"
  # pi-skills wins over legacy 'skills'
  FILE_PI_SKILLS="$(parse_list pi-skills)"
  if [ -z "$FILE_PI_SKILLS" ]; then
    FILE_PI_SKILLS="$(parse_list skills)"
  fi
  FILE_CLAUDE_SKILLS="$(parse_list claude-skills)"
fi

# --- Merge inline overrides with file values ---
EFFECTIVE_PROVIDER="$([ "$PROVIDER_SET" = "1" ] && echo "$PROVIDER" || echo "$FILE_PROVIDER")"
EFFECTIVE_MODEL="$([ "$MODEL_SET" = "1" ] && echo "$MODEL" || echo "$FILE_MODEL")"
EFFECTIVE_THINKING="$([ "$THINKING_SET" = "1" ] && echo "$THINKING" || echo "$FILE_THINKING")"
EFFECTIVE_TOOLS="$([ "$TOOLS_SET" = "1" ] && echo "$TOOLS" || echo "$FILE_TOOLS")"
EFFECTIVE_MAX_TURNS="$([ "$MAX_TURNS_SET" = "1" ] && echo "$MAX_TURNS" || echo "$FILE_MAX_TURNS")"
EFFECTIVE_APPEND_SYS="$([ "$APPEND_SYS_SET" = "1" ] && echo "$APPEND_SYS" || echo "$FILE_APPEND_SYS")"

# Booleans: inline flag presence forces true; otherwise inherit file value (true/false).
EFFECTIVE_NO_TOOLS="$FILE_NO_TOOLS"
[ "$NO_TOOLS_FLAG" = "1" ] && EFFECTIVE_NO_TOOLS="true"
EFFECTIVE_NO_SESSION="$FILE_NO_SESSION"
[ "$NO_SESSION_FLAG" = "1" ] && EFFECTIVE_NO_SESSION="true"
EFFECTIVE_STREAM="$FILE_STREAM"
[ "$STREAM_FLAG" = "1" ] && EFFECTIVE_STREAM="true"

# Lists: inline replaces file entirely.
if [ "$EXTENSIONS_INLINE_SET" = "1" ]; then
  EFFECTIVE_EXTENSIONS="$(csv_to_lines "$EXTENSIONS_INLINE")"
else
  EFFECTIVE_EXTENSIONS="$FILE_EXTENSIONS"
fi
if [ "$PI_SKILLS_INLINE_SET" = "1" ]; then
  EFFECTIVE_PI_SKILLS="$(csv_to_lines "$PI_SKILLS_INLINE")"
else
  EFFECTIVE_PI_SKILLS="$FILE_PI_SKILLS"
fi
if [ "$CLAUDE_SKILLS_INLINE_SET" = "1" ]; then
  EFFECTIVE_CLAUDE_SKILLS="$(csv_to_lines "$CLAUDE_SKILLS_INLINE")"
else
  EFFECTIVE_CLAUDE_SKILLS="$FILE_CLAUDE_SKILLS"
fi

# Body (file mode): file body unless --prompt overrides it.
if [ -n "$FILE_PATH" ]; then
  if [ "$PROMPT_SET" = "1" ]; then
    EFFECTIVE_BODY="$PROMPT"
  else
    EFFECTIVE_BODY="$FILE_BODY"
  fi
else
  # Inline mode: body is --prompt value (may be empty)
  EFFECTIVE_BODY="$PROMPT"
fi

# --- Validation ---
missing=""
[ -z "$EFFECTIVE_PROVIDER" ] && missing="${missing:+$missing, }provider"
[ -z "$EFFECTIVE_MODEL" ]    && missing="${missing:+$missing, }model"

if [ -n "$missing" ]; then
  echo "missing: $missing" >&2
  exit 1
fi

# Inline mode: must have SOME prompt content
# (--prompt, --extra-input, or --claude-skills must produce something).
if [ -z "$FILE_PATH" ]; then
  has_content=0
  [ -n "$EFFECTIVE_BODY" ] && has_content=1
  [ -n "$EXTRA_INPUT" ] && has_content=1
  [ -n "$EFFECTIVE_CLAUDE_SKILLS" ] && has_content=1
  if [ "$has_content" = "0" ]; then
    echo "missing: prompt" >&2
    exit 1
  fi
fi

# --- Claude-skills loading ---

# Validate a bare skill name. Returns 0 if valid, 1 otherwise.
valid_skill_name() {
  echo "$1" | grep -qE '^[a-zA-Z0-9._-]+$'
}

# Resolve a single claude-skill entry to an absolute SKILL.md path.
# Echoes the path on stdout, returns 0 on success.
# On failure, echoes nothing and returns 1.
resolve_claude_skill() {
  local entry="$1"

  # Case 1: absolute path — confined to safe roots
  case "$entry" in
    /*)
      [ -f "$entry" ] || return 1
      # Canonicalize and verify the path is under an allowed root.
      local canonical
      canonical="$(realpath -m "$entry" 2>/dev/null || readlink -f "$entry" 2>/dev/null)"
      if [ -z "$canonical" ]; then
        echo "cannot canonicalize claude-skill path: realpath/readlink unavailable" >&2
        return 1
      fi
      local allowed=0
      for allowed_root in \
        "$(realpath -m "./.claude/skills" 2>/dev/null || echo "./.claude/skills")" \
        "$HOME/.claude/skills" \
        "$HOME/.claude/plugins/cache"
      do
        case "$canonical" in
          "$allowed_root"/*) allowed=1; break ;;
        esac
      done
      if [ "$allowed" -eq 0 ]; then
        echo "claude-skill absolute path is outside allowed directories: $entry" >&2
        return 1
      fi
      echo "$entry"
      return 0
      ;;
  esac

  # Case 2: plugin:skill qualified
  case "$entry" in
    *:*)
      local plugin_part="${entry%%:*}"
      local skill_part="${entry#*:}"
      valid_skill_name "$plugin_part" || return 2
      valid_skill_name "$skill_part" || return 2
      local match
      match="$(ls -d "$HOME/.claude/plugins/cache/"*/"$plugin_part"/*/skills/"$skill_part"/SKILL.md 2>/dev/null | sort | head -1)"
      [ -n "$match" ] || return 1
      echo "$match"
      return 0
      ;;
  esac

  # Case 3: bare name
  valid_skill_name "$entry" || return 2

  # 3a. Project-local
  if [ -f "./.claude/skills/$entry/SKILL.md" ]; then
    echo "$(pwd)/.claude/skills/$entry/SKILL.md"
    return 0
  fi
  # 3b. User-global
  if [ -f "$HOME/.claude/skills/$entry/SKILL.md" ]; then
    echo "$HOME/.claude/skills/$entry/SKILL.md"
    return 0
  fi
  # 3c. Plugin cache, any plugin
  local match
  match="$(ls -d "$HOME/.claude/plugins/cache/"*/*/*/skills/"$entry"/SKILL.md 2>/dev/null | sort | head -1)"
  if [ -n "$match" ]; then
    echo "$match"
    return 0
  fi
  return 1
}

# Apply tool-name transformations to a skill body. Reads from stdin, writes to stdout.
transform_skill_body() {
  sed \
    -e 's|\bRead\b tool|read tool|g' \
    -e 's|\bEdit\b tool|edit tool|g' \
    -e 's|\bWrite\b tool|write tool|g' \
    -e 's|\bBash\b tool|bash tool|g' \
    -e 's|\bGlob\b tool|find tool|g' \
    -e 's|\bGrep\b tool|grep tool|g' \
    -e 's|`Read`|`read`|g' \
    -e 's|`Edit`|`edit`|g' \
    -e 's|`Write`|`write`|g' \
    -e 's|`Bash`|`bash`|g' \
    -e 's|`Glob`|`find`|g' \
    -e 's|`Grep`|`grep`|g' \
    -e 's|`Task`|`groundwork_agent`|g' \
    -e 's|the Task tool|the groundwork_agent tool|g' \
    -e 's|Use Task tool|Use groundwork_agent tool|g' \
    -e 's|Task tool|groundwork_agent tool|g' \
    -e 's|subagent_type|agent|g' \
    -e 's|Skill(skill="\([^"]*\)"[^)]*)|the \1 workflow|g' \
    -e 's|AskUserQuestion|Ask the user|g' \
    -e 's|\${CLAUDE_PLUGIN_ROOT}|the plugin directory|g' \
    -e 's|subagent|sub-task|g'
}

# Strip YAML frontmatter from a file's content (everything between first '---' pair).
# Pre-frontmatter content (before the first ---) is suppressed, not emitted.
strip_frontmatter() {
  awk 'BEGIN{c=0} /^---[[:space:]]*$/{c++;next} c==1{next} c>=2{print}' "$1"
}

# Determine the display name (### header) for a resolved skill path.
# For an absolute-path entry, use the parent directory basename; otherwise use
# the basename of the parent of SKILL.md.
skill_display_name() {
  local entry="$1" path="$2"
  case "$entry" in
    /*)
      basename "$(dirname "$path")"
      ;;
    *:*)
      # plugin:skill — use the skill_part
      echo "${entry#*:}"
      ;;
    *)
      echo "$entry"
      ;;
  esac
}

# Build the "## Available Skills" section for the EFFECTIVE_CLAUDE_SKILLS list.
# On success, prints the section to stdout. On failure, prints actionable error
# to stderr and exits 1.
build_skills_section() {
  [ -z "$EFFECTIVE_CLAUDE_SKILLS" ] && return 0

  printf '## Available Skills\n\n'
  printf 'The following skills provide context for this task. Apply them as needed.\n\n'

  local entry resolved rc display body_stripped body_transformed
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    set +e
    resolved="$(resolve_claude_skill "$entry")"
    rc=$?
    set -e

    if [ "$rc" = "2" ]; then
      echo "invalid claude-skill name: '$entry'" >&2
      echo "  Bare names and plugin:skill names must match: ^[a-zA-Z0-9._-]+\$" >&2
      exit 1
    fi
    if [ "$rc" != "0" ] || [ -z "$resolved" ]; then
      echo "could not resolve claude-skill: '$entry'" >&2
      echo "Searched the following locations:" >&2
      case "$entry" in
        /*)
          echo "  - $entry (absolute path)" >&2
          ;;
        *:*)
          local plugin_part="${entry%%:*}"
          local skill_part="${entry#*:}"
          echo "  - \$HOME/.claude/plugins/cache/*/$plugin_part/*/skills/$skill_part/SKILL.md" >&2
          ;;
        *)
          echo "  - ./.claude/skills/$entry/SKILL.md (project-local)" >&2
          echo "  - \$HOME/.claude/skills/$entry/SKILL.md (user-global)" >&2
          echo "  - \$HOME/.claude/plugins/cache/*/*/*/skills/$entry/SKILL.md (plugin cache)" >&2
          ;;
      esac
      exit 1
    fi

    display="$(skill_display_name "$entry" "$resolved")"
    body_stripped="$(strip_frontmatter "$resolved")"
    body_transformed="$(echo "$body_stripped" | transform_skill_body)"

    printf '### %s\n\n%s\n\n' "$display" "$body_transformed"
  done <<EOF
$EFFECTIVE_CLAUDE_SKILLS
EOF
}

# --- Compose the prompt ---
SKILLS_SECTION="$(build_skills_section)"
SKILLS_RC=$?
if [ "$SKILLS_RC" != "0" ]; then
  exit "$SKILLS_RC"
fi

if [ -n "$SKILLS_SECTION" ]; then
  # The --- separator goes between the (trailing-newline-stripped) skills section
  # and any body/extra-input that follows. Use $'\n' to control spacing precisely.
  COMPOSED="${SKILLS_SECTION}"$'\n\n---'
  if [ -n "$EFFECTIVE_BODY" ]; then
    COMPOSED="${COMPOSED}"$'\n\n'"${EFFECTIVE_BODY}"
  fi
  if [ -n "$EXTRA_INPUT" ]; then
    COMPOSED="${COMPOSED}"$'\n\n'"${EXTRA_INPUT}"
  fi
else
  COMPOSED=""
  if [ -n "$EFFECTIVE_BODY" ]; then
    COMPOSED="$EFFECTIVE_BODY"
  fi
  if [ -n "$EXTRA_INPUT" ]; then
    if [ -n "$COMPOSED" ]; then
      COMPOSED="${COMPOSED}"$'\n\n'"${EXTRA_INPUT}"
    else
      COMPOSED="$EXTRA_INPUT"
    fi
  fi
fi

# --- Build the Pi command ---
cmd=(pi --provider "$EFFECTIVE_PROVIDER" --model "$EFFECTIVE_MODEL")

[ -n "$EFFECTIVE_THINKING" ]    && cmd+=(--thinking "$EFFECTIVE_THINKING")
[ -n "$EFFECTIVE_TOOLS" ]       && cmd+=(--tools "$EFFECTIVE_TOOLS")
[ -n "$EFFECTIVE_MAX_TURNS" ]   && cmd+=(--max-turns "$EFFECTIVE_MAX_TURNS")
[ -n "$EFFECTIVE_APPEND_SYS" ]  && cmd+=(--append-system-prompt "$EFFECTIVE_APPEND_SYS")

[ "$EFFECTIVE_NO_TOOLS" = "true" ]   && cmd+=(--no-tools)
[ "$EFFECTIVE_NO_SESSION" = "true" ] && cmd+=(--no-session)
[ "$EFFECTIVE_STREAM" = "true" ]     && cmd+=(--stream)

# Extensions (-e per entry)
while IFS= read -r item; do
  [ -n "$item" ] && cmd+=(-e "$item")
done <<EOF
$EFFECTIVE_EXTENSIONS
EOF

# Pi skills (--skill per entry)
while IFS= read -r item; do
  [ -n "$item" ] && cmd+=(--skill "$item")
done <<EOF
$EFFECTIVE_PI_SKILLS
EOF

# --- Execute ---
# The composed prompt is delivered via stdin rather than as a positional argument.
# Pi CLI does not support an end-of-options "--" sentinel, so a prompt that begins
# with "--" passed positionally would be parsed as an unknown (or worse, recognized)
# flag — the same security concern that motivated the "--" sentinel previously.
# Stdin content is never parsed as argv, so this defangs flag injection completely
# while remaining compatible with Pi's interface (Pi reads its prompt from stdin
# when stdin is not a tty, which is always the case here).
"${cmd[@]}" <<< "$COMPOSED"
exit $?
