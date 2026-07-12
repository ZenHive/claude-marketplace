#!/usr/bin/env bash
# PreToolUse:Edit|Write|MultiEdit — BLOCK an edit to roadmap/tasks.toml that
# sets `assignee = "human"` without a `# human:` blocker line justifying it.
#
# The recurring failure mode this guards: a dispatchable task gets
# `assignee = "human"`, silently lands on the operator, and the delivery
# pipeline never picks it up. `human` is RESERVED — legitimate only when no
# agent can do the work from a sandbox, and the concrete blocker must be named
# on a `# human:` comment line.
#
# Fires on: Edit/Write/MultiEdit whose target is */roadmap/tasks.toml AND whose
# new text contains `assignee = "human"` but no `# human:` line.
# Silent on: any other assignee, files that aren't tasks.toml, edits whose new
# text doesn't touch a human assignee.
#
# This is the ONE blocking hook in dev-discipline (the others are soft
# reminders). Masking dispatchable work as human-assigned is costly enough —
# and recoverable enough (add the line, re-apply) — to warrant a hard deny.

set -eo pipefail

emit_suppress() { jq -n '{"suppressOutput": true}'; exit 0; }

emit_deny() {
  local reason="$1"
  local msg="$2"
  jq -n --arg reason "$reason" --arg msg "$msg" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    },
    systemMessage: $msg
  }'
  exit 0
}

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[[ -z "$FILE" || "$FILE" == "null" ]] && emit_suppress

case "$FILE" in
  */roadmap/tasks.toml) ;;
  *) emit_suppress ;;
esac

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# The "new text" introduced by this edit, normalized across the three tools.
case "$TOOL_NAME" in
  Write)     NEW_TEXT=$(echo "$INPUT" | jq -r '.tool_input.content // empty') ;;
  Edit)      NEW_TEXT=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty') ;;
  MultiEdit) NEW_TEXT=$(echo "$INPUT" | jq -r '[.tool_input.edits[]?.new_string] | join("\n")') ;;
  *)         emit_suppress ;;
esac

# Only fire when this edit introduces a human assignee with no justification.
echo "$NEW_TEXT" | grep -qE 'assignee[[:space:]]*=[[:space:]]*"human"' || emit_suppress
echo "$NEW_TEXT" | grep -q '# human:' && emit_suppress

emit_deny \
"[DD-1] \`assignee = \"human\"\` with no \`# human:\` blocker line — this masks dispatchable work as human-assigned, where it drops off the delivery pipeline.

\`human\` is RESERVED. It is legitimate only when no agent can do the work from a sandbox, and you must name the concrete blocker on a \`# human:\` comment line immediately above \`assignee = \"human\"\` — external account / network vantage, business or legal sign-off, or a genuine product/architecture decision spike.

Fix one of two ways:
  1. The work IS dispatchable → give it a real dispatch assignee + model per the project's routing ledger. If parking it, use \`status = \"blocked\"\` + \`blocked_reason = \"<unblock trigger>\"\` — a parked engineering task keeps its dispatchable assignee/model. A dispatch hint (e.g. handbuild) is never an assignee.
  2. It genuinely needs a human → add a \`# human: <concrete external/legal/decision blocker>\` line right above \`assignee = \"human\"\`, then re-apply." \
"dev-discipline [DD-1]: assignee = \"human\" in tasks.toml needs a # human: blocker line"
