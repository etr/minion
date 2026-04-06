# TASK-015: test/test-auto-dispatch.sh tests

**Milestone:** M5 — Auto-Minion Mode
**Estimate:** M
**Status:** Complete
**Depends on:** TASK-011

---

## Goal

Implement `test/test-auto-dispatch.sh` — automated tests for `lib/auto-dispatch.sh` using a mock Pi binary.

## Deliverables

- `test/test-auto-dispatch.sh` — bash test suite with mock Pi infrastructure

## Test Coverage

- Argument validation (missing flags, unknown flags, missing config file)
- Config validation (missing dispatcher model/provider, custom category without description)
- Dry-run dispatch: route header, provider, model, fallback reason
- Dispatcher returns "default": routes to configured default provider/model
- Dispatcher failure fallback (exit 3) and fallback reason
- Unrecognized dispatcher response fallback
- Inherit dispatcher: DISPATCHER:inherit and NEEDS_INLINE_CLASSIFICATION
- Inherit category: PROVIDER:inherit and MODEL:inherit
- Custom categories: routing, provider, model
- Full execution (non-dry-run): route header, mock Pi args verification
- Mock args verification with specific provider/model substrings
- Input validation: provider/model with shell metacharacters rejected
- Path-traversal minion names in config rejected
- Category description truncation (>200 chars)
- No-default fallback (FALLBACK:no_default, exit 3)
- Minion-based routing: MINION header in dry-run
- Missing minion file error reporting
- Route execution failure fallback to default (exit 3)
- All routes failed (exit 4)
- Mock variable isolation via snapshot at test invocation time

## Acceptance Criteria

- All tests pass with `bash test/test-auto-dispatch.sh`
- Mock Pi placed first in PATH to intercept all Pi calls
- Fixture configs created in temp directory, cleaned up on exit
- `run_and_check` helper validates exit code, stdout pattern, stderr pattern
- grep uses `grep -qF --` to support patterns starting with `--`
