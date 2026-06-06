#!/usr/bin/env bash

# Check that public functions have @spec
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

# Find public functions missing @spec
# Strategy: Find all def lines, then check what's above them

WARNINGS=""
LINE_NUM=0
PREV_LINE=""
PREV_PREV_LINE=""
PREV_PREV_PREV_LINE=""
PREV_PREV_PREV_PREV_LINE=""
PREV_PREV_PREV_PREV_PREV_LINE=""
SEEN_FUNCS=""  # Track seen functions to skip multi-clause definitions

while IFS= read -r line || [[ -n "$line" ]]; do
  ((LINE_NUM++))

  # Check if this line starts a def (public function, not defp)
  # Matches: def foo(, def foo?(, def foo!(
  # Negative lookahead: must not be defp, defmacro, defmodule, defstruct, etc.
  if echo "$line" | grep -qE '^\s*def\s+[a-z_][a-z0-9_?!]*[(]'; then
    # Skip defp, defmacro, defmodule, defstruct, defguard, defdelegate
    if echo "$line" | grep -qE '^\s*def(p|macro|module|struct|guard|delegate|impl|exception|protocol|overridable)\s'; then
      continue
    fi

    # Extract function name
    FUNC_NAME=$(echo "$line" | grep -oE 'def[[:space:]]+[a-z_][a-z0-9_?!]*' | sed 's/def[[:space:]]*//')

    # Skip if we already processed this function (multi-clause definitions)
    if echo "$SEEN_FUNCS" | grep -qF "|${FUNC_NAME}|"; then
      continue
    fi
    SEEN_FUNCS="${SEEN_FUNCS}|${FUNC_NAME}|"

    # Check for @impl true in previous lines (callback implementation)
    # If @impl is present, function gets its spec from the behaviour's @callback
    HAS_IMPL=false
    if echo "$PREV_LINE" | grep -qE '^\s*@impl\s+(true|[A-Z])'; then
      HAS_IMPL=true
    elif echo "$PREV_PREV_LINE" | grep -qE '^\s*@impl\s+(true|[A-Z])'; then
      HAS_IMPL=true
    elif echo "$PREV_PREV_PREV_LINE" | grep -qE '^\s*@impl\s+(true|[A-Z])'; then
      HAS_IMPL=true
    fi

    # Skip callback implementations - they use @callback from the behaviour
    if [[ "$HAS_IMPL" == "true" ]]; then
      continue
    fi

    # Check for @spec in previous lines (up to 5 lines back for multi-line specs)
    # The @spec should contain the function name
    HAS_SPEC=false
    if echo "$PREV_LINE" | grep -qE "^\s*@spec\s+${FUNC_NAME}[^a-z0-9_]"; then
      HAS_SPEC=true
    elif echo "$PREV_PREV_LINE" | grep -qE "^\s*@spec\s+${FUNC_NAME}[^a-z0-9_]"; then
      HAS_SPEC=true
    elif echo "$PREV_PREV_PREV_LINE" | grep -qE "^\s*@spec\s+${FUNC_NAME}[^a-z0-9_]"; then
      HAS_SPEC=true
    elif echo "$PREV_PREV_PREV_PREV_LINE" | grep -qE "^\s*@spec\s+${FUNC_NAME}[^a-z0-9_]"; then
      HAS_SPEC=true
    elif echo "$PREV_PREV_PREV_PREV_PREV_LINE" | grep -qE "^\s*@spec\s+${FUNC_NAME}[^a-z0-9_]"; then
      HAS_SPEC=true
    fi

    # Build warning message
    if [[ "$HAS_SPEC" == "false" ]]; then
      WARNINGS="${WARNINGS}Line ${LINE_NUM}: def ${FUNC_NAME} is missing @spec\n"
    fi
  fi

  # Shift previous lines (5-line lookback for multi-line specs)
  PREV_PREV_PREV_PREV_PREV_LINE="$PREV_PREV_PREV_PREV_LINE"
  PREV_PREV_PREV_PREV_LINE="$PREV_PREV_PREV_LINE"
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
OUTPUT="Typespec check for ${BASENAME}:

$(echo -e "$WARNINGS")
Convention: Public functions should have @spec for Dialyzer and documentation.
Exception: Callback implementations (@impl true) use @callback from the behaviour."

# Output JSON with additionalContext (non-blocking warning)
jq -n --arg ctx "$OUTPUT" '{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": $ctx
  }
}'

exit 0
