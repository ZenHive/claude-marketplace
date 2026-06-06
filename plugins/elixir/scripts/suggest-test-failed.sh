#!/bin/bash
# Suggest --failed --trace after repeated mix test calls
#
# Tracks consecutive mix test runs and suggests optimization when running
# the same tests repeatedly (likely fixing failing tests).

set -euo pipefail

STDIN=$(cat)
COMMAND=$(echo "$STDIN" | jq -r '.tool_input.command // empty')

# Only care about mix test commands
if ! echo "$COMMAND" | grep -qE '^\s*mix test'; then
  echo '{"suppressOutput": true}'
  exit 0
fi

# If already using --failed, reset tracking and suppress
if echo "$COMMAND" | grep -q -- '--failed'; then
  # Get project identifier
  PROJECT_HASH=$(echo "$PWD" | md5sum | cut -c1-8 2>/dev/null || echo "$PWD" | md5 | cut -c1-8)
  TRACKER_FILE="/tmp/mix_test_tracker_${PROJECT_HASH}"
  rm -f "$TRACKER_FILE" 2>/dev/null || true
  echo '{"suppressOutput": true}'
  exit 0
fi

# Get project identifier (hash of current directory)
if command -v md5sum &>/dev/null; then
  PROJECT_HASH=$(echo "$PWD" | md5sum | cut -c1-8)
else
  PROJECT_HASH=$(echo "$PWD" | md5 | cut -c1-8)
fi
TRACKER_FILE="/tmp/mix_test_tracker_${PROJECT_HASH}"

# Read current count and last run time
CURRENT_TIME=$(date +%s)
if [[ -f "$TRACKER_FILE" ]]; then
  # Format: count:timestamp
  TRACKER_DATA=$(cat "$TRACKER_FILE")
  COUNT=$(echo "$TRACKER_DATA" | cut -d: -f1)
  LAST_TIME=$(echo "$TRACKER_DATA" | cut -d: -f2)

  # Reset if more than 10 minutes since last test
  TIME_DIFF=$((CURRENT_TIME - LAST_TIME))
  if [[ $TIME_DIFF -gt 600 ]]; then
    COUNT=0
  fi
else
  COUNT=0
fi

# Increment count
COUNT=$((COUNT + 1))
echo "${COUNT}:${CURRENT_TIME}" > "$TRACKER_FILE"

# On 2+ consecutive calls, suggest optimization
if [[ $COUNT -ge 2 ]]; then
  jq -n --arg count "$COUNT" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "additionalContext": ("Tip: You'"'"'ve run `mix test` " + $count + " times consecutively. Consider:\n- `mix test --failed` - only runs previously failed tests\n- `mix test --failed --trace` - adds detailed output\n- `mix test --failed --seed 0` - deterministic order for debugging\n\nThis can significantly speed up your test-fix-test cycle.")
    }
  }'
else
  echo '{"suppressOutput": true}'
fi
