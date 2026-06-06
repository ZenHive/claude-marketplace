#!/usr/bin/env bash
set -eo pipefail

# Read hook input from stdin
HOOK_INPUT=$(cat)
COMMAND=$(echo "$HOOK_INPUT" | jq -r '.tool_input.command')

# Only check mix phx.new commands
if ! echo "$COMMAND" | grep -qE 'mix\s+phx\.new'; then
  jq -n '{"suppressOutput": true}'
  exit 0
fi

# Check for --live flag
if ! echo "$COMMAND" | grep -qE '\-\-live'; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": "BLOCKED: Missing --live flag!\n\nAlways use: mix phx.new <name> --live\n\nWithout --live, auth scoping is incomplete and future phx.gen.live commands won'\''t be user-scoped. This creates security vulnerabilities.\n\nSee: elixir-setup.md include or /elixir:elixir-setup skill for setup guidance."
    }
  }'
  exit 0
fi

# --live present, show setup checklist
jq -n '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "Phoenix project with --live flag. After creation, add recommended deps to mix.exs:\n\n{:styler, \"~> 1.9\", only: [:dev, :test], runtime: false}\n{:credo, \"~> 1.7\", only: [:dev, :test], runtime: false}\n{:dialyxir, \"~> 1.4\", only: [:dev, :test], runtime: false}\n{:doctor, \"~> 0.21\", only: [:dev, :test], runtime: false}\n{:sobelow, \"~> 0.13\", only: [:dev, :test], runtime: false}\n{:tidewave, \"~> 0.5\", only: :dev}\n{:live_debugger, \"~> 0.5\", only: :dev}\n\nThen configure .formatter.exs with Styler and Tidewave endpoint plug."
  }
}'
exit 0
