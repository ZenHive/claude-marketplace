#!/usr/bin/env bash
# PreToolUse:Edit|Write|MultiEdit — soft reminder when about to add a new
# [[task]] block to a roadmap/tasks.toml file via direct edit (bypassing
# `rmap new`). Closes the workaround corridor for the rmap-new-pause hook.
#
# Fires on: Edit/Write/MultiEdit whose target is */roadmap/tasks.toml AND
# whose new content introduces a `[[task]]` block not present before.
# Silent on: status flips, marker toggles, body edits, non-tasks.toml files.

set -eo pipefail

emit_suppress() { jq -n '{"suppressOutput": true}'; exit 0; }

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[[ -z "$FILE" || "$FILE" == "null" ]] && emit_suppress

# Only fire on roadmap/tasks.toml (any depth)
case "$FILE" in
  */roadmap/tasks.toml) ;;
  *) emit_suppress ;;
esac

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
TASK_HEADER='^\[\[task\]\]'

# Count `[[task]]` headers in a multi-line string.
count_task_headers() {
  echo "$1" | grep -cE "$TASK_HEADER" || true
}

case "$TOOL_NAME" in
  Write)
    NEW_CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')
    if [[ -f "$FILE" ]]; then
      OLD_COUNT=$(grep -cE "$TASK_HEADER" "$FILE" 2>/dev/null || echo 0)
    else
      OLD_COUNT=0
    fi
    NEW_COUNT=$(count_task_headers "$NEW_CONTENT")
    [[ "$NEW_COUNT" -gt "$OLD_COUNT" ]] || emit_suppress
    ;;
  Edit)
    OLD_STRING=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty')
    NEW_STRING=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty')
    OLD_HITS=$(count_task_headers "$OLD_STRING")
    NEW_HITS=$(count_task_headers "$NEW_STRING")
    [[ "$NEW_HITS" -gt "$OLD_HITS" ]] || emit_suppress
    ;;
  MultiEdit)
    EDITS=$(echo "$INPUT" | jq -c '.tool_input.edits // []')
    ADDS=0
    while IFS= read -r EDIT; do
      [[ -z "$EDIT" ]] && continue
      O=$(count_task_headers "$(echo "$EDIT" | jq -r '.old_string // ""')")
      N=$(count_task_headers "$(echo "$EDIT" | jq -r '.new_string // ""')")
      [[ "$N" -gt "$O" ]] && ADDS=1
    done < <(echo "$EDITS" | jq -c '.[]')
    [[ "$ADDS" -eq 1 ]] || emit_suppress
    ;;
  *)
    emit_suppress
    ;;
esac

MESSAGE="🪝 tasks.toml new-task gate — pause and pick.

About to add a [[task]] block via direct edit. Same question as
rmap-new-pause:

Cross-session or cross-repo work → file the task.
In-scope finding that fits the current commit → fix inline, don't file.
Same-PR follow-up → push back / amend the staged set, don't file.

Direct TOML edits bypass the rmap-new Bash matcher, so this hook closes
the workaround corridor. The decision criterion is identical.

If you've answered 'yes, this is cross-session / cross-repo' — proceed."

jq -n --arg ctx "$MESSAGE" '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": $ctx
  }
}'
