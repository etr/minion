### TASK-009: README and marketplace distribution

**Milestone:** M4 - Polish & Distribution
**Component:** Plugin root, groundwork-marketplace
**Estimate:** S

**Goal:**
Prepare the plugin for distribution via the groundwork marketplace.

**Action Items:**
- [x] Write README.md with: overview, installation command, usage for both modes, minion file format reference, frontmatter field table, examples
- [x] Add LICENSE file (MIT)
- [ ] Add entry to `../claude-groundwork/groundwork-marketplace/README.md` available plugins table
- [ ] Verify `claude plugin install minion@groundwork-marketplace` installs correctly
- [ ] Verify `/minion` is available after marketplace install

**Dependencies:**
- Blocked by: TASK-008
- Blocks: None

**Acceptance Criteria:**
- README covers both invocation modes with examples
- README includes minion file format with all frontmatter fields
- Plugin installs from marketplace successfully
- Marketplace README lists the minion plugin with description
- LICENSE file present

**Related Requirements:** PRD-MIN-REQ-004, PRD-MIN-REQ-006, PRD-MIN-REQ-008, PRD-MIN-REQ-013
**Related Decisions:** DR-001

**Status:** In Progress
