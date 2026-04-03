#!/usr/bin/env bash
# minion-run.sh — Mechanical layer: parse args, construct Pi CLI command, execute.
# No UX, no prompting — exit codes and stdout/stderr only.
#
# Usage: minion-run.sh --provider <val> --model <val> --prompt <val>
#
# Exit codes:
#   0   — Pi succeeded
#   1   — Validation error (missing required params)
#   2   — Unknown flag
#   N   — Pi's exit code passed through
set -uo pipefail

PROVIDER=""
MODEL=""
PROMPT=""

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

# --- Validation ---
missing=""
[ -z "$PROVIDER" ] && missing="${missing:+$missing, }provider"
[ -z "$MODEL" ]    && missing="${missing:+$missing, }model"
[ -z "$PROMPT" ]   && missing="${missing:+$missing, }prompt"

if [ -n "$missing" ]; then
  echo "missing: $missing"
  exit 1
fi

# --- Command construction (array form for safe quoting) ---
cmd=(pi --provider "$PROVIDER" --model "$MODEL" "$PROMPT")

# --- Execution ---
"${cmd[@]}"
exit $?
