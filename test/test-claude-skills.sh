#!/usr/bin/env bash
#
# Tests for lib/minion-run.sh — claude-skills loading, pi-skills rename,
# and inline parameter overrides (FEATURE-claude-skills).
#
# Uses a mock pi script to verify what minion-run.sh sends to Pi.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MINION_RUN="$ROOT/lib/minion-run.sh"

PASS=0
FAIL=0

# --- Mock Pi setup ---
MOCK_DIR="$(mktemp -d)"
trap 'rm -rf "$MOCK_DIR"' EXIT

cat > "$MOCK_DIR/pi" <<'MOCKEOF'
#!/usr/bin/env bash
# Echo all arguments so tests can verify what was passed.
# We use a delimiter that won't appear in args so we can separate flags from prompt.
echo "MOCK_ARGS: $*"
exit 0
MOCKEOF
chmod +x "$MOCK_DIR/pi"

export PATH="$MOCK_DIR:$PATH"

# --- Test helpers ---

check() {
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    FAIL=$((FAIL + 1))
  fi
}

# Run a command, capture stdout+stderr+exit, then check assertions.
# Usage: run_and_check "desc" expected_exit "stdout_contains" "stderr_contains" -- cmd args...
run_and_check() {
  local description="$1"
  local expected_exit="$2"
  local stdout_pattern="$3"
  local stderr_pattern="$4"
  shift 4
  [ "${1:-}" = "--" ] && shift

  local stdout stderr actual_exit

  set +e
  stdout="$("$@" 2>"$MOCK_DIR/_stderr")"
  actual_exit=$?
  set -e
  stderr="$(cat "$MOCK_DIR/_stderr")"

  local all_pass=true

  if [ "$actual_exit" != "$expected_exit" ]; then
    all_pass=false
  fi

  if [ -n "$stdout_pattern" ]; then
    if ! echo "$stdout" | grep -qF -- "$stdout_pattern"; then
      all_pass=false
    fi
  fi

  if [ -n "$stderr_pattern" ]; then
    if ! echo "$stderr" | grep -qF -- "$stderr_pattern"; then
      all_pass=false
    fi
  fi

  if $all_pass; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    if [ "$actual_exit" != "$expected_exit" ]; then
      echo "        exit: expected=$expected_exit actual=$actual_exit"
    fi
    if [ -n "$stdout_pattern" ] && ! echo "$stdout" | grep -qF -- "$stdout_pattern"; then
      echo "        stdout missing: '$stdout_pattern'"
      echo "        stdout was: '$stdout'"
    fi
    if [ -n "$stderr_pattern" ] && ! echo "$stderr" | grep -qF -- "$stderr_pattern"; then
      echo "        stderr missing: '$stderr_pattern'"
      echo "        stderr was: '$stderr'"
    fi
    FAIL=$((FAIL + 1))
  fi
}

# Run a command verifying that a substring is NOT in its stdout
check_stdout_absent() {
  local description="$1"
  local pattern="$2"
  shift 2
  [ "${1:-}" = "--" ] && shift

  local stdout
  set +e
  stdout="$("$@" 2>/dev/null)"
  set -e

  if echo "$stdout" | grep -qF -- "$pattern"; then
    echo "  FAIL: $description"
    echo "        stdout unexpectedly contains: '$pattern'"
    echo "        stdout was: '$stdout'"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  fi
}

# Helper to create a minion file with given content. Returns the path.
create_minion_file() {
  local content="$1"
  local path="$MOCK_DIR/test-minion-$RANDOM.md"
  printf '%s\n' "$content" > "$path"
  echo "$path"
}

# Helper to create a Claude skill at a given path. Skill contents include
# frontmatter and a body that exercises the tool-name transformations.
create_skill_file() {
  local skill_path="$1"
  mkdir -p "$(dirname "$skill_path")"
  cat > "$skill_path" <<'EOF'
---
name: example-skill
description: An example skill for tests
---
# Example Skill

Use the Read tool when you need to view a file.
The `Bash` command runs shell scripts.
Skill(skill="other-thing") to chain workflows.
Ask via AskUserQuestion when uncertain.
The plugin lives at ${CLAUDE_PLUGIN_ROOT}.
EOF
}

echo "=== claude-skills Tests ==="
echo ""

# ============================================================
# Phase 1: pi-skills rename + backwards compat
# ============================================================
echo "-- pi-skills rename --"

# 1a. pi-skills field maps to --skill flag (one per entry)
MINFILE_PISKILLS="$(create_minion_file "---
provider: openai
model: gpt-4
pi-skills:
  - alpha
  - beta
---
Do stuff")"

run_and_check \
  "pi-skills field maps to --skill per entry" \
  0 \
  "--skill alpha --skill beta" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_PISKILLS"

# 1b. legacy 'skills' field still works
MINFILE_LEGACY="$(create_minion_file "---
provider: openai
model: gpt-4
skills:
  - legacy-one
  - legacy-two
---
Do stuff")"

run_and_check \
  "legacy 'skills' field still maps to --skill per entry" \
  0 \
  "--skill legacy-one --skill legacy-two" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_LEGACY"

# 1c. when both present, pi-skills wins (legacy is silently ignored)
MINFILE_BOTH="$(create_minion_file "---
provider: openai
model: gpt-4
pi-skills:
  - new-one
skills:
  - old-one
---
Do stuff")"

run_and_check \
  "pi-skills wins over legacy 'skills' when both present" \
  0 \
  "--skill new-one" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_BOTH"

check_stdout_absent \
  "legacy 'skills' values absent when pi-skills present" \
  "old-one" \
  -- "$MINION_RUN" --file "$MINFILE_BOTH"

# ============================================================
# Phase 2: claude-skills resolution
# ============================================================
echo ""
echo "-- claude-skills resolution --"

# 2a. Project-local resolution: ./.claude/skills/<name>/SKILL.md
PROJECT_DIR="$MOCK_DIR/project-resolution"
mkdir -p "$PROJECT_DIR"
create_skill_file "$PROJECT_DIR/.claude/skills/proj-skill/SKILL.md"
MINFILE_PROJ="$(create_minion_file "---
provider: openai
model: gpt-4
claude-skills:
  - proj-skill
---
Body text")"

check_project_local() {
  local stdout
  set +e
  stdout="$(cd "$PROJECT_DIR" && "$MINION_RUN" --file "$MINFILE_PROJ" 2>/dev/null)"
  local rc=$?
  set -e
  [ "$rc" = "0" ] || { echo "        rc=$rc"; return 1; }
  echo "$stdout" | grep -qF "## Available Skills" || { echo "        missing ## Available Skills"; return 1; }
  echo "$stdout" | grep -qF "### proj-skill" || { echo "        missing ### proj-skill header"; return 1; }
  echo "$stdout" | grep -qF "Use the read tool" || { echo "        missing transformed Read tool"; return 1; }
}
check "claude-skills resolves project-local skill" check_project_local

# 2b. User-global resolution: $HOME/.claude/skills/<name>/SKILL.md
HOME_DIR="$MOCK_DIR/home-resolution"
mkdir -p "$HOME_DIR"
create_skill_file "$HOME_DIR/.claude/skills/home-skill/SKILL.md"
MINFILE_HOME="$(create_minion_file "---
provider: openai
model: gpt-4
claude-skills:
  - home-skill
---
Body text")"

# We must run in a directory that does NOT have .claude/skills/home-skill
EMPTY_DIR="$MOCK_DIR/empty-cwd-home"
mkdir -p "$EMPTY_DIR"

check_home_global() {
  local stdout
  set +e
  stdout="$(cd "$EMPTY_DIR" && HOME="$HOME_DIR" "$MINION_RUN" --file "$MINFILE_HOME" 2>/dev/null)"
  local rc=$?
  set -e
  [ "$rc" = "0" ] || { echo "        rc=$rc"; return 1; }
  echo "$stdout" | grep -qF "### home-skill" || return 1
  echo "$stdout" | grep -qF "Use the read tool" || return 1
}
check "claude-skills resolves \$HOME-global skill" check_home_global

# 2c. plugin:skill qualified name resolution
PLUGIN_HOME="$MOCK_DIR/plugin-home"
mkdir -p "$PLUGIN_HOME"
create_skill_file "$PLUGIN_HOME/.claude/plugins/cache/marketplace-x/plugin-dev/v1/skills/hook-development/SKILL.md"
MINFILE_PLUGIN="$(create_minion_file "---
provider: openai
model: gpt-4
claude-skills:
  - plugin-dev:hook-development
---
Body text")"

EMPTY_DIR2="$MOCK_DIR/empty-cwd-plugin"
mkdir -p "$EMPTY_DIR2"

check_plugin_qualified() {
  local stdout
  set +e
  stdout="$(cd "$EMPTY_DIR2" && HOME="$PLUGIN_HOME" "$MINION_RUN" --file "$MINFILE_PLUGIN" 2>/dev/null)"
  local rc=$?
  set -e
  [ "$rc" = "0" ] || { echo "        rc=$rc"; return 1; }
  echo "$stdout" | grep -qF "### hook-development" || return 1
  echo "$stdout" | grep -qF "Use the read tool" || return 1
}
check "claude-skills resolves plugin:skill qualified name" check_plugin_qualified

# 2d. Bare name resolution falls through to plugins cache
PLUGIN_HOME2="$MOCK_DIR/plugin-home-bare"
mkdir -p "$PLUGIN_HOME2"
create_skill_file "$PLUGIN_HOME2/.claude/plugins/cache/marketplace-y/some-plugin/v1/skills/bare-skill/SKILL.md"
MINFILE_BARE="$(create_minion_file "---
provider: openai
model: gpt-4
claude-skills:
  - bare-skill
---
Body text")"

EMPTY_DIR3="$MOCK_DIR/empty-cwd-bare"
mkdir -p "$EMPTY_DIR3"

check_bare_plugin_fallback() {
  local stdout
  set +e
  stdout="$(cd "$EMPTY_DIR3" && HOME="$PLUGIN_HOME2" "$MINION_RUN" --file "$MINFILE_BARE" 2>/dev/null)"
  local rc=$?
  set -e
  [ "$rc" = "0" ] || { echo "        rc=$rc"; return 1; }
  echo "$stdout" | grep -qF "### bare-skill" || return 1
}
check "claude-skills bare name falls through to plugins cache" check_bare_plugin_fallback

# 2e. Absolute path resolution — path must be inside an allowed root.
# We place the skill inside a fake $HOME/.claude/skills/ directory so
# the confinement check accepts it.
ABS_HOME_DIR="$MOCK_DIR/abs-home"
mkdir -p "$ABS_HOME_DIR/.claude/skills/abs-skill-dir"
ABS_SKILL_PATH="$ABS_HOME_DIR/.claude/skills/abs-skill-dir/SKILL.md"
create_skill_file "$ABS_SKILL_PATH"
MINFILE_ABS="$(create_minion_file "---
provider: openai
model: gpt-4
claude-skills:
  - $ABS_SKILL_PATH
---
Body text")"

EMPTY_DIR_ABS="$MOCK_DIR/empty-cwd-abs"
mkdir -p "$EMPTY_DIR_ABS"

check_absolute_path() {
  local stdout
  set +e
  stdout="$(cd "$EMPTY_DIR_ABS" && HOME="$ABS_HOME_DIR" "$MINION_RUN" --file "$MINFILE_ABS" 2>/dev/null)"
  local rc=$?
  set -e
  [ "$rc" = "0" ] || return 1
  # Header should use the directory basename of the absolute path
  echo "$stdout" | grep -qF "### abs-skill-dir" || return 1
}
check "claude-skills resolves absolute path" check_absolute_path

# 2f. Missing skill: actionable error to stderr, exit 1
MINFILE_MISSING="$(create_minion_file "---
provider: openai
model: gpt-4
claude-skills:
  - definitely-not-found-$RANDOM
---
Body text")"

EMPTY_DIR4="$MOCK_DIR/empty-cwd-missing"
mkdir -p "$EMPTY_DIR4"

run_and_check \
  "missing claude-skill prints actionable error and exits 1" \
  1 \
  "" \
  "could not resolve claude-skill" \
  -- env HOME="$EMPTY_DIR4" bash -c "cd '$EMPTY_DIR4' && '$MINION_RUN' --file '$MINFILE_MISSING'"

# 2g. Path traversal: invalid name '..' rejected
MINFILE_TRAVERSAL="$(create_minion_file "---
provider: openai
model: gpt-4
claude-skills:
  - ../escape
---
Body text")"

run_and_check \
  "invalid claude-skill name '../escape' rejected" \
  1 \
  "" \
  "invalid claude-skill name" \
  -- "$MINION_RUN" --file "$MINFILE_TRAVERSAL"

# 2h. Path traversal in plugin:skill
MINFILE_TRAVERSAL2="$(create_minion_file "---
provider: openai
model: gpt-4
claude-skills:
  - good-plugin:../escape
---
Body text")"

run_and_check \
  "invalid plugin:skill name with traversal rejected" \
  1 \
  "" \
  "invalid claude-skill name" \
  -- "$MINION_RUN" --file "$MINFILE_TRAVERSAL2"

# ============================================================
# Phase 3: Tool name transformations
# ============================================================
echo ""
echo "-- Tool name transformations --"

TRANSFORM_HOME="$MOCK_DIR/transform-home"
TRANSFORM_SKILL="$TRANSFORM_HOME/.claude/skills/transform-skill/SKILL.md"
mkdir -p "$(dirname "$TRANSFORM_SKILL")"
cat > "$TRANSFORM_SKILL" <<'EOF'
---
name: transform-skill
description: tests the transformations
---
# Transform Tests

Use the Read tool to read files.
The Edit tool modifies files in place.
The Write tool creates files.
The Bash tool runs shell.
The Glob tool finds files.
The Grep tool searches text.

Inline refs: `Read`, `Edit`, `Write`, `Bash`, `Glob`, `Grep`, `Task`.

Use the Task tool for delegation.
Use Task tool with subagent_type=foo.
Pass subagent_type as parameter.

Skill(skill="reviewer") to start.
Skill(skill="other-thing", arg=1) is also valid.

Ask via AskUserQuestion when uncertain.
The plugin lives at ${CLAUDE_PLUGIN_ROOT}/foo.

Each subagent runs independently.
EOF

MINFILE_TRANSFORM="$(create_minion_file "---
provider: openai
model: gpt-4
claude-skills:
  - transform-skill
---
Body text")"

EMPTY_DIR5="$MOCK_DIR/empty-cwd-transform"
mkdir -p "$EMPTY_DIR5"

check_transformations() {
  local stdout
  set +e
  stdout="$(cd "$EMPTY_DIR5" && HOME="$TRANSFORM_HOME" "$MINION_RUN" --file "$MINFILE_TRANSFORM" 2>/dev/null)"
  local rc=$?
  set -e
  [ "$rc" = "0" ] || { echo "        rc=$rc"; return 1; }

  local all_pass=true
  local patterns=(
    "Use the read tool to read files."
    "The edit tool modifies files in place."
    "The write tool creates files."
    "The bash tool runs shell."
    "The find tool finds files."
    "The grep tool searches text."
    "Inline refs: \`read\`, \`edit\`, \`write\`, \`bash\`, \`find\`, \`grep\`, \`groundwork_agent\`."
    "Use the groundwork_agent tool for delegation."
    "Use groundwork_agent tool with agent=foo."
    "Pass agent as parameter."
    "the reviewer workflow to start."
    "the other-thing workflow is also valid."
    "Ask via Ask the user when uncertain."
    "The plugin lives at the plugin directory/foo."
    "Each sub-task runs independently."
  )
  for pat in "${patterns[@]}"; do
    if ! echo "$stdout" | grep -qF -- "$pat"; then
      echo "        missing: '$pat'"
      all_pass=false
    fi
  done

  # Make sure no untransformed forms remain (anchor on backticks to avoid false positives)
  local antipatterns=(
    "\`Read\`"
    "\`Edit\`"
    "\`Write\`"
    "\`Bash\`"
    "\`Glob\`"
    "\`Grep\`"
    "\`Task\`"
    "AskUserQuestion"
    "\${CLAUDE_PLUGIN_ROOT}"
    "Skill(skill="
  )
  for pat in "${antipatterns[@]}"; do
    if echo "$stdout" | grep -qF -- "$pat"; then
      echo "        untransformed: '$pat'"
      all_pass=false
    fi
  done

  $all_pass
}
check "tool name transformations applied to skill body" check_transformations

# Verify frontmatter is stripped (the skill name from FM should not appear as YAML)
check_frontmatter_stripped() {
  local stdout
  set +e
  stdout="$(cd "$EMPTY_DIR5" && HOME="$TRANSFORM_HOME" "$MINION_RUN" --file "$MINFILE_TRANSFORM" 2>/dev/null)"
  local rc=$?
  set -e
  [ "$rc" = "0" ] || return 1
  # Frontmatter description line should NOT appear
  echo "$stdout" | grep -qF "tests the transformations" && return 1
  return 0
}
check "frontmatter is stripped from skill body" check_frontmatter_stripped

# ============================================================
# Phase 4: Prompt embedding (skills before body)
# ============================================================
echo ""
echo "-- Prompt embedding --"

ORDER_HOME="$MOCK_DIR/order-home"
mkdir -p "$ORDER_HOME/.claude/skills/order-skill"
cat > "$ORDER_HOME/.claude/skills/order-skill/SKILL.md" <<'EOF'
---
name: order-skill
description: ordering test
---
SKILL_BODY_MARKER
EOF

MINFILE_ORDER="$(create_minion_file "---
provider: openai
model: gpt-4
claude-skills:
  - order-skill
---
MINION_BODY_MARKER")"

EMPTY_DIR6="$MOCK_DIR/empty-cwd-order"
mkdir -p "$EMPTY_DIR6"

check_skills_before_body() {
  local stdout
  set +e
  stdout="$(cd "$EMPTY_DIR6" && HOME="$ORDER_HOME" "$MINION_RUN" --file "$MINFILE_ORDER" 2>/dev/null)"
  local rc=$?
  set -e
  [ "$rc" = "0" ] || return 1

  # SKILL_BODY_MARKER must appear BEFORE MINION_BODY_MARKER
  local skill_pos body_pos
  skill_pos=$(echo "$stdout" | grep -bF "SKILL_BODY_MARKER" | head -1 | cut -d: -f1)
  body_pos=$(echo "$stdout" | grep -bF "MINION_BODY_MARKER" | head -1 | cut -d: -f1)
  [ -n "$skill_pos" ] || return 1
  [ -n "$body_pos" ] || return 1
  [ "$skill_pos" -lt "$body_pos" ] || return 1

  # Separator '---' should be present between skills and body
  echo "$stdout" | grep -qF -- "---" || return 1
}
check "claude-skills appear before minion body, separated by ---" check_skills_before_body

# ============================================================
# Phase 5: Inline overrides (file mode + inline flags)
# ============================================================
echo ""
echo "-- Inline overrides --"

MINFILE_OVERRIDE="$(create_minion_file "---
provider: filesys
model: filemodel
---
File body")"

# 5a. --provider override replaces file provider
run_and_check \
  "--provider override replaces file value" \
  0 \
  "--provider clidsys" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_OVERRIDE" --provider clidsys

# 5b. --model override
run_and_check \
  "--model override replaces file value" \
  0 \
  "--model clidsmodel" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_OVERRIDE" --model clidsmodel

# 5c. --file with --provider no longer fatal (regression of old conflict)
check_file_provider_no_conflict() {
  local stdout
  set +e
  stdout="$("$MINION_RUN" --file "$MINFILE_OVERRIDE" --provider override 2>/dev/null)"
  local rc=$?
  set -e
  [ "$rc" = "0" ]
}
check "--file with --provider no longer errors" check_file_provider_no_conflict

# 5d. --prompt override replaces body
run_and_check \
  "--prompt override replaces minion body" \
  0 \
  "OVERRIDE_PROMPT" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_OVERRIDE" --prompt "OVERRIDE_PROMPT"

check_stdout_absent \
  "--prompt override hides original file body" \
  "File body" \
  -- "$MINION_RUN" --file "$MINFILE_OVERRIDE" --prompt "OVERRIDE_PROMPT"

# 5e. --pi-skills inline list replaces frontmatter pi-skills entirely
MINFILE_PISKILLS_OVR="$(create_minion_file "---
provider: openai
model: gpt-4
pi-skills:
  - file-skill-1
  - file-skill-2
---
Body")"

run_and_check \
  "--pi-skills inline replaces file pi-skills (new value present)" \
  0 \
  "--skill cli-a --skill cli-b" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_PISKILLS_OVR" --pi-skills cli-a,cli-b

check_stdout_absent \
  "--pi-skills inline replaces file pi-skills (file values absent)" \
  "file-skill-1" \
  -- "$MINION_RUN" --file "$MINFILE_PISKILLS_OVR" --pi-skills cli-a,cli-b

# 5f. --extensions inline list
MINFILE_EXT_OVR="$(create_minion_file "---
provider: openai
model: gpt-4
extensions:
  - ext-file-1
---
Body")"

run_and_check \
  "--extensions inline replaces file extensions (new value present)" \
  0 \
  "-e ext-cli-1 -e ext-cli-2" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_EXT_OVR" --extensions ext-cli-1,ext-cli-2

check_stdout_absent \
  "--extensions inline replaces file extensions (file values absent)" \
  "ext-file-1" \
  -- "$MINION_RUN" --file "$MINFILE_EXT_OVR" --extensions ext-cli-1,ext-cli-2

# 5g. --claude-skills inline replaces frontmatter claude-skills entirely
INLINE_SKILLS_HOME="$MOCK_DIR/inline-skills-home"
mkdir -p "$INLINE_SKILLS_HOME/.claude/skills/cli-only/"
cat > "$INLINE_SKILLS_HOME/.claude/skills/cli-only/SKILL.md" <<'EOF'
---
name: cli-only
description: cli skill
---
CLI_ONLY_BODY
EOF
mkdir -p "$INLINE_SKILLS_HOME/.claude/skills/file-skill/"
cat > "$INLINE_SKILLS_HOME/.claude/skills/file-skill/SKILL.md" <<'EOF'
---
name: file-skill
description: file skill
---
FILE_SKILL_BODY
EOF

MINFILE_CSKILLS_OVR="$(create_minion_file "---
provider: openai
model: gpt-4
claude-skills:
  - file-skill
---
Body")"

EMPTY_DIR7="$MOCK_DIR/empty-cwd-cskills-ovr"
mkdir -p "$EMPTY_DIR7"

check_claude_skills_override() {
  local stdout
  set +e
  stdout="$(cd "$EMPTY_DIR7" && HOME="$INLINE_SKILLS_HOME" "$MINION_RUN" --file "$MINFILE_CSKILLS_OVR" --claude-skills cli-only 2>/dev/null)"
  local rc=$?
  set -e
  [ "$rc" = "0" ] || { echo "        rc=$rc"; return 1; }
  echo "$stdout" | grep -qF "CLI_ONLY_BODY" || { echo "        missing CLI_ONLY_BODY"; return 1; }
  echo "$stdout" | grep -qF "FILE_SKILL_BODY" && { echo "        unexpected FILE_SKILL_BODY"; return 1; }
  return 0
}
check "--claude-skills inline replaces file claude-skills" check_claude_skills_override

# 5h. --extra-input now permitted with inline mode flags (no longer a hard conflict)
run_and_check \
  "inline mode --provider/--model/--prompt + --extra-input works" \
  0 \
  "MOCK_ARGS:" \
  "" \
  -- "$MINION_RUN" --provider openai --model gpt-4 --prompt "Base" --extra-input "Extra"

# 5i. --thinking, --tools, --max-turns, --append-system-prompt overrides
run_and_check \
  "--thinking override applied" \
  0 \
  "--thinking high" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_OVERRIDE" --thinking high

run_and_check \
  "--tools override applied" \
  0 \
  "--tools bash" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_OVERRIDE" --tools bash

run_and_check \
  "--max-turns override applied" \
  0 \
  "--max-turns 7" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_OVERRIDE" --max-turns 7

run_and_check \
  "--append-system-prompt override applied" \
  0 \
  "--append-system-prompt SystemBit" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_OVERRIDE" --append-system-prompt SystemBit

# 5j. Boolean flags as overrides
run_and_check \
  "--no-tools boolean override applied" \
  0 \
  "--no-tools" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_OVERRIDE" --no-tools

run_and_check \
  "--no-session boolean override applied" \
  0 \
  "--no-session" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_OVERRIDE" --no-session

run_and_check \
  "--stream boolean override applied" \
  0 \
  "--stream" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_OVERRIDE" --stream

# ============================================================
# Phase 6: Pure inline mode with --claude-skills
# ============================================================
echo ""
echo "-- Pure inline mode with claude-skills --"

INLINE_HOME="$MOCK_DIR/inline-home"
mkdir -p "$INLINE_HOME/.claude/skills/inline-skill"
cat > "$INLINE_HOME/.claude/skills/inline-skill/SKILL.md" <<'EOF'
---
name: inline-skill
description: inline test
---
INLINE_SKILL_MARKER
EOF

EMPTY_DIR8="$MOCK_DIR/empty-cwd-inline"
mkdir -p "$EMPTY_DIR8"

check_inline_with_skills() {
  local stdout
  set +e
  stdout="$(cd "$EMPTY_DIR8" && HOME="$INLINE_HOME" "$MINION_RUN" \
    --provider openai --model gpt-4 --claude-skills inline-skill --prompt "USER_PROMPT" 2>/dev/null)"
  local rc=$?
  set -e
  [ "$rc" = "0" ] || { echo "        rc=$rc"; return 1; }
  echo "$stdout" | grep -qF "INLINE_SKILL_MARKER" || return 1
  echo "$stdout" | grep -qF "USER_PROMPT" || return 1
  echo "$stdout" | grep -qF "## Available Skills" || return 1
}
check "inline mode with --claude-skills loads skill before --prompt" check_inline_with_skills

# Inline mode with claude-skills but no --prompt or --extra-input still works
# (the skills themselves provide content)
check_inline_skills_only() {
  local stdout
  set +e
  stdout="$(cd "$EMPTY_DIR8" && HOME="$INLINE_HOME" "$MINION_RUN" \
    --provider openai --model gpt-4 --claude-skills inline-skill 2>/dev/null)"
  local rc=$?
  set -e
  [ "$rc" = "0" ] || return 1
  echo "$stdout" | grep -qF "INLINE_SKILL_MARKER" || return 1
}
check "inline mode with --claude-skills only (no --prompt) works" check_inline_skills_only

# Inline mode with no provider/model still fails
run_and_check \
  "inline mode missing provider+model exits 1" \
  1 \
  "" \
  "missing:" \
  -- "$MINION_RUN" --prompt "hi"

# Inline mode with provider+model but no prompt content fails
run_and_check \
  "inline mode missing prompt content exits 1" \
  1 \
  "" \
  "missing:" \
  -- "$MINION_RUN" --provider openai --model gpt-4

# ============================================================
# Phase 7: Regression — existing extensions list still works
# ============================================================
echo ""
echo "-- Regression --"

MINFILE_REGRESSION="$(create_minion_file "---
provider: openai
model: gpt-4
extensions:
  - ext-a
  - ext-b
---
Body")"

run_and_check \
  "extensions still parsed (regression)" \
  0 \
  "-e ext-a -e ext-b" \
  "" \
  -- "$MINION_RUN" --file "$MINFILE_REGRESSION"

# ============================================================
# Phase 8: Security — -- sentinel before prompt (Finding 1)
# ============================================================
echo ""
echo "-- -- sentinel before composed prompt --"

# 8a. A prompt starting with --no-tools is passed as literal text, not a flag.
# The fake-pi mock echoes all args; without --, pi would interpret --no-tools as a flag.
# With --, it appears as a literal argument in the echo output.
MINFILE_SENTINEL="$(create_minion_file "---
provider: openai
model: gpt-4
---
--no-tools is the prompt body")"

check_sentinel_literal_prompt() {
  local stdout
  set +e
  stdout="$("$MINION_RUN" --file "$MINFILE_SENTINEL" 2>/dev/null)"
  local rc=$?
  set -e
  [ "$rc" = "0" ] || { echo "        rc=$rc"; return 1; }
  # The -- sentinel must appear immediately before the prompt argument in the args list.
  # The mock echoes: "MOCK_ARGS: ...flags... -- --no-tools is the prompt body"
  # We use grep -F with a literal string; use grep -e to avoid -- being parsed as options.
  if ! echo "$stdout" | grep -qFe "-- --no-tools is the prompt body"; then
    echo "        stdout does not contain '-- --no-tools is the prompt body'"
    echo "        stdout was: $stdout"
    return 1
  fi
}
check "prompt starting with --no-tools is preceded by -- sentinel" check_sentinel_literal_prompt

# ============================================================
# Phase 9: Security — absolute-path confinement (Finding 2)
# ============================================================
echo ""
echo "-- absolute-path confinement --"

# 9a. Absolute path inside $HOME/.claude/skills/ is accepted.
CONFINEMENT_HOME="$MOCK_DIR/confinement-home"
mkdir -p "$CONFINEMENT_HOME/.claude/skills/allowed-skill"
cat > "$CONFINEMENT_HOME/.claude/skills/allowed-skill/SKILL.md" <<'EOF'
---
name: allowed-skill
description: confinement test
---
ALLOWED_SKILL_BODY
EOF

ABS_ALLOWED_PATH="$CONFINEMENT_HOME/.claude/skills/allowed-skill/SKILL.md"
MINFILE_ABS_ALLOWED="$(create_minion_file "---
provider: openai
model: gpt-4
claude-skills:
  - $ABS_ALLOWED_PATH
---
Body")"

EMPTY_DIR_CONF="$MOCK_DIR/empty-cwd-conf"
mkdir -p "$EMPTY_DIR_CONF"

check_abs_allowed() {
  local stdout
  set +e
  stdout="$(cd "$EMPTY_DIR_CONF" && HOME="$CONFINEMENT_HOME" "$MINION_RUN" --file "$MINFILE_ABS_ALLOWED" 2>/dev/null)"
  local rc=$?
  set -e
  [ "$rc" = "0" ] || { echo "        rc=$rc"; return 1; }
  echo "$stdout" | grep -qF "ALLOWED_SKILL_BODY" || { echo "        missing ALLOWED_SKILL_BODY"; return 1; }
}
check "absolute path inside HOME/.claude/skills/ is accepted" check_abs_allowed

# 9b. Absolute path OUTSIDE the allowlist (e.g., /tmp) is rejected with error message.
TMP_SKILL_DIR="$MOCK_DIR/tmp-outside-skill"
mkdir -p "$TMP_SKILL_DIR"
cat > "$TMP_SKILL_DIR/SKILL.md" <<'EOF'
---
name: evil-skill
description: should not be loaded
---
EVIL_BODY
EOF

ABS_OUTSIDE_PATH="$TMP_SKILL_DIR/SKILL.md"
MINFILE_ABS_OUTSIDE="$(create_minion_file "---
provider: openai
model: gpt-4
claude-skills:
  - $ABS_OUTSIDE_PATH
---
Body")"

run_and_check \
  "absolute path outside allowlist is rejected with error" \
  1 \
  "" \
  "absolute path is outside allowed directories" \
  -- env HOME="$CONFINEMENT_HOME" "$MINION_RUN" --file "$MINFILE_ABS_OUTSIDE"

# 9c. Verify the evil body is NOT in stdout even when rejected.
check_stdout_absent \
  "rejected absolute path does not leak file contents" \
  "EVIL_BODY" \
  -- env HOME="$CONFINEMENT_HOME" "$MINION_RUN" --file "$MINFILE_ABS_OUTSIDE"

# ============================================================
# Phase 10: Security — strip_frontmatter pre-content leak (Finding 3)
# ============================================================
echo ""
echo "-- strip_frontmatter pre-frontmatter content --"

# 10a. A skill file with content BEFORE the first '---' must NOT leak that content.
PRE_FM_HOME="$MOCK_DIR/pre-fm-home"
mkdir -p "$PRE_FM_HOME/.claude/skills/pre-fm-skill"
cat > "$PRE_FM_HOME/.claude/skills/pre-fm-skill/SKILL.md" <<'EOF'
THIS_LINE_BEFORE_FRONTMATTER
---
name: pre-fm-skill
description: pre-frontmatter test
---
# Skill Body

SKILL_BODY_CONTENT
EOF

MINFILE_PRE_FM="$(create_minion_file "---
provider: openai
model: gpt-4
claude-skills:
  - pre-fm-skill
---
Body")"

EMPTY_DIR_PFM="$MOCK_DIR/empty-cwd-pfm"
mkdir -p "$EMPTY_DIR_PFM"

check_stdout_absent \
  "pre-frontmatter content is not leaked into prompt" \
  "THIS_LINE_BEFORE_FRONTMATTER" \
  -- bash -c "cd '$EMPTY_DIR_PFM' && HOME='$PRE_FM_HOME' '$MINION_RUN' --file '$MINFILE_PRE_FM'"

# 10b. A skill file with NO frontmatter at all must not dump all content as pre-content.
NO_FM_HOME="$MOCK_DIR/no-fm-home"
mkdir -p "$NO_FM_HOME/.claude/skills/no-fm-skill"
cat > "$NO_FM_HOME/.claude/skills/no-fm-skill/SKILL.md" <<'EOF'
NO_FRONTMATTER_CONTENT
This file has no --- delimiters at all.
EOF

MINFILE_NO_FM="$(create_minion_file "---
provider: openai
model: gpt-4
claude-skills:
  - no-fm-skill
---
Body")"

EMPTY_DIR_NFM="$MOCK_DIR/empty-cwd-nfm"
mkdir -p "$EMPTY_DIR_NFM"

check_stdout_absent \
  "skill file with no frontmatter does not dump content" \
  "NO_FRONTMATTER_CONTENT" \
  -- bash -c "cd '$EMPTY_DIR_NFM' && HOME='$NO_FM_HOME' '$MINION_RUN' --file '$MINFILE_NO_FM'"

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  echo "TESTS FAILED"
  exit 1
else
  echo "ALL TESTS PASSED"
  exit 0
fi
