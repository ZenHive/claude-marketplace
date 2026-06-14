#!/usr/bin/env bash
# PreToolUse:Edit|Write|MultiEdit — soft warn when an edit to roadmap/tasks.toml
# introduces demand-hedge phrasing ("wait until someone asks", "unproven
# demand", "table-stakes", "buyers expect", ...).
#
# Critical-rules § NO PSEUDO-RIGOROUS HEDGING: you have no consumer telemetry —
# the developer IS the demand signal. Demand-hedge phrasing reframes requested
# work as needing evidence you can't get. A task may only be gated on a NAMED
# technical / legal / market-scope dependency with a concrete unblock path —
# never on speculated demand.
#
# Fires on: Edit/Write/MultiEdit whose target is */roadmap/tasks.toml AND whose
# new text matches a hedge phrase. Soft reminder — exit 0, additionalContext.

set -eo pipefail

emit_suppress() { jq -n '{"suppressOutput": true}'; exit 0; }

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[[ -z "$FILE" || "$FILE" == "null" ]] && emit_suppress

case "$FILE" in
  */roadmap/tasks.toml) ;;
  *) emit_suppress ;;
esac

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

case "$TOOL_NAME" in
  Write)     NEW_TEXT=$(echo "$INPUT" | jq -r '.tool_input.content // empty') ;;
  Edit)      NEW_TEXT=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty') ;;
  MultiEdit) NEW_TEXT=$(echo "$INPUT" | jq -r '[.tool_input.edits[]?.new_string] | join("\n")') ;;
  *)         emit_suppress ;;
esac

HEDGE='wait until|unproven demand|is this widely needed|table[ -]stakes|buyers expect|increasingly standard|once a customer|first paying'
echo "$NEW_TEXT" | grep -qiE "$HEDGE" || emit_suppress

MESSAGE="🪝 Demand-hedge phrasing in a roadmap task.

Critical-rules § NO PSEUDO-RIGOROUS HEDGING: you have no consumer telemetry —
the developer IS the demand signal. \"Wait until someone asks\", \"unproven
demand\", \"table-stakes\", \"buyers expect\" reframe requested work as needing
evidence you can't get. That's risk-aversion theater, not analysis.

A task may only be gated on a NAMED technical / legal / market-scope dependency
with a concrete unblock path — a missing dep, a licensing/regulatory trigger,
an unactivated market — never on speculated demand.

Fix: either name the real technical/legal/structural blocker (and use
\`status = \"blocked\"\` + \`blocked_reason\`), or score it honestly low — don't
smuggle demand-speculation into B/U or the body. If the phrase names a concrete
market-scope trigger (e.g. \"wait until market MY activates\"), that's legitimate
dependency-gating — ignore this warning."

jq -n --arg ctx "$MESSAGE" '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": $ctx
  }
}'
