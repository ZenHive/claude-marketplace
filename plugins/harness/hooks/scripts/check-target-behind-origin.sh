#!/usr/bin/env bash
# SessionStart hook: warn if the current branch is behind its origin tracking branch.
#
# With harness auto-landing on (landing_policy: :auto), the lander is a SECOND
# committer to origin/<target> — it ff-pushes from a detached worktree and never
# touches your checkout, so your local ref drifts behind origin after every land.
# Committing/pushing from a stale base then produces non-ff rejects and stale-base
# review noise. This nudge surfaces the drift at session start so you rebase first.
#
# Fails open: any error (not a git repo, no upstream, fetch fails) -> silent.

set -euo pipefail

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  jq -n '{"suppressOutput": true}'
  exit 0
fi

CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
if [[ -z "$CURRENT_BRANCH" ]]; then
  jq -n '{"suppressOutput": true}'
  exit 0
fi

# Resolve the upstream tracking ref (e.g. origin/development); silent if none set.
UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || echo "")
if [[ -z "$UPSTREAM" ]]; then
  jq -n '{"suppressOutput": true}'
  exit 0
fi

REMOTE="${UPSTREAM%%/*}"
REMOTE_BRANCH="${UPSTREAM#*/}"

if ! timeout 5 git fetch --quiet "$REMOTE" "$REMOTE_BRANCH" 2>/dev/null; then
  jq -n '{"suppressOutput": true}'
  exit 0
fi

BEHIND=$(git rev-list --count "HEAD..$UPSTREAM" 2>/dev/null || echo 0)

if [[ "$BEHIND" -gt 0 ]]; then
  jq -n --arg branch "$CURRENT_BRANCH" --arg upstream "$UPSTREAM" --arg behind "$BEHIND" '{
    "hookSpecificOutput": {
      "hookEventName": "SessionStart",
      "additionalContext": ("Branch \($branch) is \($behind) commits behind \($upstream). If harness auto-landing is on, the lander has pushed since your last pull — run `git fetch \($upstream | split("/")[0]) \($upstream | split("/")[1:] | join("/")) && git rebase \($upstream)` before committing to avoid a stale base / non-ff push.")
    }
  }'
else
  jq -n '{"suppressOutput": true}'
fi
