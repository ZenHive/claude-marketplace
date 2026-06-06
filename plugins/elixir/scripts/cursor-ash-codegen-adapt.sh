#!/usr/bin/env bash
# Cursor postToolUse adapter for Claude Code ash-codegen-check.sh
# Same stdin/stdout contract as cursor-post-edit-adapt.sh (see that file).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INNER_HOOK="$SCRIPT_DIR/ash-codegen-check.sh"

RAW_INPUT=$(cat)

CLAUDE_JSON=$(echo "$RAW_INPUT" | jq -c '
  (
    .tool_input.file_path //
    .tool_input.path //
    .tool_input.file //
    .file_path //
    ""
  ) as $fp |
  if ($fp == "") then
    { tool_input: { file_path: "" } }
  else
    { tool_input: { file_path: $fp } }
  end
')

FILE_PATH=$(echo "$CLAUDE_JSON" | jq -r '.tool_input.file_path')
if [[ -z "$FILE_PATH" || "$FILE_PATH" == "null" ]]; then
  echo '{}'
  exit 0
fi

INNER_OUT=""
INNER_OUT=$(echo "$CLAUDE_JSON" | "$INNER_HOOK")

if ! echo "$INNER_OUT" | jq -e . >/dev/null 2>&1; then
  echo '{}'
  exit 0
fi

echo "$INNER_OUT" | jq '
  if .suppressOutput == true then
    {}
  elif (.hookSpecificOutput.additionalContext | type) == "string" then
    { additional_context: .hookSpecificOutput.additionalContext }
  else
    {}
  end
'

exit 0
