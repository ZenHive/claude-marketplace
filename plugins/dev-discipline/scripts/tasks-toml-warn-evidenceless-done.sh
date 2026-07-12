#!/usr/bin/env bash
# PreToolUse:Edit|Write|MultiEdit — soft warn when an edit flips a task to
# `status = "done"` with no shipping evidence (implemented / shipped_in /
# delivered_by) in the same edit.
#
# A `done` with no evidence is often a decision-only "done" burying a deferred
# build under `done`, where it drops out of the backlog — the same silent-defer
# failure as masking work as `human`, in a different shape.
#
# Fires on: Edit/Write/MultiEdit whose target is */roadmap/tasks.toml AND whose
# new text adds `status = "done"` but none of implemented / shipped_in /
# delivered_by. Soft reminder — exit 0, additionalContext.

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

# Only fire when this edit sets a done status with no shipping evidence beside it.
echo "$NEW_TEXT" | grep -qE 'status[[:space:]]*=[[:space:]]*"done"' || emit_suppress
echo "$NEW_TEXT" | grep -qE 'implemented|shipped_in|delivered_by' && emit_suppress

MESSAGE="🪝 [DD-7] Task flipped to \`status = \"done\"\` with no shipping evidence in this edit.

A \`done\` with no \`implemented\` / \`shipped_in\` / \`delivered_by\` is often a
decision-only \"done\" burying a deferred build under \`done\`, where it drops out
of the backlog — the same silent-defer failure as masking work as \`human\`, in a
different shape.

Decide which it actually is:
  • Genuinely shipped → add the evidence (\`implemented = \"...\"\`,
    \`shipped_in\`/\`delivered_by\`, \`verified = true\`). Then this warning clears.
  • Deferred, not built → it is NOT done. Use \`status = \"blocked\"\` +
    \`blocked_reason = \"<unblock trigger>\"\` so it stays visible, or keep it
    \`pending\` and dispatch it. Capturing a design decision is fine — but the
    *build* it defers must remain a tracked open task."

jq -n --arg ctx "$MESSAGE" '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": $ctx
  }
}'
