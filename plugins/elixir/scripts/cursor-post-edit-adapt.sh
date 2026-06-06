#!/usr/bin/env bash
# Cursor postToolUse adapter for Claude Code post-edit-check.sh
# - stdin: Cursor hook JSON (see https://cursor.com/docs/hooks — postToolUse)
# - transforms to Claude-shaped { tool_input: { file_path } } and pipes to post-edit-check.sh
# - stdout: Cursor JSON { additional_context?: string } or {} (suppress / no-op)
#
# Install: reference this script from ~/.cursor/hooks.json or <repo>/.cursor/hooks.json
# under "postToolUse" with matcher "Write|TabWrite" and a sufficient timeout (60s).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INNER_HOOK="$SCRIPT_DIR/post-edit-check.sh"

RAW_INPUT=$(cat)

# Cursor may send file_path under tool_input (same as Claude) or alternate keys.
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
