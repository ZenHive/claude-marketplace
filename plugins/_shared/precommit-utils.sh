#!/usr/bin/env bash
# Pre-commit utilities for Claude Code plugin hooks
# Source this file after lib.sh for pre-commit hooks

# ============================================================================
# Pre-commit Detection
# ============================================================================

# Check if command is a git commit command
# Usage: is_git_commit_command "$command" || exit 0
is_git_commit_command() {
  local command="$1"
  echo "$command" | grep -qE 'git\b.*\bcommit\b'
}

# Check if project has precommit alias (Phoenix 1.8+ standard)
# If so, defer to it and suppress this hook's output
# Usage: defer_to_precommit "$project_root" && exit 0
defer_to_precommit() {
  local project_root="$1"
  cd "$project_root" && mix help precommit >/dev/null 2>&1
}

# ============================================================================
# Pre-commit JSON Output
# ============================================================================

# Emit deny JSON for blocking commits
# Usage: emit_deny_json "$reason" "$system_message"
emit_deny_json() {
  local reason="$1"
  local system_message="$2"

  jq -n \
    --arg reason "$reason" \
    --arg msg "$system_message" \
    '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": $reason
      },
      "systemMessage": $msg
    }'
}

# ============================================================================
# Pre-commit Workflow Helpers
# ============================================================================

# Standard pre-commit setup: parse input, check for git commit, find project
# Sets: PROJECT_ROOT
# Usage: precommit_setup || exit 0
#
# IMPORTANT: This function may call `exit 0` directly (not return) when the
# project has a precommit alias. This is intentional - it suppresses hook
# output and defers to the project's own precommit workflow. If you need
# different behavior, use the individual helper functions instead.
#
# Emits suppress JSON before returning 1 for skip cases (not git commit, no project).
precommit_setup() {
  read_hook_input
  if ! parse_precommit_input; then
    emit_suppress_json
    return 1
  fi

  if ! is_git_commit_command "$HOOK_COMMAND"; then
    emit_suppress_json
    return 1
  fi

  local git_dir
  git_dir=$(extract_git_dir "$HOOK_COMMAND" "$HOOK_CWD")

  if ! PROJECT_ROOT=$(find_mix_project_root_from_dir "$git_dir"); then
    emit_suppress_json
    return 1
  fi

  # Defer to precommit alias if it exists (exits directly, not returns)
  if defer_to_precommit "$PROJECT_ROOT"; then
    emit_suppress_json
    exit 0
  fi

  return 0
}

# Standard pre-commit setup that requires a specific dependency
# Sets: PROJECT_ROOT
# Usage: precommit_setup_with_dep "dialyxir" || exit 0
#
# Emits suppress JSON before returning 1 when dependency not found.
precommit_setup_with_dep() {
  local dep_name="$1"

  # precommit_setup already emits suppress JSON on failure
  precommit_setup || return 1

  if ! has_mix_dependency "$dep_name" "$PROJECT_ROOT"; then
    emit_suppress_json
    return 1
  fi

  return 0
}
