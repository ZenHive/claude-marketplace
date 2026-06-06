#!/usr/bin/env bash
# Test script for shared library functions

# shellcheck source=./lib.sh
# shellcheck source=./precommit-utils.sh
# shellcheck source=./postedit-utils.sh

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
source "$SCRIPT_DIR/precommit-utils.sh"
source "$SCRIPT_DIR/postedit-utils.sh"

PASS=0
FAIL=0

pass() {
  echo "  ✓ $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  ✗ $1"
  FAIL=$((FAIL + 1))
}

echo "Testing lib.sh..."
echo ""

# Test is_null_or_empty
echo "is_null_or_empty:"
is_null_or_empty "" && pass "empty string" || fail "empty string"
is_null_or_empty "null" && pass "null string" || fail "null string"
is_null_or_empty "value" && fail "non-empty value should return false" || pass "non-empty value"

# Test find_mix_project_root_from_dir
echo ""
echo "find_mix_project_root_from_dir:"
# Test with a known mix project (this repo's test fixtures)
TEST_DIR="$SCRIPT_DIR/../../test/plugins/elixir/autoformat-test"
if [[ -d "$TEST_DIR" ]]; then
  RESULT=$(find_mix_project_root_from_dir "$TEST_DIR")
  if [[ "$RESULT" == "$TEST_DIR" ]] || [[ -f "$RESULT/mix.exs" ]]; then
    pass "finds project root from test dir"
  else
    fail "finds project root from test dir (got: $RESULT)"
  fi
else
  echo "  - skipped (test dir not found)"
fi

# Test with non-project directory
RESULT=$(find_mix_project_root_from_dir "/tmp" 2>/dev/null) && fail "should fail for /tmp" || pass "returns error for non-project"

# Test find_mix_project_root_from_file
echo ""
echo "find_mix_project_root_from_file:"
TEST_FILE="$SCRIPT_DIR/../../test/plugins/elixir/autoformat-test/lib/test.ex"
if [[ -f "$TEST_FILE" ]]; then
  RESULT=$(find_mix_project_root_from_file "$TEST_FILE")
  if [[ -f "$RESULT/mix.exs" ]]; then
    pass "finds project root from file path"
  else
    fail "finds project root from file path (got: $RESULT)"
  fi
else
  # Create a temp test case
  TEMP_DIR=$(mktemp -d)
  mkdir -p "$TEMP_DIR/lib"
  echo 'defmodule Test do end' > "$TEMP_DIR/lib/test.ex"
  echo 'defmodule TestProject.MixProject do end' > "$TEMP_DIR/mix.exs"
  RESULT=$(find_mix_project_root_from_file "$TEMP_DIR/lib/test.ex")
  if [[ "$RESULT" == "$TEMP_DIR" ]]; then
    pass "finds project root from file path (temp)"
  else
    fail "finds project root from file path (got: $RESULT)"
  fi
  rm -rf "$TEMP_DIR"
fi

# Test is_elixir_file
echo ""
echo "is_elixir_file:"
is_elixir_file "test.ex" && pass "test.ex" || fail "test.ex"
is_elixir_file "test.exs" && pass "test.exs" || fail "test.exs"
is_elixir_file "/path/to/file.ex" && pass "/path/to/file.ex" || fail "/path/to/file.ex"
is_elixir_file "test.js" && fail "test.js should return false" || pass "test.js"
is_elixir_file "test.py" && fail "test.py should return false" || pass "test.py"

# Test truncate_output
echo ""
echo "truncate_output:"
SHORT_OUTPUT="line1
line2
line3"
RESULT=$(truncate_output "$SHORT_OUTPUT" 5)
if [[ "$RESULT" == "$SHORT_OUTPUT" ]]; then
  pass "short output unchanged"
else
  fail "short output unchanged"
fi

LONG_OUTPUT=$(seq 1 50 | tr '\n' ' ' | sed 's/ /\n/g')
RESULT=$(truncate_output "$LONG_OUTPUT" 10 "test command")
if echo "$RESULT" | grep -q "Output truncated"; then
  pass "long output truncated"
else
  fail "long output truncated"
fi

# Test emit_suppress_json
echo ""
echo "emit_suppress_json:"
RESULT=$(emit_suppress_json)
if echo "$RESULT" | jq -e '.suppressOutput == true' > /dev/null 2>&1; then
  pass "valid suppress JSON"
else
  fail "valid suppress JSON"
fi

# Test extract_git_dir
echo ""
echo "extract_git_dir:"
RESULT=$(extract_git_dir "git commit -m 'test'" "/home/user")
if [[ "$RESULT" == "/home/user" ]]; then
  pass "no -C flag uses cwd"
else
  fail "no -C flag uses cwd (got: $RESULT)"
fi

# Use /tmp which exists on all systems
RESULT=$(extract_git_dir "git -C /tmp commit -m 'test'" "/home/user")
if [[ "$RESULT" == "/tmp" ]]; then
  pass "extracts -C flag path"
else
  fail "extracts -C flag path (got: $RESULT)"
fi

# Test with non-existent path (should fall back to cwd)
RESULT=$(extract_git_dir "git -C /nonexistent/path commit -m 'test'" "/home/user")
if [[ "$RESULT" == "/home/user" ]]; then
  pass "falls back to cwd for non-existent -C path"
else
  fail "falls back to cwd for non-existent -C path (got: $RESULT)"
fi

# Test is_git_commit_command
echo ""
echo "Testing precommit-utils.sh..."
echo ""
echo "is_git_commit_command:"
is_git_commit_command "git commit -m 'test'" && pass "git commit" || fail "git commit"
is_git_commit_command "git -C /path commit -m 'test'" && pass "git -C commit" || fail "git -C commit"
is_git_commit_command "git status" && fail "git status should return false" || pass "git status"
is_git_commit_command "git push" && fail "git push should return false" || pass "git push"

# Test emit_deny_json
echo ""
echo "emit_deny_json:"
RESULT=$(emit_deny_json "Test reason" "Test message")
if echo "$RESULT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' > /dev/null 2>&1; then
  pass "valid deny JSON structure"
else
  fail "valid deny JSON structure"
fi

# Test emit_context_json
echo ""
echo "Testing postedit-utils.sh..."
echo ""
echo "emit_context_json:"
RESULT=$(emit_context_json "Test context")
if echo "$RESULT" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"' > /dev/null 2>&1; then
  pass "valid context JSON structure"
else
  fail "valid context JSON structure"
fi

# Test emit_context_json_with_title
echo ""
echo "emit_context_json_with_title:"
RESULT=$(emit_context_json_with_title "Test Title" "Test content")
if echo "$RESULT" | jq -e '.hookSpecificOutput.additionalContext | contains("=== Test Title ===")' > /dev/null 2>&1; then
  pass "includes title header"
else
  fail "includes title header"
fi
if echo "$RESULT" | jq -e '.hookSpecificOutput.additionalContext | contains("Test content")' > /dev/null 2>&1; then
  pass "includes content"
else
  fail "includes content"
fi

# Test workflow helpers with simulated input
echo ""
echo "Workflow helpers (simulated stdin):"

# Create a temp Mix project for workflow tests
TEMP_PROJECT=$(mktemp -d)
echo 'defmodule TestProject.MixProject do
  use Mix.Project
  def project do
    [app: :test_project, version: "0.1.0"]
  end
end' > "$TEMP_PROJECT/mix.exs"
mkdir -p "$TEMP_PROJECT/lib"
echo 'defmodule Test do end' > "$TEMP_PROJECT/lib/test.ex"

# Initialize git repo for has_staged_elixir_files tests
git -C "$TEMP_PROJECT" init -q
git -C "$TEMP_PROJECT" config user.email "test@test.com"
git -C "$TEMP_PROJECT" config user.name "Test"

# Test has_staged_elixir_files
echo ""
echo "has_staged_elixir_files:"
# No staged files initially
has_staged_elixir_files "$TEMP_PROJECT" && fail "should return false with no staged files" || pass "no staged files"

# Stage an Elixir file
git -C "$TEMP_PROJECT" add lib/test.ex
has_staged_elixir_files "$TEMP_PROJECT" && pass "detects staged .ex file" || fail "detects staged .ex file"

# Unstage and stage a non-Elixir file
git -C "$TEMP_PROJECT" rm --cached -q lib/test.ex
echo "test" > "$TEMP_PROJECT/README.md"
git -C "$TEMP_PROJECT" add README.md
has_staged_elixir_files "$TEMP_PROJECT" && fail "should return false with only non-Elixir staged" || pass "ignores non-Elixir staged files"

# Unstage for other tests
git -C "$TEMP_PROJECT" rm --cached -q README.md 2>/dev/null || true

# Test precommit_setup with valid git commit
test_precommit_setup() {
  local json='{"tool_input":{"command":"git commit -m test"},"cwd":"'"$TEMP_PROJECT"'"}'
  HOOK_INPUT="$json"
  parse_precommit_input || return 1
  is_git_commit_command "$HOOK_COMMAND" || return 1
  local git_dir
  git_dir=$(extract_git_dir "$HOOK_COMMAND" "$HOOK_CWD")
  PROJECT_ROOT=$(find_mix_project_root_from_dir "$git_dir") || return 1
  return 0
}

if test_precommit_setup; then
  pass "precommit_setup with valid commit"
else
  fail "precommit_setup with valid commit"
fi

# Test precommit_setup rejects non-commit commands
test_precommit_rejects_status() {
  local json='{"tool_input":{"command":"git status"},"cwd":"'"$TEMP_PROJECT"'"}'
  HOOK_INPUT="$json"
  parse_precommit_input || return 1
  is_git_commit_command "$HOOK_COMMAND" && return 1
  return 0
}

if test_precommit_rejects_status; then
  pass "precommit_setup rejects git status"
else
  fail "precommit_setup rejects git status"
fi

# Test postedit_setup with valid Elixir file
test_postedit_setup() {
  local json='{"tool_input":{"file_path":"'"$TEMP_PROJECT/lib/test.ex"'"}}'
  HOOK_INPUT="$json"
  parse_postedit_input || return 1
  is_elixir_file "$HOOK_FILE_PATH" || return 1
  PROJECT_ROOT=$(find_mix_project_root_from_file "$HOOK_FILE_PATH") || return 1
  return 0
}

if test_postedit_setup; then
  pass "postedit_setup with valid .ex file"
else
  fail "postedit_setup with valid .ex file"
fi

# Test postedit_setup rejects non-Elixir files
test_postedit_rejects_js() {
  local json='{"tool_input":{"file_path":"'"$TEMP_PROJECT/lib/test.js"'"}}'
  HOOK_INPUT="$json"
  parse_postedit_input || return 1
  is_elixir_file "$HOOK_FILE_PATH" && return 1
  return 0
}

if test_postedit_rejects_js; then
  pass "postedit_setup rejects .js file"
else
  fail "postedit_setup rejects .js file"
fi

# Cleanup temp project
rm -rf "$TEMP_PROJECT"

# Summary
echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
