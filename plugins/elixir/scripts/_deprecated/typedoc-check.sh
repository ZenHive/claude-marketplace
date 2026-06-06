#!/usr/bin/env bash

# Check that type definitions have @typedoc
# Non-blocking warning - provides context to Claude

# Read and validate stdin
INPUT=$(cat) || exit 1

# Extract file_path with error handling
FILE_PATH=$(echo "$INPUT" | jq -e -r '.tool_input.file_path' 2>/dev/null) || exit 1

# Validate extracted value is not null
if [[ -z "$FILE_PATH" ]] || [[ "$FILE_PATH" == "null" ]]; then
  exit 0
fi

# Only process .ex files (not test files .exs)
if ! echo "$FILE_PATH" | grep -qE '\.ex$'; then
  jq -n '{"suppressOutput": true}'
  exit 0
fi

# Skip test directories
if echo "$FILE_PATH" | grep -qE '(/test/|_test\.ex$)'; then
  jq -n '{"suppressOutput": true}'
  exit 0
fi

# Check if file exists
if [[ ! -f "$FILE_PATH" ]]; then
  jq -n '{"suppressOutput": true}'
  exit 0
fi

# Find type definitions missing @typedoc
# Strategy: Find all @type/@typep/@opaque lines, then check what's above them

WARNINGS=""
LINE_NUM=0
PREV_LINE=""
PREV_PREV_LINE=""
PREV_PREV_PREV_LINE=""

while IFS= read -r line || [[ -n "$line" ]]; do
  ((LINE_NUM++))

  # Check if this line is a type definition
  # Matches: @type name ::, @typep name ::, @opaque name ::
  if echo "$line" | grep -qE '^\s*@(type|typep|opaque)\s+[a-z_][a-z0-9_]*\s*::'; then

    # Extract type kind and name
    TYPE_KIND=$(echo "$line" | grep -oE '@(type|typep|opaque)' | head -1 | sed 's/@//')
    TYPE_NAME=$(echo "$line" | sed -E 's/.*@(type|typep|opaque)[[:space:]]+([a-z_][a-z0-9_]*).*/\2/')

    # Check for @typedoc in previous lines (up to 3 lines back)
    HAS_TYPEDOC=false
    if echo "$PREV_LINE" | grep -qE '^\s*@typedoc\s'; then
      HAS_TYPEDOC=true
    elif echo "$PREV_PREV_LINE" | grep -qE '^\s*@typedoc\s'; then
      HAS_TYPEDOC=true
    elif echo "$PREV_PREV_PREV_LINE" | grep -qE '^\s*@typedoc\s'; then
      HAS_TYPEDOC=true
    fi

    # Also check for multi-line @typedoc with heredoc (""")
    # If we see @typedoc """ the actual doc might be several lines
    if echo "$PREV_LINE" | grep -qE '^\s*"""'; then
      # Previous line ends a heredoc, check further back
      if echo "$PREV_PREV_LINE" | grep -qE '^\s*@typedoc\s'; then
        HAS_TYPEDOC=true
      elif echo "$PREV_PREV_PREV_LINE" | grep -qE '^\s*@typedoc\s'; then
        HAS_TYPEDOC=true
      fi
    fi

    # Build warning message
    if [[ "$HAS_TYPEDOC" == "false" ]]; then
      WARNINGS="${WARNINGS}Line ${LINE_NUM}: @${TYPE_KIND} ${TYPE_NAME} is missing @typedoc\n"
    fi
  fi

  # Shift previous lines
  PREV_PREV_PREV_LINE="$PREV_PREV_LINE"
  PREV_PREV_LINE="$PREV_LINE"
  PREV_LINE="$line"

done < "$FILE_PATH"

# If no warnings, suppress output
if [[ -z "$WARNINGS" ]]; then
  jq -n '{"suppressOutput": true}'
  exit 0
fi

# Format output for Claude
BASENAME=$(basename "$FILE_PATH")
OUTPUT="Typedoc check for ${BASENAME}:

$(echo -e "$WARNINGS")
Convention: Type definitions (@type, @typep, @opaque) should have @typedoc explaining the type's purpose and structure."

# Output JSON with additionalContext (non-blocking warning)
jq -n --arg ctx "$OUTPUT" '{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": $ctx
  }
}'

exit 0
