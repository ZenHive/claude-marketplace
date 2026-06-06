#!/usr/bin/env bash
# PreToolUse:Bash — soft reminder when about to run `rmap new`.
#
# Pauses Claude to answer: is this finding fixable in the current commit?
# Reminder only, NOT a block (exit 0 + additionalContext).
#
# Fires on: rmap new, rmap new --from-stdin, ... && rmap new ..., chained variants.
# Silent on: rmap list, rmap show, rmap status, rmap next, rmap render, etc.
#
# Origin: hookify:conversation-analyzer surfaced the close-2-open-2 pattern in
# transcript ...aa46fc79-eaf4-4bd8-a826-8bbd94667770.jsonl — user-flagged
# cross-session, not session-local. Memory `feedback_dogfood-task-spawn-rate`
# names the symptom but doesn't fire at the trigger word; this hook does.

set -eo pipefail

emit_suppress() { jq -n '{"suppressOutput": true}'; exit 0; }

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[[ -z "$CMD" || "$CMD" == "null" ]] && emit_suppress

# Match `rmap new` at start, after whitespace, or after a shell separator.
# Word-boundary after `new` so `rmap newxyz` (hypothetical) does NOT match.
echo "$CMD" | grep -qE '(^|[[:space:]]|;|&|\|)rmap[[:space:]]+new([[:space:]]|$)' \
  || emit_suppress

MESSAGE="🪝 rmap new gate — pause and pick.

Cross-session or cross-repo work → file the task.
In-scope finding that fits the current commit → fix inline, don't file.
Same-PR follow-up → push back / amend the staged set, don't file.

Why this hook exists: the close-2-open-2 pattern (close N tasks, open N
new tasks) accumulates churn across sessions. The roadmap-as-queue only
earns its overhead when work genuinely spans sessions or repos.

If you've answered 'yes, this is cross-session / cross-repo' — proceed."

jq -n --arg ctx "$MESSAGE" '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": $ctx
  }
}'
