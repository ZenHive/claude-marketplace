#!/usr/bin/env bash
# Shared helper for /staged-review:audit-status and the unaudited-commits SessionStart hook.
#
# Detects the last `audit(...)` commit ancestor and counts commits since.
# Prints TSV: count<TAB>last_audit_sha<TAB>last_audit_date<TAB>range
#
# Exit codes:
#   0 — in a git repo (output is meaningful)
#   2 — not in a git repo (no output)
#
# Flags:
#   --threshold N    suppress output when count < N (still exit 0); default 1
#   --short-sha      print last_audit_sha as 7-char short form (default: full)

set -euo pipefail

threshold=1
short_sha=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --threshold)
      threshold="${2:-1}"
      shift 2
      ;;
    --short-sha)
      short_sha=1
      shift
      ;;
    *)
      echo "unaudited-commits.sh: unknown flag: $1" >&2
      exit 64
      ;;
  esac
done

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 2
fi

last_audit_sha=$(git log --grep '^audit(' -1 --format=%H 2>/dev/null || true)

if [[ -n "$last_audit_sha" ]]; then
  count=$(git rev-list --count "${last_audit_sha}..HEAD" 2>/dev/null || echo 0)
  last_audit_date=$(git log -1 --format=%cs "$last_audit_sha" 2>/dev/null || echo "-")
  range="${last_audit_sha}..HEAD"
else
  total=$(git rev-list --count HEAD 2>/dev/null || echo 0)
  if [[ "$total" -gt 50 ]]; then
    count=50
    range="HEAD~50..HEAD"
  else
    count="$total"
    range="HEAD"
  fi
  last_audit_date="-"
fi

if [[ "$count" -lt "$threshold" ]]; then
  exit 0
fi

if [[ "$short_sha" -eq 1 && -n "$last_audit_sha" ]]; then
  last_audit_sha="${last_audit_sha:0:7}"
fi

# Empty fields become "-" so consumers using `read -r` with IFS=$'\t' don't
# collapse adjacent tabs (bash whitespace-IFS rule).
[[ -z "$last_audit_sha" ]] && last_audit_sha="-"
[[ -z "$last_audit_date" ]] && last_audit_date="-"

printf '%s\t%s\t%s\t%s\n' "$count" "$last_audit_sha" "$last_audit_date" "$range"
