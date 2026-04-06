# Minor TODOs

Accumulated unexecuted findings from validation runs. Check items off as addressed.

---

## Run: 2026-04-06 | Validation loop: bash-first hook hardening (5 iterations)

1. [ ] `major` **code-simplifier** | `lib/auto-minion-hook.sh:62` | flag-argument: handle_dispatch_result takes boolean string 'unavail_on_exit3' as 5th arg — split or pass pre-computed attribution string
2. [ ] `major` **code-simplifier** | `lib/auto-minion-hook.sh:82` | duplication: NEEDS_NATIVE_HANDLING block duplicates SHOW_ROUTING branch pattern; attribution block below handles it more cleanly -- Build routing prefix into variable, call output_context once
3. [ ] `major` **architecture** | `specs/architecture.md:473` | adr-stale: DR-005 consequences still reference NEEDS_INLINE_CLASSIFICATION and say skill handles inherit classification; hook now handles via claude -p -- Update DR-005 consequences
4. [ ] `minor` **security** | `lib/auto-minion-hook.sh:213` | dead-code: CATEGORIES variable extracted from dry-run but never used -- Remove or document intended use
5. [ ] `minor` **code-simplifier** | `lib/auto-minion-hook.sh:73` | echo-vs-printf: Header validation and body extraction (lines 73-79) use echo instead of printf '%s' used elsewhere -- Replace with printf for consistency
6. [ ] `minor` **code-simplifier** | `test/test-auto-minion-hook.sh:194` | naming: with_mock_auto_dispatch reads like setup function but returns a path -- Rename to make_mock_dispatch_dir
7. [ ] `minor` **code-quality** | `test/test-auto-minion-hook.sh:596` | heredoc-fragility: Sentinel mock heredoc embeds path via single-quote workaround; path with single quote would break -- Use printf or double-quoted heredoc
8. [ ] `minor` **architecture** | `specs/architecture.md` | doc-stale: Section 4.7.5 says "parses headers in a while read loop" but implementation uses sed -- Update to reflect sed-based parsing
9. [ ] `minor` **architecture** | `lib/auto-minion-hook.sh:24` | undocumented: AUTO_DISPATCH_DIR env var test seam not in architecture doc -- Add note to section 4.7.5
10. [ ] `minor` **housekeeper** | `CLAUDE.md:90` | doc-stale: TASK-014 roadmap entry still says 'hooks/auto-minion.md pre-message hook' -- Update to reflect bash-first hook
11. [ ] `minor` **spec-alignment** | `lib/auto-dispatch.sh:93` | char-set-mismatch: parse_field validates ^[a-zA-Z0-9_-]+$ (no dot) vs validate_identifier ^[a-zA-Z0-9._-]+$ -- Align or document difference
12. [ ] `minor` **spec-alignment** | `lib/auto-minion-hook.sh:85` | default-value: SHOW_ROUTING defaults to true but EARS PRD-AUTO-REQ-016 implies opt-in -- Document or change default
13. [ ] `minor` **performance** | `lib/auto-minion-hook.sh:113` | multi-pass: Three separate sed invocations parse same dry-run output -- Consolidate into single while-read loop
14. [ ] `minor` **security** | `lib/auto-dispatch.sh:313` | portability: base64 fallback without -w0 may produce line-wrapped output on macOS -- Use `base64 | tr -d '\n'` as fallback
15. [ ] `minor` **test-quality** | `test/test-auto-dispatch.sh:434` | comment-mismatch: Comment conflates non-dry-run and dry-run under single 'Finding 5' label -- Split comment

---

## Run: 2026-04-05 | Auto-minion hook refactor (bash-first pre-message hook)

1. [ ] `major` **security** | `lib/auto-dispatch.sh:277` | template-injection: compose_dispatcher_prompt substitutes USER_PROMPT via bash parameter expansion; if prompt contains `{{categories}}` it won't re-trigger (categories substituted first), but the substitution order is undocumented and fragile for future placeholders -- Neutralize `{{` sequences in USER_PROMPT before substitution or document substitution order
2. [ ] `major` **security** | `lib/auto-dispatch.sh:429` | path-traversal: validate_identifier allows `.` character; a minion name of `..` passes validation and could produce path traversal in `.claude/minions/../..` -- Reject identifiers matching `^\.+$` or containing `..`
3. [x] `major` **architecture** | `specs/architecture.md:57` | diagram-stale: Section 3.1 high-level diagram shows hook→auto-minion skill→auto-dispatch, but actual flow is hook→auto-minion-hook.sh→auto-dispatch -- Update diagram
4. [x] `major` **architecture** | `specs/architecture.md:249` | interface-stale: Section 4.7 says "Dispatches to: auto-minion skill" but hook now dispatches to lib/auto-minion-hook.sh -- Rewrite to reflect thin-hook design
5. [ ] `minor` **code-quality** | `lib/auto-dispatch.sh:299` | exit-code-inconsistency: --category unknown exits 1 instead of 2 (other bad-input paths use exit 2) -- Change to exit 2
6. [ ] `minor` **code-quality** | `lib/auto-minion-hook.sh:84` | cleanup-inconsistency: inherit block manually rm's temp file; external block uses trap -- Unify on trap pattern
7. [ ] `minor` **code-simplifier** | `lib/auto-dispatch.sh:257` | naming: is_valid_category() also accepts 'default' sentinel — name is misleading -- Rename to is_valid_route_target()
8. [x] `minor` **code-simplifier** | `hooks/auto-minion.md:113` | scope-clarity: PROMPT_FILE scope not documented — OBSOLETE: hooks/auto-minion.md deleted in bash-first refactor
9. [x] `minor` **code-simplifier** | `hooks/auto-minion.md:96` | doc-mismatch: DISPATCHED section order — OBSOLETE: hooks/auto-minion.md deleted in bash-first refactor
10. [x] `minor` **security** | `hooks/auto-minion.md:119` | trust-boundary: IMPORTANT note — OBSOLETE: hooks/auto-minion.md deleted in bash-first refactor
11. [ ] `minor` **security** | `lib/auto-dispatch.sh:419` | info-disclosure: HOME path in minion-not-found stderr error -- Suppress or make debug-only
12. [ ] `minor` **architecture** | `specs/architecture.md:278` | doc-imprecision: SHOW_ROUTING note says "emitted after every STATUS" but not emitted for DISABLED/BYPASS/ERROR -- Qualify the note
13. [x] `minor` **architecture** | `hooks/auto-minion.md:5` | unused-tool: "Skill" in allowed-tools — OBSOLETE: hooks/auto-minion.md deleted in bash-first refactor
14. [ ] `minor` **test-quality** | `test/test-auto-minion-hook.sh:100` | dead-code: run_hook_with_home defined but never called -- Use it or delete it
15. [ ] `minor` **test-quality** | `test/test-auto-minion-hook.sh:276` | logic-in-test: HOME fallback test uses inline if/else instead of run_and_check -- Refactor to use helper
16. [ ] `minor` **test-quality** | `test/test-auto-minion-hook.sh:546` | naming: _CLEANUP_DIRS holds file paths too -- Rename to _CLEANUP_PATHS
17. [ ] `minor` **test-quality** | `test/test-auto-minion-hook.sh` | missing-test: No test for STATUS:NATIVE with FALLBACK:dispatcher_failed
18. [ ] `minor` **test-quality** | `test/test-auto-dispatch.sh` | missing-test: No test for --category 'default' via direct --category flag
19. [x] `minor` **housekeeper** | `specs/tasks/M5-auto-minion-mode/TASK-014.md:12` | deliverables-incomplete: Missing lib/auto-minion-hook.sh and test/test-auto-minion-hook.sh -- Update deliverables list
20. [ ] `minor` **performance** | `lib/auto-dispatch.sh:267` | unnecessary-work: CATEGORY_LIST and DISPATCHER_PROMPT built even when --category bypasses dispatcher -- Move into else branch

---

## Run: 2026-04-05 | Milestone 5: Auto-Minion Mode (TASK-010 through TASK-015)

1. [ ] `major` **spec-alignment** | `lib/auto-dispatch.sh` | ears-requirement: PRD-AUTO-REQ-016 requires show-routing attribution but auto-dispatch.sh has no SHOW_ROUTING: header in output protocol; skill has no instruction for reading this field from config -- Add SHOW_ROUTING:true|false header to auto-dispatch.sh output and update SKILL.md Step 5c
2. [ ] `minor` **security** | `lib/auto-dispatch.sh:83` | injection: echo "$BODY" could misinterpret content starting with -n/-e/-E as flags -- Replace with printf '%s\n' "$BODY"
3. [ ] `minor` **security** | `lib/auto-dispatch.sh:270` | injection: {{prompt}} substitution inserts USER_PROMPT verbatim; user prompt containing {{categories}} could confuse dispatcher LLM (prompt injection, not shell injection) -- Strip or escape {{ and }} from USER_PROMPT before substitution
4. [ ] `minor` **code-simplifier** | `lib/auto-dispatch.sh:110` | code-structure: is_inherit() duplicates parse_field() sed extraction -- Implement as val="$(parse_field "$1")"; [ "$val" = "inherit" ]
5. [ ] `minor` **code-simplifier** | `lib/auto-dispatch.sh:311` | naming: VALID variable name too generic -- Rename to CATEGORY_RECOGNIZED
6. [ ] `minor` **code-simplifier** | `lib/auto-dispatch.sh:302` | code-structure: Dispatch failure condition could use named boolean -- Assign to dispatcher_failed variable
7. [ ] `minor` **performance** | `lib/auto-dispatch.sh:125` | algorithmic-complexity: validate_identifier uses echo|grep fork per call -- Replace with bash [[ "$val" =~ ^[a-zA-Z0-9._-]+$ ]]
8. [ ] `minor` **performance** | `lib/auto-dispatch.sh:225` | algorithmic-complexity: Two separate validation loops over CAT_NAMES -- Merge into single pass
9. [ ] `minor` **code-simplifier** | `lib/auto-dispatch.sh:367` | code-structure: Nested if [ -n "$MINION_FILE" ] check redundant after resolution block -- Remove wrapper, call minion-run.sh directly
10. [ ] `minor` **code-simplifier** | `lib/auto-dispatch.sh:178` | naming: local_val/local_key prefix inconsistent with rest of script -- Rename to cat_val/field_key
11. [ ] `minor` **code-simplifier** | `lib/auto-dispatch.sh:423` | code-structure: Bare echo "" to stderr before fallback error message -- Remove or fold into error message
12. [ ] `minor` **code-quality** | `lib/auto-dispatch.sh:401` | error-handling: FALLBACK_REASON not set for missing-minion fallback path -- Set FALLBACK_REASON="minion_not_found" before default fallback
13. [ ] `minor` **code-quality** | `lib/auto-dispatch.sh:255` | code-readability: Inherit-dispatcher block mixes exit points; NEEDS_INLINE_CLASSIFICATION intent unclear without reading skill -- Add comment explaining output is consumed by skill layer
14. [ ] `minor` **spec-alignment** | `lib/auto-dispatch.sh:202` | specification-gap: minion: field in category config undocumented in specs/product_specs.md and examples/auto.md -- Document or confirm intentional scope
15. [ ] `minor` **architecture** | `skills/auto-minion/SKILL.md:209` | pattern-violation: Step 5d references --category flag that doesn't exist in auto-dispatch.sh -- Remove --category reference, keep only the minion-run.sh direct invocation alternative
16. [ ] `minor` **architecture** | `hooks/auto-minion.md:52` | interface-contract: Hook uses "Auto-minion dispatch" (capital A) but skill pattern-matches "auto-minion dispatch" (lowercase) -- Normalize casing
17. [ ] `minor` **architecture** | `commands/minion/COMMAND.md:36` | interface-contract: Command uses "Auto-minion subcommand" (capital A) vs skill expects lowercase -- Normalize casing
18. [ ] `minor` **architecture** | `.claude-plugin/plugin.json` | adr-violation: plugin.json doesn't reference hooks/auto-minion.md hook -- Verify if auto-discovery applies; if not, add hook entry
19. [ ] `minor` **housekeeper** | `specs/architecture.md:4` | spec-not-updated: Last updated date 2026-04-02 despite DR-005/DR-006 added 2026-04-05 -- Bump to 2026-04-05
20. [ ] `minor` **housekeeper** | `specs/product_specs.md:4` | spec-not-updated: Last updated date 2026-04-02 despite section 3.2 added -- Bump to 2026-04-05
21. [ ] `minor` **test-quality** | `test/test-auto-dispatch.sh:17` | naming: _CLEANUP_DIRS holds both dirs and files; name/comment says "dirs" -- Rename to _CLEANUP_PATHS
22. [ ] `minor` **test-quality** | `test/test-auto-dispatch.sh:667` | excessive-setup: Redundant rm -f after _CLEANUP_DIRS registration -- Remove manual rm -f or remove _CLEANUP_DIRS registration; pick one strategy
23. [ ] `minor` **test-quality** | `test/test-auto-dispatch.sh:719` | excessive-setup: MINIONRUN_CALL_FILE allocated but never read in site-2 block -- Remove unused variable
24. [ ] `minor` **test-quality** | `test/test-auto-dispatch.sh:347` | multiple-concerns: Four separate subprocess invocations for same routing scenario -- Capture output once and grep multiple patterns
25. [ ] `minor` **test-quality** | `test/test-auto-dispatch.sh:635` | naming: _minion_site1/site2/site3 use opaque positional names -- Rename to describe behavior (e.g., _mock_minionrun_record_args, _mock_minionrun_always_fail)
26. [ ] `minor` **test-quality** | `test/test-auto-dispatch.sh` | missing-test: No test for category description containing embedded newlines (PRD-AUTO-REQ-014 newline stripping) -- Add fixture with newline in description
27. [ ] `minor` **spec-alignment** | `hooks/auto-minion.md` | specification-gap: Bypass conditions only check '/' prefix and empty messages; system messages not mentioned -- Document bypass rationale
28. [ ] `minor` **performance** | `skills/auto-minion/SKILL.md:100` | missing-caching: Steps 2c and 2e each invoke auto-dispatch.sh --dry-run separately for same config -- Run once, capture, reuse

---

## Run: 2026-04-04 | TASK-009: README and marketplace distribution

1. [ ] `major` **spec-alignment** | `(external repo)` | action-item: Marketplace README entry, install verification, and `/minion` availability check deferred — minion repo has no GitHub remote yet. Complete when `etr/minion` is published.
2. [ ] `minor` **security** | `README.md:19` | insecure-design: Pi CLI URL has no integrity verification guidance (checksum/signature) -- Add verification note if Pi publishes checksums
3. [ ] `minor` **security** | `README.md:108` | sensitive-data: append-system-prompt field docs lack warning about secrets in minion files committed to VCS -- Add note to avoid secrets in frontmatter
4. [ ] `minor` **security** | `test/test-readme-and-license.sh:10` | input-validation: ROOT variable `cd` missing `&&`; if cd fails, pwd returns wrong directory silently -- Use `cd "$SCRIPT_DIR/.." && pwd`
5. [ ] `minor` **code-simplifier** | `test/test-readme-and-license.sh:15` | naming: check() discards stderr; failures give no diagnostic output -- Consider verbose flag or stderr capture on failure
6. [ ] `minor` **code-simplifier** | `test/test-readme-and-license.sh:96` | code-structure: `grep -qw` for common words (stream, tools, model) could false-positive match prose -- Use backtick-delimited pattern `\`field\``
7. [ ] `minor` **code-quality** | `test/test-readme-and-license.sh:7` | test-coverage: `set -uo pipefail` missing `-e`; intentional but undocumented -- Add comment explaining why
8. [ ] `minor` **code-quality** | `README.md:19` | readability: Pi CLI URL appears twice in Prerequisites section (link + bold URL) -- Remove duplicate
9. [ ] `minor` **code-quality** | `README.md:99` | readability: Required=Yes fields not visually distinct in frontmatter table -- Bold the Yes entries
10. [ ] `minor` **architecture** | `README.md:42` | interface-contract: Model name `claude-sonnet-4-20250514` unverified against Pi CLI docs -- Verify or use placeholder
11. [ ] `minor` **spec-alignment** | `README.md:102` | specification-gap: `tools` field type ambiguity (string vs list) -- Verify against Pi CLI `--tools` signature
12. [ ] `minor` **test-quality** | `test/test-readme-and-license.sh:134` | missing-test: No check for error behavior documentation (not-found paths) -- Add grep for error UX content
13. [ ] `minor` **test-quality** | `test/test-readme-and-license.sh:15` | naming-convention: Check descriptions mix question-like and assertion-like styles -- Standardize
14. [ ] `minor` **test-quality** | `test/test-readme-and-license.sh:87` | excessive-setup: Redundant provider/model re-checks after loop already verified them -- Remove or document intent
15. [ ] `minor` **code-simplifier** | `test/test-readme-and-license.sh:47` | code-structure: bash -c wrapper for line-count inconsistent with direct check() style -- Extract to variable first

---

## Run: 2026-04-04 | TASK-008: Example minion files and error UX

1. [ ] `major` **code-quality** | `test/test-examples-and-errors.sh:298` | test-coverage: --extra-input happy path (valid file + extra input, prompt composition verified) not tested -- Add capture_scenario with --file + --extra-input and assert extra text in mock Pi output
2. [ ] `major` **code-simplifier** | `test/test-examples-and-errors.sh:152` | code-structure: Phase 1 runs eight separate Python one-liners that each re-open and re-split the same example files; consolidate into two check calls (one per file) -- Create check_example_frontmatter helper or single Python block per file
3. [ ] `minor` **security** | `test/test-examples-and-errors.sh:118` | injection: check_skill_section Python interpolation fragile for assertion values containing single quotes -- Pass assertion via environment variable
4. [ ] `minor` **security** | `skills/delegate-to-minion/SKILL.md:33` | sensitive-data: curl-pipe-bash install pattern preserved without integrity check (CWE-494, pre-existing) -- Reorder so inspect-first is recommended path
5. [ ] `minor` **code-quality** | `examples/code-explainer.md:1` | code-readability: model: gpt-4 is a legacy alias; gpt-4o is current default -- Update or add comment explaining intentional choice
6. [ ] `minor` **code-quality** | `skills/delegate-to-minion/SKILL.md:293` | code-elegance: Copy instructions show different example files per scope (security-reviewer for local, code-explainer for global) -- Use same file name for both or add note
7. [ ] `minor` **code-simplifier** | `test/test-examples-and-errors.sh:257` | naming: MINFILE_NOBOTH unclear; rename to MINFILE_NOFIELDS or MINFILE_MISSING_PROVIDER_AND_MODEL -- Rename for clarity
8. [ ] `minor` **code-simplifier** | `test/test-examples-and-errors.sh:50` | code-structure: actual_stdout/stderr/exit declared at top level far from capture_scenario -- Move declarations near capture_scenario or add comment
9. [ ] `minor` **code-simplifier** | `test/test-examples-and-errors.sh:99` | code-structure: Phase 1 Python snippets each re-open and re-split same file; could factor into helper -- Create check_example_frontmatter-style helper
10. [ ] `minor` **housekeeper** | `specs/tasks/_index.md:15` | task-status: M4 milestone summary row shows 'Not Started' but TASK-008 is 'In Progress' -- Update to 'In Progress'
11. [ ] `minor` **housekeeper** | `CLAUDE.md:53` | documentation-stale: Development Workflow only mentions validate-plugin-structure.sh; test-examples-and-errors.sh not listed -- Add new test file to workflow docs
12. [ ] `minor` **architecture** | `specs/architecture.md:193` | pattern-violation: Plugin structure tree omits test/ directory (pre-existing) -- Add test/ with all test files
13. [ ] `minor` **spec-alignment** | `test/test-examples-and-errors.sh` | acceptance-criteria: Install-declined error path (PRD-MIN-REQ-003) not testable via bash; SKILL.md section is correct -- Informational; structurally untestable
14. [ ] `minor` **performance** | `test/test-examples-and-errors.sh:279` | missing-caching: Several Python subprocess checks could be combined per scenario -- Consolidate per-scenario assertions

---

## Run: 2026-04-03 | TASK-007: Prompt composition and minion-file mode end-to-end

1. [ ] `minor` **security** | `lib/minion-run.sh:83` | input-validation: FILE_PATH passed to awk without `--` end-of-options marker; paths starting with `-` could be misinterpreted as awk flags -- Use `awk '...' -- "$FILE_PATH"`
2. [ ] `minor` **security** | `skills/delegate-to-minion/SKILL.md:258` | sensitive-data: Pi stderr presented verbatim on failure may contain credential hints or internal endpoint details -- Add caveat to redact or warn about sharing error output
3. [ ] `minor` **test-quality** | `test/test-prompt-composition.sh:248` | implementation-coupling: Phase 8 structural checks grep for literal strings in SKILL.md/COMMAND.md; fragile to wording changes -- Consider replacing with behavioral assertions or documenting as lint-style checks
4. [ ] `minor` **test-quality** | `test/test-prompt-composition.sh:274` | missing-test: No test for extra-input containing embedded newlines or the separator sequence `\n\n` -- Add test with multi-line extra-input
5. [ ] `minor` **architecture** | `skills/delegate-to-minion/SKILL.md:197` | component-boundary: `test -f lib/minion-run.sh` guard is CWD-dependent; fragile deployment sanity check -- Document as deployment guard or move to script
6. [ ] `minor` **test-quality** | `test/test-prompt-composition.sh:119` | test-coverage: Composition test doesn't assert exact double-newline separator between body and extra-input -- Add pattern anchoring both parts with separator
7. [ ] `minor` **test-quality** | `test/test-prompt-composition.sh:185` | test-coverage: Empty extra-input test doesn't verify no trailing whitespace/newlines appended -- Add negative assertion for trailing separator
8. [ ] `minor` **code-quality** | `lib/minion-run.sh:154` | code-readability: COMPOSED variable name is generic; FINAL_PROMPT or PROMPT_ARG better communicates intent -- Rename throughout file-mode block
9. [ ] `minor` **code-quality** | `skills/delegate-to-minion/SKILL.md:210` | code-readability: MINION_EXTRA assignment in file-mode snippet missing single-quote wrapper shown for other variables -- Add single quotes for consistency
10. [ ] `minor` **test-quality** | `test/test-prompt-composition.sh:113` | algorithmic-complexity: create_minion_file uses $RANDOM for filenames; mktemp would guarantee uniqueness -- Use mktemp instead
11. [ ] `minor` **code-simplifier** | `lib/minion-run.sh:153` | code-structure: Redundant conditional in prompt composition; `COMPOSED="$BODY"` unconditionally is equivalent -- Simplify to flat assignment
12. [ ] `minor` **spec-alignment** | `test/test-prompt-composition.sh:240` | acceptance-criteria: PRD-MIN-REQ-014 (Pi output to context) verified only via structural grep, not behavioral test -- Inherent limitation of skill testing; documented
13. [ ] `minor` **test-quality** | `test/test-prompt-composition.sh:120` | missing-test: No test for empty body + non-empty extra-input composition path -- Add test with frontmatter-only minion file and --extra-input
14. [ ] `minor` **test-quality** | `test/test-frontmatter-parsing.sh:141` | missing-test: --file + --model mutual exclusivity untested (only --file + --provider covered) -- Add symmetrical test case
15. [ ] `minor` **test-quality** | `test/test-prompt-composition.sh:174` | test-coverage: Phase 4 test asserts only exit code 2, no stderr content -- Add minimal stderr assertion (e.g., non-empty)
16. [ ] `minor` **code-simplifier** | `test/test-prompt-composition.sh:249` | naming: One-off function definitions for structural checks could be inline check calls -- Inline grep into check() calls directly
17. [ ] `minor` **spec-alignment** | `lib/minion-run.sh:159` | specification-gap: Empty body + no extra input edge case unspecified in PRD; current behavior (omit prompt arg) is reasonable -- Document if PRD updated

---

## Run: 2026-04-03 | TASK-006: Frontmatter parsing and Pi flag mapping

1. [ ] `major` **code-quality** | `lib/minion-run.sh:81` | code-elegance: parse_field passes field name directly into sed regex without escaping; field names are hardcoded literals so safe today, but function interface doesn't enforce that -- Escape metacharacters or document constraint
2. [ ] `major` **code-simplifier** | `lib/minion-run.sh:88` | code-structure: validation block (missing required fields) duplicated between file and inline modes -- Extract shared `require_vars` or `die_missing` helper
3. [ ] `major` **code-simplifier** | `lib/minion-run.sh:133` | code-structure: list-flag loop pattern repeated for extensions and skills, differing only in field name and flag -- Extract `append_list_flags <field> <flag>` helper
4. [ ] `major` **code-quality** | `test/test-frontmatter-parsing.sh:1` | code-elegance: mock Pi setup and run_and_check helper duplicated verbatim across test-frontmatter-parsing.sh and test-minion-run.sh -- Extract into shared test/helpers.sh
5. [ ] `minor` **security** | `lib/minion-run.sh:84` | input-validation: parsed frontmatter field values passed directly to Pi CLI cmd array without sanitization; a value like '--inject-flag' would be forwarded verbatim -- Validate structured fields (max-turns numeric, thinking/tools allowlist)
6. [ ] `minor` **security** | `lib/minion-run.sh:66` | input-validation: FILE_PATH not restricted to any directory or file extension -- Consider .md extension check or document that callers scope paths
7. [ ] `minor` **security** | `lib/minion-run.sh:14` | error-handling: set -uo pipefail without -e; subshell failures in parse_field/parse_list could silently leave vars empty -- Add set -e or explicit exit checks
8. [ ] `minor` **architecture** | `lib/minion-run.sh:81` | pattern-violation: parse_field sed doesn't strip trailing content after value; 'provider: openai # note' would parse as 'openai # note' -- Add trailing comment strip or document that inline YAML comments are unsupported
9. [ ] `minor` **performance** | `lib/minion-run.sh:80` | missing-caching: parse_field spawns a subshell per call (9 times); all fields could be extracted in a single awk pass -- Replace 9 sed calls with one awk pass
10. [ ] `minor` **performance** | `lib/minion-run.sh:72` | memory-allocation: file read by 2 awk processes + 1 sed for body trim; could be single awk pass -- Combine into one awk
11. [ ] `minor` **code-simplifier** | `lib/minion-run.sh:80` | code-structure: parse_field and parse_list implicitly depend on outer $FRONTMATTER variable -- Pass $FRONTMATTER as explicit argument
12. [ ] `minor` **code-simplifier** | `lib/minion-run.sh:109` | code-readability: parse_list defined far from parse_field, separated by variable assignments -- Move parse_list immediately after parse_field
13. [ ] `minor` **test-quality** | `test/test-frontmatter-parsing.sh:141` | missing-test: mutual exclusivity test asserts only exit code, not stderr error message -- Add stderr_pattern for error text
14. [ ] `minor` **test-quality** | `test/test-frontmatter-parsing.sh:149` | missing-test: file-not-found test asserts only exit code, not stderr message -- Add stderr_pattern "file not found"
15. [ ] `minor` **test-quality** | `test/test-frontmatter-parsing.sh:574` | missing-test: body containing a --- line (markdown HR) untested; awk delimiter count may truncate body -- Add test with --- in body content
16. [ ] `minor` **test-quality** | `test/test-frontmatter-parsing.sh:224` | missing-test: leading-blank-line trim behavior (line 77 of minion-run.sh) has no dedicated test -- Add test with blank line after closing ---
17. [ ] `minor` **code-simplifier** | `test/test-frontmatter-parsing.sh:598` | needless-repetition: check_absent_booleans not using consolidated check_flag_absent helper -- Replace with three check_flag_absent calls or a loop
18. [ ] `minor` **code-quality** | `test/test-frontmatter-parsing.sh:567` | code-readability: check_no_prompt_arg and check_absent_booleans are one-off inline functions that could be expressed as run_and_check calls -- Inline or simplify
19. [ ] `minor` **spec-alignment** | `lib/minion-run.sh:93` | specification-gap: architecture section 4.3 says missing-field message goes to stdout; implementation now correctly uses stderr -- Update architecture doc to reflect stderr convention

---

## Run: 2026-04-03 | TASK-005: Minion file resolution

1. [ ] `major` **code-quality, code-simplifier** | `test/test-minion-file-resolution.sh:75` | multi-assert: 'error reports searched locations' bundles 4 assertions in one check; failure doesn't indicate which failed -- Split into separate single-assertion checks
2. [ ] `major` **code-quality, code-simplifier** | `test/test-minion-file-resolution.sh:119` | multi-assert: protocol tokens check bundles FOUND:, NOT_FOUND, SEARCHED: in one check -- Split into individual token checks
3. [ ] `major` **code-quality, code-simplifier** | `test/test-minion-file-resolution.sh:125` | multi-assert: 'invalid name error' tests error message language AND character class pattern together -- Split into two separate checks
4. [ ] `major` **code-quality** | `test/test-minion-file-resolution.sh:32` | test-coverage: All 16 tests are structural text-presence checks; no integration tests execute actual bash resolution logic -- Add at least one happy-path and one NOT_FOUND integration test
5. [ ] `major` **code-simplifier** | `skills/delegate-to-minion/SKILL.md:136` | needless-repetition: Name validation command appears twice (standalone + inside combined bash block) -- Keep only the combined block
6. [ ] `major` **code-simplifier** | `test/test-minion-file-resolution.sh:32` | needless-repetition: check_section4 repeats `env SKILL_FILE=... python3 -c` inline on every call -- Inline invocation into the helper function
7. [ ] `minor` **spec-alignment** | `skills/delegate-to-minion/SKILL.md:131` | specification-gap: SEARCHED paths use relative form (./) while FOUND absolutizes via $(pwd) -- Absolutize SEARCHED paths for consistency
8. [ ] `minor` **security** | `skills/delegate-to-minion/SKILL.md:210` | input-validation: Provider/model escaping assumes 'simple identifiers' but minion file values are user-controlled -- Apply same single-quote escaping to provider/model
9. [ ] `minor` **security** | `skills/delegate-to-minion/SKILL.md:150` | input-validation: Absolute paths with newlines could produce malformed FOUND: output -- Validate no control characters in absolute path
10. [ ] `minor` **housekeeper** | `specs/architecture.md:237` | documentation-stale: Security section doesn't mention CWE-22 path traversal mitigation added in TASK-005 -- Add note about name character validation
11. [ ] `minor` **architecture** | `test/test-minion-file-resolution.sh:6` | pattern-violation: python3 test dependency conflicts with DR-003 zero-dependency ethos -- Document test exemption or rewrite in bash
12. [ ] `minor` **performance** | `test/test-minion-file-resolution.sh:32` | missing-caching: Each check_section4 forks python3 and reads SKILL.md (16 times) -- Consolidate into single invocation
13. [ ] `minor` **code-simplifier** | `skills/delegate-to-minion/SKILL.md:171` | comments: Resolved path subsection restates what Cases A and B already say -- Remove redundant subsection
14. [ ] `minor` **code-simplifier** | `skills/delegate-to-minion/SKILL.md:86` | comments: Security note (single-quote escaping) duplicated from Step 7 -- Reference Step 7 instead
15. [ ] `minor` **code-quality** | `test/test-minion-file-resolution.sh:53` | test-quality: `and '/' in section` is trivially true in any path-related section -- Drop redundant clause
16. [ ] `minor` **code-quality** | `test/test-minion-file-resolution.sh:6` | readability: `set -uo pipefail` omits `-e`; intentional but undocumented -- Add comment explaining why
17. [ ] `minor` **test-quality** | `test/test-minion-file-resolution.sh:64` | implementation-coupling: Resolution order anchored to 'absolute' word in intro, not Case A heading -- Anchor to 'case a:' instead
18. [ ] `minor` **test-quality** | `test/test-minion-file-resolution.sh:114` | implementation-coupling: Path traversal check passes on 'grep' anywhere in section -- Remove 'grep' shortcut, use specific terms
19. [ ] `minor` **code-simplifier** | `test/test-minion-file-resolution.sh:32` | naming: check_section4 named after section number not intent -- Rename to check_resolution_section

---

## Run: 2026-04-02 | TASK-004: Skill inline invocation flow

1. [ ] `major` **security** | `skills/delegate-to-minion/SKILL.md:126` | injection: LLM-applied single-quote escaping is a structural risk; Claude may misapply the `'\''` idiom for prompts containing single quotes -- Consider adding `--prompt-file` flag to minion-run.sh to accept prompt via file instead of shell argument
2. [ ] `minor` **security** | `skills/delegate-to-minion/SKILL.md:122` | injection: Pi stdout presented verbatim to conversation context; malicious Pi response could contain prompt-injection payloads -- Wrap Pi output in a labeled code fence to delineate as untrusted data
3. [ ] `minor` **code-quality, test-quality** | `test/validate-plugin-structure.sh` | test-coverage: No automated check that COMMAND.md and SKILL.md contain the mode handoff phrases; drift between files would be caught only at runtime -- Add grep assertions for "Inline mode" in both files
4. [ ] `minor` **code-quality** | `commands/minion/COMMAND.md:18` | code-elegance: Detection rule uses OR (`--provider` or `--model`); AND would be more robust discriminator since both are always required for inline mode -- Change to AND with explicit partial-inline fallback
5. [ ] `minor` **test-quality** | `test/test-minion-run.sh:226` | missing-test: No test for Pi stderr passthrough on success (exit 0 with stderr) -- Add test with MOCK_PI_EXIT_CODE=0 and MOCK_PI_STDERR set
6. [ ] `minor` **test-quality** | `test/test-minion-run.sh:238` | missing-test: Only `--provider` missing-value case tested; `--model` and `--prompt` missing-value paths untested -- Add symmetrical exit-2 tests for each flag
7. [ ] `minor` **test-quality** | `test/test-minion-run.sh:142` | missing-test: No test for prompt with shell-sensitive characters (quotes, `$`, backticks) -- Add test verifying special chars pass through verbatim
8. [ ] `minor` **architecture** | `specs/architecture.md:96` | adr-violation: Section 4.1 states argument validation happens in the command, but implementation defers validation to the skill per DR-004 -- Update section 4.1 to say argument parsing (not validation) is in the command
9. [ ] `minor` **architecture** | `skills/delegate-to-minion/SKILL.md:139` | pattern-violation: Exit code 1 guidance says to report stderr, but minion-run.sh emits validation messages to stdout -- Either change minion-run.sh to use stderr or update skill guidance
10. [ ] `minor` **spec-alignment** | `skills/delegate-to-minion/SKILL.md:138` | specification-gap: Exit code 1 branch in Step 7 is unreachable in inline mode since Step 3 validates before execution -- Add note that this is a defense-in-depth fallback
11. [ ] `minor` **code-simplifier** | `commands/minion/COMMAND.md:27` | clarity: "join them as a single prompt string" does not specify separator (space implied) -- Add "join with a single space"

---

## Run: 2026-04-02 | TASK-003: minion-run.sh with inline mode

1. [ ] `minor` **security** | `lib/minion-run.sh:59` | input-validation: PROVIDER and MODEL passed to Pi with no format validation; a malformed value could cause unexpected Pi behavior -- Add allowlist regex e.g. `[a-zA-Z0-9_-]{1,64}`
2. [ ] `minor` **security** | `lib/minion-run.sh:51` | input-validation: PROMPT has no length limit; unbounded prompt could amplify Pi API costs -- Consider max length check e.g. 65536 chars
3. [ ] `minor` **code-quality, code-simplifier** | `lib/minion-run.sh:63` | code-elegance: `exit $?` after `"${cmd[@]}"` is redundant; shell exits with last command's code naturally -- Remove line 63
4. [ ] `minor` **code-quality, test-quality** | `test/test-minion-run.sh:147` | test-coverage: Missing-param tests check for bare field name (e.g. "model") not full format "missing: model"; format change wouldn't be caught -- Change stdout_pattern to "missing: model" etc.
5. [ ] `minor` **code-quality** | `test/test-minion-run.sh:176` | test-coverage: `check_no_args_all_fields` inline function uses different style from `run_and_check` pattern used everywhere else -- Consolidate into single `run_and_check` with pattern "missing: provider, model, prompt"
6. [ ] `minor` **code-simplifier, performance** | `test/test-minion-run.sh:96` | code-structure: `run_and_check` evaluates grep conditions twice (once for pass/fail, once for diagnostics) -- Store results in boolean vars and reuse
7. [ ] `minor` **code-simplifier** | `test/test-minion-run.sh:62` | code-structure: `--` separator in `run_and_check` is optional but always used; hybrid pattern adds cognitive overhead -- Make mandatory or remove
8. [ ] `minor` **test-quality** | `test/test-minion-run.sh:249` | missing-test: The `*` branch (bare positional word, line 40-43 of minion-run.sh) has no test; only `-*` unknown flag branch is tested -- Add test with positional arg after all flags
9. [ ] `minor` **spec-alignment** | `lib/minion-run.sh:62` | action-item: Action item says "output stdout on success, stderr on failure" but implementation passes both through unconditionally -- Update action item wording to match implementation

---

## Run: 2026-04-02 | TASK-002: Pi availability check with install offer

1. [ ] `minor` **security** | `skills/delegate-to-minion/SKILL.md:35` | insecure-design: curl-pipe-bash install pattern has no integrity check (CWE-494) -- Add SHA-256 verification once upstream publishes checksums
2. [ ] `minor` **code-quality, code-simplifier** | `test/test-pi-availability.sh:6` | test-isolation: `set -uo pipefail` omits `-e`; failures outside `check()` continue silently -- Add `-e` or document intentional omission with a comment
3. [ ] `minor` **test-quality** | `test/test-pi-availability.sh:64` | implementation-coupling: decline+abort check doesn't verify proximity; words could appear in different branches -- Use regex like `r'declin.{0,200}abort'` for tighter assertion
4. [ ] `minor` **test-quality** | `test/test-pi-availability.sh:68` | missing-test: No test for install-failure sub-branch (post-install verification fails) -- Add assertion for 'install manually' or 'did not succeed' text
5. [ ] `minor` **performance** | `test/test-pi-availability.sh:32` | blocking-io: Spawns fresh python3 process per assertion (8 times); reads SKILL.md each time -- Consolidate into single python3 invocation or extract section in bash
6. [ ] `minor` **security** | `test/test-pi-availability.sh:17` | logging: check() suppresses stderr; test failures show no diagnostic output -- Capture stderr and print on failure only
7. [ ] `minor` **code-simplifier** | `test/test-pi-availability.sh:29` | naming: `check_section1` name embeds section number rather than intent -- Rename to `check_availability_section`
8. [x] `minor` **housekeeper, code-quality** | `specs/tasks/_index.md:12` | documentation-stale: M1 milestone status shows 'Not Started' despite TASK-001 Complete and TASK-002 In Progress -- Update to 'In Progress'
9. [ ] `minor` **architecture** | `skills/delegate-to-minion/SKILL.md:41` | pattern-violation: Post-install failure path lacks explicit 'abort' and 'do not proceed' mirroring decline path -- Add explicit abort instruction for consistency

---

## Run: 2026-04-02 | TASK-001: Plugin directory structure and manifest

1. [ ] `major` **code-quality, code-simplifier** | `test/validate-plugin-structure.sh:6` | error-handling: `set -uo pipefail` is missing `-e` flag; without it, unguarded failures outside `check()` continue silently -- Add `-e` or document its intentional omission with a comment
2. [ ] `major` **code-quality, security, code-simplifier** | `test/validate-plugin-structure.sh:30` | injection: `check_json_field` and `check_frontmatter` embed `$ROOT`/`$file` directly into Python source via interpolation; paths with special characters break silently -- Pass paths via `sys.argv` or environment variable instead
3. [ ] `major` **code-quality, test-quality, spec-alignment** | `test/validate-plugin-structure.sh:76` | missing-test: COMMAND.md frontmatter `name` field not validated; acceptance criterion `/minion appears in command list` depends on this -- Add `check_frontmatter` assertion for `name == 'minion'`
4. [ ] `major` **code-quality, test-quality** | `test/validate-plugin-structure.sh:95` | missing-test: SKILL.md `user-invocable: false` not tested; controls skill visibility -- Add `check_frontmatter` assertion for `user-invocable` field
5. [ ] `minor` **security** | `skills/delegate-to-minion/SKILL.md:44` | insecure-design: When implementing TASK-005, validate absolute paths to prevent path traversal -- Restrict to project root or user home
6. [ ] `minor` **security** | `skills/delegate-to-minion/SKILL.md:63` | insecure-design: When implementing TASK-003, ensure shell arguments to pi are properly quoted -- Use exec-array form, validate provider/model patterns
7. [ ] `minor` **architecture** | `commands/minion/COMMAND.md:5` | pattern-violation: `allowed-tools` includes Glob and Grep which aren't needed for thin dispatcher role -- Remove unless concrete use case identified
8. [ ] `minor` **code-simplifier** | `test/validate-plugin-structure.sh:72` | code-structure: Inline frontmatter-has check duplicates logic already in `check_frontmatter` helper -- Extract `check_has_frontmatter` or extend helper
9. [ ] `minor` **code-simplifier** | `skills/delegate-to-minion/SKILL.md:62` | naming: TODO references `TASK-004/TASK-007` with ambiguous slash notation -- Split into separate TODO lines per task
10. [ ] `minor` **code-quality** | `skills/delegate-to-minion/SKILL.md:14` | readability: HTML comment TODOs invisible when rendered -- Convert to visible Markdown notes or document convention
11. [ ] `minor` **code-quality, code-simplifier** | `CLAUDE.md:20` | readability: `lib/minion-run.sh` listed in structure but doesn't exist yet -- Mark as `# placeholder — created in TASK-003`
12. [ ] `minor` **housekeeper** | `specs/architecture.md:192` | architecture-not-updated: Plugin structure diagram missing `test/` directory -- Add to diagram
13. [ ] `minor` **spec-alignment** | `skills/delegate-to-minion/SKILL.md:1` | action-item: Task spec lists `when-to-use` as distinct frontmatter key but implementation folds it into `description` -- Add dedicated key or update task spec
14. [ ] `minor` **code-quality** | `test/validate-plugin-structure.sh:100` | test-coverage: `lib/.gitkeep` existence not verified -- Add assertion
15. [ ] `minor` **code-simplifier** | `test/validate-plugin-structure.sh:10` | naming: `PASS`/`FAIL` counter names use all-caps convention reserved for env vars -- Rename to `pass_count`/`fail_count`
