### TASK-006: Frontmatter parsing and Pi flag mapping

**Milestone:** M3 - Minion File Support
**Component:** lib/minion-run.sh
**Estimate:** M

**Goal:**
Parse YAML frontmatter from minion files and map all supported fields to Pi CLI flags.

**Action Items:**
- [x] Add `--file <path>` mode to `minion-run.sh`
- [x] Extract YAML frontmatter between first and second `---` delimiters using sed/awk
- [x] Parse string fields: provider, model, thinking, tools, max-turns, append-system-prompt
- [x] Parse boolean fields: no-tools, no-session, stream (emit bare `--flag` when value is `true`)
- [x] Parse list fields: extensions (`- item` → `-e item` per entry), skills (`- item` → `--skill item` per entry)
- [x] Validate required fields (provider, model); report missing field names and exit non-zero
- [x] Extract markdown body (everything after second `---`) as base prompt
- [x] Construct full Pi CLI command from all parsed fields + base prompt

**Dependencies:**
- Blocked by: TASK-003
- Blocks: TASK-007

**Acceptance Criteria:**
- Minion file with all field types parses correctly into Pi CLI flags
- Boolean `true` emits `--no-tools`; `false` or absent omits it
- List with 3 extensions emits `-e ext1 -e ext2 -e ext3`
- Missing `provider` exits non-zero with "missing: provider"
- Markdown body after frontmatter is captured as base prompt
- Constructed command is syntactically valid Pi CLI invocation

**Related Requirements:** PRD-MIN-REQ-008, PRD-MIN-REQ-009, PRD-MIN-REQ-010, PRD-MIN-REQ-013
**Related Decisions:** DR-003

**Status:** Complete
