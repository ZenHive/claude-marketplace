#!/usr/bin/env bash
# SessionStart hook: warn if the current branch is behind origin/main.
# Codex may have landed PRs since the last local pull; reviewing or claiming
# tasks against a stale base produces stale-base review noise.
#
# Fails open: any error (not a git repo, fetch fails, no origin/main) -> silent.

set -euo pipefail

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  jq -n '{"suppressOutput": true}'
  exit 0
fi

if ! timeout 5 git fetch --quiet origin main 2>/dev/null; then
  jq -n '{"suppressOutput": true}'
  exit 0
fi

BEHIND=$(git rev-list --count HEAD..origin/main 2>/dev/null || echo 0)
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo unknown)

if [[ "$BEHIND" -gt 0 ]]; then
  jq -n --arg branch "$CURRENT_BRANCH" --arg behind "$BEHIND" '{
    "hookSpecificOutput": {
      "hookEventName": "SessionStart",
      "additionalContext": ("Branch \($branch) is \($behind) commits behind origin/main. If working on a [CX] follow-up or claiming a roadmap task, run `git rebase origin/main` first to avoid stale-base reviews.")
    }
  }'
else
  jq -n '{"suppressOutput": true}'
fi
