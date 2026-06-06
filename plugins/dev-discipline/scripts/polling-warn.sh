#!/usr/bin/env bash
# PreToolUse:Bash — soft warn when about to run a long sleep or a polling
# loop. Almost always means: "I should return to the user and wait for an
# event-notification instead of burning wallclock here."
#
# Fires on: sleep N where N >= 10 (any unit suffix preserved), until/while
# loops that contain `sleep`. Silent on short bridge sleeps (sleep 1..9).
#
# Reminder only — the harness-side polling rule is the hard wall; this is
# the cross-repo soft cousin.

set -eo pipefail

emit_suppress() { jq -n '{"suppressOutput": true}'; exit 0; }

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[[ -z "$CMD" || "$CMD" == "null" ]] && emit_suppress

# Match `sleep N` where N has 2+ digits (>= 10), with optional unit suffix.
# Also match `until ...; do sleep ...` and `while ...; do sleep ...` polling.
if echo "$CMD" | grep -qE '\bsleep[[:space:]]+[0-9]{2,}'; then
  TRIGGER="long sleep (>= 10s)"
elif echo "$CMD" | grep -qE '(until|while)[[:space:]]+.*;[[:space:]]*do[[:space:]]+.*sleep'; then
  TRIGGER="polling loop (until/while + sleep)"
else
  emit_suppress
fi

MESSAGE="🪝 No polling. Wait for the event.

Detected: $TRIGGER.

You're about to burn wallclock waiting for something. The harness, the
TaskCreate runtime, and your background Bash all notify you when work
completes — sleeping past that notification just delays your own response.

Right pattern:
  • Long-running background tool → return to the user, wait for the
    completion notification. Don't sleep, don't poll.
  • External state Claude can't observe (CI run, deploy, remote queue)
    → use a Monitor with an event-shaped check, not a fixed-length sleep.
  • Genuinely brief bridge (sleep 1..9) → not flagged, proceed.

If you're polling external state with no event mechanism, switch to the
Monitor tool's until-loop pattern (the runtime notifies on exit) rather
than a long bare sleep."

jq -n --arg ctx "$MESSAGE" '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": $ctx
  }
}'
