#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/lib.sh"

# Read hook input from stdin
read_hook_input

COMMAND=$(echo "$HOOK_INPUT" | jq -r '.tool_input.command')
HOOK_CWD=$(echo "$HOOK_INPUT" | jq -r '.cwd')

# Skip if command is null or empty
is_null_or_empty "$COMMAND" && { emit_suppress_json; exit 0; }

# Check if this is a `mix dialyzer` command but NOT `mix dialyzer.json` or `mix dialyzer.something_else`
# Pattern: "mix dialyzer" optionally followed by space and args, but NOT followed by a dot
if ! echo "$COMMAND" | grep -qE 'mix\s+dialyzer(\s|$)'; then
  # Not a mix dialyzer command at all
  emit_suppress_json
  exit 0
fi

# Allow mix dialyzer.json and other mix dialyzer.* variants
if echo "$COMMAND" | grep -qE 'mix\s+dialyzer\.[a-z]'; then
  emit_suppress_json
  exit 0
fi

# Find Mix project root to confirm this is an Elixir project
PROJECT_ROOT=$(find_mix_project_root_from_dir "$HOOK_CWD") || {
  # Not in an Elixir project, allow the command
  emit_suppress_json
  exit 0
}

# Silently rewrite mix dialyzer → mix dialyzer.json, preserving any trailing args.
# BSD-portable: [[:space:]] (macOS sed -E does not support \s).
NEW_COMMAND=$(echo "$COMMAND" | sed -E 's/mix dialyzer([[:space:]]|$)/mix dialyzer.json\1/')

REASON="Rewrote to mix dialyzer.json for AI-friendly output. (If dialyzer_json is not installed, see https://hexdocs.pm/dialyzer_json.)"

echo "$HOOK_INPUT" | jq --arg new "$NEW_COMMAND" --arg reason "$REASON" '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": $reason,
    "updatedInput": ((.tool_input // {}) + {command: $new})
  }
}'
exit 0
