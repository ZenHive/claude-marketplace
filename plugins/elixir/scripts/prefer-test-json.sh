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

# Check if this is a `mix test` command but NOT `mix test.json` or `mix test.something_else`
# Pattern: "mix test" optionally followed by space and args, but NOT followed by a dot
if ! echo "$COMMAND" | grep -qE 'mix\s+test(\s|$)'; then
  # Not a mix test command at all
  emit_suppress_json
  exit 0
fi

# Allow mix test.json and other mix test.* variants
if echo "$COMMAND" | grep -qE 'mix\s+test\.[a-z]'; then
  emit_suppress_json
  exit 0
fi

# Find Mix project root to confirm this is an Elixir project
PROJECT_ROOT=$(find_mix_project_root_from_dir "$HOOK_CWD") || {
  # Not in an Elixir project, allow the command
  emit_suppress_json
  exit 0
}

# Silently rewrite mix test → mix test.json, preserving any trailing args.
# BSD-portable: [[:space:]] (macOS sed -E does not support \s).
NEW_COMMAND=$(echo "$COMMAND" | sed -E 's/mix test([[:space:]]|$)/mix test.json\1/')

REASON="Rewrote to mix test.json for AI-friendly output. (If ex_unit_json is not installed, see https://hexdocs.pm/ex_unit_json.)"

echo "$HOOK_INPUT" | jq --arg new "$NEW_COMMAND" --arg reason "$REASON" '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": $reason,
    "updatedInput": ((.tool_input // {}) + {command: $new})
  }
}'
exit 0
