#!/usr/bin/env bash
# Roadmap CHANGELOG reminder hook
# Triggers when a roadmap file is edited and a task is marked complete
# Reminds Claude to move completed task details to CHANGELOG.md

set -euo pipefail

# Get the file path from tool input
TOOL_INPUT="${CLAUDE_TOOL_INPUT:-}"
if [[ -z "$TOOL_INPUT" ]]; then
  jq -n '{"suppressOutput": true}'
  exit 0
fi
FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path // .path // empty')

# If no file path, suppress output
if [[ -z "$FILE_PATH" ]]; then
  jq -n '{"suppressOutput": true}'
  exit 0
fi

# Check if file matches roadmap patterns:
# - ROADMAP.md (exact)
# - *roadmap.md (ends with roadmap.md, case insensitive)
# - .thoughts/plans/*
# - docs/*
is_roadmap_file() {
  local file="$1"
  local basename
  basename=$(basename "$file" | tr '[:upper:]' '[:lower:]')

  # Check exact match or ends with roadmap.md
  if [[ "$basename" == "roadmap.md" ]] || [[ "$basename" == *roadmap.md ]]; then
    return 0
  fi

  # Check path patterns
  if [[ "$file" == *".thoughts/plans/"* ]] || [[ "$file" == *"/docs/"* ]] || [[ "$file" == "docs/"* ]]; then
    return 0
  fi

  return 1
}

# Not a roadmap file, suppress output
if ! is_roadmap_file "$FILE_PATH"; then
  jq -n '{"suppressOutput": true}'
  exit 0
fi

# Check if we can detect a task being marked complete
# Look for the new_string containing "- [x]" pattern
NEW_STRING=$(echo "$TOOL_INPUT" | jq -r '.new_string // empty')

# For Write tool, check the content
if [[ -z "$NEW_STRING" ]]; then
  CONTENT=$(echo "$TOOL_INPUT" | jq -r '.content // empty')
  if [[ -n "$CONTENT" ]] && echo "$CONTENT" | grep -qE '^\s*-\s*\[x\]'; then
    # File has completed tasks, remind about maintenance
    jq -n '{
      "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": "📋 Roadmap file detected with completed tasks. Remember: Move completed task details to CHANGELOG.md and keep only a one-line reference in the roadmap (e.g., \"- [x] Task name — Done, see CHANGELOG\"). This prevents stale metrics from accumulating."
      }
    }'
    exit 0
  fi
fi

# For Edit tool, check if new_string marks a task complete
if [[ -n "$NEW_STRING" ]] && echo "$NEW_STRING" | grep -qE '^\s*-\s*\[x\]'; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PostToolUse",
      "additionalContext": "📋 Task marked complete in roadmap. Remember: Move the full task details to CHANGELOG.md and keep only a one-line reference here (e.g., \"- [x] Task name — Done, see CHANGELOG\"). Avoid leaving specific metrics (counts, percentages) that will become stale."
    }
  }'
  exit 0
fi

# Roadmap file but no completed task detected, suppress
jq -n '{"suppressOutput": true}'
exit 0
