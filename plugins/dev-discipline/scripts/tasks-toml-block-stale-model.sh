#!/usr/bin/env bash
# PreToolUse:Edit|Write|MultiEdit — BLOCK an edit to roadmap/tasks.toml that
# pins a dead model id (`model = "gpt-5-codex"`).
#
# The recurring failure mode this guards: a task carries
# `model = "gpt-5-codex"`, a model id that is NOT in the codex catalog and is
# operator-blocked (unsupported on ChatGPT/subscription Codex accounts —
# requires a metered API account). A per-task `model` pin wins over
# `agent_model.codex`, so the stale pin silently overrides the configured model
# and the dispatch fails: codex routing dies with "unavailable", and even a
# claude-adapter dispatch dies with "invalid_model_for_adapter". The valid
# codex model is `gpt-5.5` (catalog: gpt-5.5 | gpt-5.4 | gpt-5.4-mini |
# gpt-5.3-codex-spark).
#
# Fires on: Edit/Write/MultiEdit whose target is */roadmap/tasks.toml AND whose
# new text introduces `model = "gpt-5-codex"`.
# Silent on: any other model id, files that aren't tasks.toml, edits whose new
# text doesn't touch this dead pin.
#
# A hard deny (like tasks-toml-block-human-assignee.sh): a dead model pin is a
# guaranteed dispatch failure and trivially recoverable (swap to gpt-5.5,
# re-apply), so it warrants a block rather than a soft reminder.

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

# Only fire when this edit introduces the dead model pin.
echo "$NEW_TEXT" | grep -qE 'model[[:space:]]*=[[:space:]]*"gpt-5-codex"' || emit_suppress

emit_deny \
"\`model = \"gpt-5-codex\"\` is a DEAD model pin — it is not in the codex catalog and is operator-blocked (unsupported on ChatGPT/subscription Codex accounts; requires a metered API account).

A per-task \`model\` pin overrides \`agent_model.codex\`, so this silently breaks dispatch: codex routing fails with \"unavailable\", and a claude-adapter dispatch fails with \"invalid_model_for_adapter\".

Fix: use a valid codex model — \`model = \"gpt-5.5\"\` (catalog: gpt-5.5 | gpt-5.4 | gpt-5.4-mini | gpt-5.3-codex-spark) — then re-apply." \
"dev-discipline: model = \"gpt-5-codex\" in tasks.toml is a dead/blocked model — use gpt-5.5"
