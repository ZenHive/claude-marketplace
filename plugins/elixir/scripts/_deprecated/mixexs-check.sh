#!/usr/bin/env bash
set -eo pipefail

# Read hook input from stdin
HOOK_INPUT=$(cat)
FILE_PATH=$(echo "$HOOK_INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')

# Only check mix.exs files
if [[ -z "$FILE_PATH" ]] || [[ "$FILE_PATH" != *"mix.exs" ]]; then
  jq -n '{"suppressOutput": true}'
  exit 0
fi

# Read the file
if [[ ! -f "$FILE_PATH" ]]; then
  jq -n '{"suppressOutput": true}'
  exit 0
fi

CONTENT=$(cat "$FILE_PATH")
WARNINGS=""

# Check for missing recommended deps
check_dep() {
  local dep=$1
  if ! echo "$CONTENT" | grep -qE "\{:${dep}"; then
    WARNINGS="${WARNINGS}- Missing {:${dep}, ...}\n"
  fi
}

check_dep "styler"
check_dep "credo"
check_dep "dialyxir"
check_dep "doctor"

# Check for common mistakes
# 1. Deps without runtime: false that should have it
for dep in styler credo dialyxir doctor sobelow ex_doc; do
  if echo "$CONTENT" | grep -qE "\{:${dep}" && ! echo "$CONTENT" | grep -qE "\{:${dep}[^}]*runtime:\s*false"; then
    WARNINGS="${WARNINGS}- {:${dep}} should have runtime: false\n"
  fi
done

# 2. Check if tidewave exists but bandit doesn't (non-Phoenix detection)
if echo "$CONTENT" | grep -qE '\{:tidewave' && ! echo "$CONTENT" | grep -qE '\{:phoenix\b' && ! echo "$CONTENT" | grep -qE '\{:bandit'; then
  WARNINGS="${WARNINGS}- Has :tidewave but missing :bandit (required for non-Phoenix projects)\n"
fi

if [[ -z "$WARNINGS" ]]; then
  jq -n '{"suppressOutput": true}'
  exit 0
fi

jq -n --arg warnings "$WARNINGS" '{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "mix.exs review:\n" + $warnings + "\nRun: mix deps.get after adding deps. See /elixir:elixir-setup for full setup guide."
  }
}'
exit 0
