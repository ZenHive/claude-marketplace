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
