# Minor TODOs

Accumulated unexecuted findings from validation runs. Check items off as addressed.

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
