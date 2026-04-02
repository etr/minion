# Minor TODOs

Accumulated unexecuted findings from validation runs. Check items off as addressed.

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
