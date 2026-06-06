#!/usr/bin/env bash
# Post-edit utilities for Claude Code plugin hooks
# Source this file after lib.sh for post-edit hooks

# ============================================================================
# Post-edit JSON Output
# ============================================================================

# Emit context JSON for non-blocking feedback
# Usage: emit_context_json "$context"
emit_context_json() {
  local context="$1"

  jq -n \
    --arg context "$context" \
    '{
      "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": $context
      }
    }'
}

# Emit context JSON with a title header for cleaner output
# Usage: emit_context_json_with_title "Credo Analysis" "$output"
emit_context_json_with_title() {
  local title="$1"
  local context="$2"
  local formatted

  formatted=$(printf "=== %s ===\n%s" "$title" "$context")
  emit_context_json "$formatted"
}

# ============================================================================
# Post-edit Workflow Helpers
# ============================================================================

# Standard post-edit setup for Elixir files: parse input, check extension, find project
# Sets: PROJECT_ROOT, HOOK_FILE_PATH
# Usage: postedit_setup || exit 0
postedit_setup() {
  read_hook_input
  parse_postedit_input || return 1

  is_elixir_file "$HOOK_FILE_PATH" || return 1

  PROJECT_ROOT=$(find_mix_project_root_from_file "$HOOK_FILE_PATH") || return 1

  return 0
}

# Standard post-edit setup that requires a specific dependency
# Sets: PROJECT_ROOT, HOOK_FILE_PATH
# Usage: postedit_setup_with_dep "credo" || exit 0
postedit_setup_with_dep() {
  local dep_name="$1"

  postedit_setup || return 1

  has_mix_dependency "$dep_name" "$PROJECT_ROOT" || return 1

  return 0
}
