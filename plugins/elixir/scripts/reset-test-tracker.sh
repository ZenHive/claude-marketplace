#!/bin/bash
# Reset mix test tracker when tests pass
#
# PostToolUse hook that clears the consecutive test counter
# when tests complete successfully (0 failures).

set -euo pipefail

STDIN=$(cat)
COMMAND=$(echo "$STDIN" | jq -r '.tool_input.command // empty')
STDOUT=$(echo "$STDIN" | jq -r '.tool_output.stdout // empty')

# Only care about mix test commands
if ! echo "$COMMAND" | grep -qE '^\s*mix test'; then
  echo '{"suppressOutput": true}'
  exit 0
fi

# Check if tests passed (look for "0 failures" in output)
if echo "$STDOUT" | grep -qE '0 failures'; then
  # Get project identifier
  if command -v md5sum &>/dev/null; then
    PROJECT_HASH=$(echo "$PWD" | md5sum | cut -c1-8)
  else
    PROJECT_HASH=$(echo "$PWD" | md5 | cut -c1-8)
  fi
  TRACKER_FILE="/tmp/mix_test_tracker_${PROJECT_HASH}"
  rm -f "$TRACKER_FILE" 2>/dev/null || true
fi

echo '{"suppressOutput": true}'
