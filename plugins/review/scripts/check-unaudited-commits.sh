#!/usr/bin/env bash
# SessionStart hook: surface unaudited commit tail when ≥3 commits sit past
# the last `audit(...)` ancestor. Quiets context-switched / interrupted
# sessions that would otherwise accumulate unaudited work silently.
#
# Fails open: any error (not a git repo, missing helper, etc.) -> silent.

set -euo pipefail

THRESHOLD=3
HELPER="$(dirname "$0")/unaudited-commits.sh"

if [[ ! -x "$HELPER" ]]; then
  jq -n '{"suppressOutput": true}'
  exit 0
fi

if ! tsv=$("$HELPER" --threshold "$THRESHOLD" --short-sha 2>/dev/null); then
  jq -n '{"suppressOutput": true}'
  exit 0
fi

if [[ -z "$tsv" ]]; then
  jq -n '{"suppressOutput": true}'
  exit 0
fi

IFS=$'\t' read -r count last_sha last_date range <<<"$tsv"

if [[ "$last_sha" != "-" ]]; then
  msg="${count} unaudited commits since audit(${last_sha}) on ${last_date} (range: ${range}). Run \`/staged-review:audit-status\` for the full snapshot, or \`Skill(audit-review)\` to audit ${range}."
else
  msg="${count} commits with no audit history yet (range: ${range}). Run \`/staged-review:audit-status\` for details, or \`Skill(audit-review)\` to start the audit corpus."
fi

jq -n --arg msg "$msg" '{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": $msg
  }
}'
