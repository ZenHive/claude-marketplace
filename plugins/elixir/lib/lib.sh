#!/usr/bin/env bash
# Shared library for Claude Code plugin hooks
# Source this file at the start of hook scripts
#
# NOTE: This library does NOT set shell options (set -eo pipefail).
# The sourcing script should set its own shell options as needed.
# This prevents the library from affecting the caller's error handling.

# ============================================================================
# Constants
# ============================================================================

readonly DEFAULT_MAX_LINES=30
readonly COMPILE_MAX_LINES=50

# ============================================================================
# Core Utilities
# ============================================================================

# Check if value is null or empty
# Usage: is_null_or_empty "$value" && exit 0
is_null_or_empty() {
  local value="$1"
  [[ -z "$value" ]] || [[ "$value" == "null" ]]
}

# Find Mix project root by traversing upward from a directory
# Usage: PROJECT_ROOT=$(find_mix_project_root_from_dir "$dir")
find_mix_project_root_from_dir() {
  local dir="$1"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/mix.exs" ]]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

# Find Mix project root by traversing upward from a file path
# Usage: PROJECT_ROOT=$(find_mix_project_root_from_file "$file_path")
find_mix_project_root_from_file() {
  local file_path="$1"
  local dir
  dir=$(dirname "$file_path")
  find_mix_project_root_from_dir "$dir"
}

# Check if a file has .ex or .exs extension
# Usage: is_elixir_file "$file_path" || exit 0
is_elixir_file() {
  local file_path="$1"
  echo "$file_path" | grep -qE '\.(ex|exs)$'
}

# Check if a dependency exists in mix.exs
# Usage: has_mix_dependency "dialyxir" "$project_root" || exit 0
has_mix_dependency() {
  local dep_name="$1"
  local project_root="$2"
  grep -qE "\{:${dep_name}" "$project_root/mix.exs" 2>/dev/null
}

# Truncate output to max lines with message
# Usage: OUTPUT=$(truncate_output "$raw_output" 30 "mix credo")
truncate_output() {
  local output="$1"
  local max_lines="${2:-$DEFAULT_MAX_LINES}"
  local command_hint="${3:-}"

  local total_lines
  total_lines=$(echo "$output" | wc -l | tr -d ' ')

  if [[ "$total_lines" -gt "$max_lines" ]]; then
    local truncated
    truncated=$(echo "$output" | head -n "$max_lines")

    if [[ -n "$command_hint" ]]; then
      echo "$truncated

[Output truncated: showing $max_lines of $total_lines lines]
Run '$command_hint' to see the full output."
    else
      echo "$truncated

[Output truncated: showing $max_lines of $total_lines lines]"
    fi
  else
    echo "$output"
  fi
}

# ============================================================================
# JSON Output Helpers
# ============================================================================

# Emit suppress output JSON
# Usage: emit_suppress_json
emit_suppress_json() {
  jq -n '{"suppressOutput": true}'
}

# ============================================================================
# Hook Input Parsing
# ============================================================================

# Global variables set by parse functions
HOOK_INPUT=""
HOOK_COMMAND=""
HOOK_CWD=""
HOOK_FILE_PATH=""

# Read hook input from stdin
# Usage: read_hook_input
read_hook_input() {
  HOOK_INPUT=$(cat) || exit 1
}

# Parse command from PreToolUse hook input
# Sets: HOOK_COMMAND, HOOK_CWD
# Usage: parse_precommit_input || exit 0
parse_precommit_input() {
  HOOK_COMMAND=$(echo "$HOOK_INPUT" | jq -e -r '.tool_input.command' 2>/dev/null) || exit 1
  HOOK_CWD=$(echo "$HOOK_INPUT" | jq -e -r '.cwd' 2>/dev/null) || exit 1

  is_null_or_empty "$HOOK_COMMAND" && return 1
  is_null_or_empty "$HOOK_CWD" && return 1
  return 0
}

# Parse file_path from PostToolUse hook input
# Sets: HOOK_FILE_PATH
# Usage: parse_postedit_input || exit 0
parse_postedit_input() {
  HOOK_FILE_PATH=$(echo "$HOOK_INPUT" | jq -e -r '.tool_input.file_path' 2>/dev/null) || exit 1

  is_null_or_empty "$HOOK_FILE_PATH" && return 1
  return 0
}

# Extract git directory from -C flag in command, or use CWD
# Usage: GIT_DIR=$(extract_git_dir "$command" "$cwd")
#
# Handles commands like: git -C /path/to/repo commit -m "msg"
# The sed pattern captures the path after "git -C " up to the next whitespace
extract_git_dir() {
  local command="$1"
  local cwd="$2"
  local git_dir="$cwd"

  # Check if command contains "git -C <path>" pattern
  if echo "$command" | grep -qE 'git\s+-C\s+'; then
    # Extract path: match "git" + whitespace + "-C" + whitespace + capture non-whitespace
    git_dir=$(echo "$command" | sed -n 's/.*git[[:space:]]*-C[[:space:]]*\([^[:space:]]*\).*/\1/p')
    # Fall back to cwd if extraction failed or path doesn't exist
    if is_null_or_empty "$git_dir" || [[ ! -d "$git_dir" ]]; then
      git_dir="$cwd"
    fi
  fi

  echo "$git_dir"
}

# Check if there are staged .ex or .exs files in the git repository
# Usage: has_staged_elixir_files "$project_root" || exit 0
has_staged_elixir_files() {
  local project_root="$1"
  git -C "$project_root" diff --cached --name-only 2>/dev/null | grep -qE '\.(ex|exs)$'
}

# ============================================================================
# Per-Hook Enable / Disable
# ============================================================================
#
# Every hook script has a "hook id": its basename without the .sh extension
# (e.g. pre-commit-unified). A single hook can be switched off without
# disabling the whole plugin in `enabledPlugins`.
#
# Resolution order, first match wins:
#   1. ZENHIVE_HOOKS_ENABLED   env — force ON  (overrides a config file)
#   2. ZENHIVE_HOOKS_DISABLED  env — force OFF
#   3. <repo>/.claude/zenhive-hooks.json
#   4. ~/.claude/zenhive-hooks.json
#   5. default: ON
#
# Both env vars hold a comma- or space-separated list of hook ids; "*" matches
# every hook. Config files are a flat JSON map of hook id -> bool, where the
# key "*" sets the default for unlisted hooks:
#
#   { "*": true, "pre-commit-unified": false }

# Check whether a hook id appears in a comma/space-separated list ("*" = all)
# Usage: hook_list_matches "$ZENHIVE_HOOKS_DISABLED" "pre-commit-unified"
hook_list_matches() {
  local list="$1"
  local hook_id="$2"
  local entry
  local -a entries=()

  [[ -z "$list" ]] && return 1

  # `read -a` splits on IFS without pathname expansion — an unquoted
  # for-loop over the list would glob-expand a "*" entry into filenames.
  IFS=', ' read -r -a entries <<< "$list"

  for entry in "${entries[@]}"; do
    [[ "$entry" == "*" || "$entry" == "$hook_id" ]] && return 0
  done
  return 1
}

# Look a hook id up in a config file
# Echoes "true" / "false", or nothing when the hook is not configured.
# Usage: value=$(hook_config_lookup "$file" "pre-commit-unified")
#
# NOTE: uses `has` rather than jq's `//` operator — `false // x` yields x,
# which would make an explicit `false` fall through to the "*" default.
hook_config_lookup() {
  local file="$1"
  local hook_id="$2"

  [[ -f "$file" ]] || return 0

  jq -r --arg id "$hook_id" '
    if type != "object" then empty
    elif has($id) then .[$id]
    elif has("*") then .["*"]
    else empty
    end | tostring
  ' "$file" 2>/dev/null
}

# Check whether a hook is enabled
# Usage: hook_enabled "pre-commit-unified" "$HOOK_CWD" || { emit_suppress_json; exit 0; }
hook_enabled() {
  local hook_id="$1"
  local repo_dir="${2:-${CLAUDE_PROJECT_DIR:-$PWD}}"
  local file value

  hook_list_matches "${ZENHIVE_HOOKS_ENABLED:-}" "$hook_id" && return 0
  hook_list_matches "${ZENHIVE_HOOKS_DISABLED:-}" "$hook_id" && return 1

  for file in "$repo_dir/.claude/zenhive-hooks.json" "$HOME/.claude/zenhive-hooks.json"; do
    value=$(hook_config_lookup "$file" "$hook_id")
    if [[ -n "$value" ]]; then
      [[ "$value" == "true" ]]
      return
    fi
  done

  return 0
}
