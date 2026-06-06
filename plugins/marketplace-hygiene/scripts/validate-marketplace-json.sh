#!/usr/bin/env bash
# PostToolUse hook: after Edit|Write|MultiEdit on any marketplace.json,
# plugin.json, or hooks.json, run `jq -e .` to catch JSON parse errors
# immediately instead of waiting for marketplace load to fail.
#
# Matches by basename only — works for `.claude-plugin/marketplace.json`,
# `plugins/*/.claude-plugin/plugin.json`, `plugins/*/hooks/hooks.json`, and
# any other JSON manifest with one of those three names anywhere in the tree.

set -eo pipefail

emit_suppress() { jq -n '{"suppressOutput": true}'; exit 0; }

emit_context() {
  local title="$1"
  local body="$2"
  jq -n --arg ctx "=== $title ===
$body" '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $ctx
    }
  }'
  exit 0
}

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[[ -z "$FILE" || "$FILE" == "null" ]] && emit_suppress

BASENAME=$(basename "$FILE")
case "$BASENAME" in
  marketplace.json|plugin.json|hooks.json) ;;
  *) emit_suppress ;;
esac

[[ ! -f "$FILE" ]] && emit_suppress

if ! JQ_ERR=$(jq -e . "$FILE" 2>&1 >/dev/null); then
  # jq parse failure: stderr captured in JQ_ERR, surface it.
  emit_context "Invalid JSON in $BASENAME" "jq could not parse $FILE after this edit. The marketplace will fail to load until this is fixed.

jq error:
$JQ_ERR"
fi

# Parse succeeded; nothing to surface.
emit_suppress
