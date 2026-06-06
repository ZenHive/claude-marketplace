#!/usr/bin/env bash

# Check that private functions have @doc false and explanatory comments
# Non-blocking warning - provides context to Claude
#
# Handles Phoenix functional components which have attr/slot declarations
# between @doc false and defp:
#   @doc false
#   # Renders a toolbar
#   attr :search, :string, required: true
#   slot :inner_block
#   defp toolbar(assigns) do

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

# Read file into array for backward searching
mapfile -t LINES < "$FILE_PATH"
TOTAL_LINES=${#LINES[@]}

# Find private functions missing @doc false or comments
# Strategy: Find all defp lines, then search backward skipping attr/slot/blank

WARNINGS=""
SEEN_FUNCS=""  # Track seen functions to skip multi-clause definitions

for ((i=0; i<TOTAL_LINES; i++)); do
  line="${LINES[$i]}"
  LINE_NUM=$((i + 1))  # 1-indexed for user display

  # Check if this line starts a defp (not inside a string or comment)
  # Matches: defp foo(, defp foo?(, defp foo!(
  if echo "$line" | grep -qE '^\s*defp\s+[a-z_][a-z0-9_?!]*[(]'; then

    # Check if it's a one-liner (has ", do:" on same line)
    IS_ONE_LINER=false
    if echo "$line" | grep -qE ',\s*do:'; then
      IS_ONE_LINER=true
    fi

    # Extract function name for clearer warning
    FUNC_NAME=$(echo "$line" | grep -oE 'defp[[:space:]]+[a-z_][a-z0-9_?!]*' | sed 's/defp[[:space:]]*//')

    # Skip if we already processed this function (multi-clause definitions)
    # Only the first clause needs @doc false and comment
    if echo "$SEEN_FUNCS" | grep -qF "|${FUNC_NAME}|"; then
      continue
    fi
    SEEN_FUNCS="${SEEN_FUNCS}|${FUNC_NAME}|"

    # Search backward, skipping attr/slot declarations and blank lines
    # to find @doc false and comments
    HAS_DOC_FALSE=false
    HAS_COMMENT=false
    DOC_BLOCK_LINES=()  # Collect lines that are part of the doc block

    j=$((i - 1))
    while ((j >= 0)); do
      prev_line="${LINES[$j]}"

      # Skip blank lines
      if echo "$prev_line" | grep -qE '^\s*$'; then
        ((j--))
        continue
      fi

      # Skip attr declarations: attr :name, :type or attr :name, :type, opts
      if echo "$prev_line" | grep -qE '^\s*attr\s+:[a-z_][a-z0-9_]*\s*,'; then
        ((j--))
        continue
      fi

      # Skip slot declarations: slot :name or slot :name, opts
      if echo "$prev_line" | grep -qE '^\s*slot\s+:[a-z_][a-z0-9_]*'; then
        ((j--))
        continue
      fi

      # Found a non-attr/slot/blank line - this is part of doc block
      DOC_BLOCK_LINES+=("$prev_line")

      # Check for @doc false
      if echo "$prev_line" | grep -qE '^\s*@doc\s+false'; then
        HAS_DOC_FALSE=true
      fi

      # Check for comment
      if echo "$prev_line" | grep -qE '^\s*#'; then
        HAS_COMMENT=true
      fi

      # Stop after collecting 3 doc block lines (enough context)
      if ((${#DOC_BLOCK_LINES[@]} >= 3)); then
        break
      fi

      ((j--))
    done

    # Build warning message
    if [[ "$HAS_DOC_FALSE" == "false" ]]; then
      WARNINGS="${WARNINGS}Line ${LINE_NUM}: defp ${FUNC_NAME} is missing @doc false\n"
    fi

    # Only warn about missing comment for non-one-liners
    if [[ "$IS_ONE_LINER" == "false" ]] && [[ "$HAS_COMMENT" == "false" ]]; then
      WARNINGS="${WARNINGS}Line ${LINE_NUM}: defp ${FUNC_NAME} is missing explanatory comment\n"
    fi
  fi
done

# If no warnings, suppress output
if [[ -z "$WARNINGS" ]]; then
  jq -n '{"suppressOutput": true}'
  exit 0
fi

# Format output for Claude
BASENAME=$(basename "$FILE_PATH")
OUTPUT="Private function documentation check for ${BASENAME}:

$(echo -e "$WARNINGS")
Convention: Private functions should have @doc false and an explanatory comment above.
Exception: Trivial one-liners don't need comments."

# Output JSON with additionalContext (non-blocking warning)
jq -n --arg ctx "$OUTPUT" '{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": $ctx
  }
}'

exit 0
