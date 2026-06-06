#!/usr/bin/env bash
# Consolidated post-edit hook for Elixir files
# Runs: format, compile, corresponding-test, credo, sobelow, doctor, struct-reminder, hidden-failures, mixexs-check

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/lib.sh"
source "$SCRIPT_DIR/../lib/postedit-utils.sh"

# ============================================================================
# Configuration
# ============================================================================

MAX_OUTPUT_LINES=50
REQUIRED_DEPS=("credo" "sobelow" "doctor")

# ============================================================================
# Output Aggregation
# ============================================================================

OUTPUT_SECTIONS=""

add_section() {
  local title="$1"
  local content="$2"
  if [[ -n "$content" ]]; then
    OUTPUT_SECTIONS="${OUTPUT_SECTIONS}## ${title}\n${content}\n\n"
  fi
}

add_ok_section() {
  local title="$1"
  OUTPUT_SECTIONS="${OUTPUT_SECTIONS}## ${title}: ✓\n\n"
}

# ============================================================================
# Emit Error (for missing deps - blocking)
# ============================================================================

emit_error_json() {
  local message="$1"
  jq -n \
    --arg msg "$message" \
    '{
      "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": ("❌ ERROR: " + $msg)
      }
    }'
}

# ============================================================================
# Main Logic
# ============================================================================

# Parse input and setup
read_hook_input
parse_postedit_input || { emit_suppress_json; exit 0; }

# Check if Elixir file
is_elixir_file "$HOOK_FILE_PATH" || { emit_suppress_json; exit 0; }

# Find project root
PROJECT_ROOT=$(find_mix_project_root_from_file "$HOOK_FILE_PATH") || { emit_suppress_json; exit 0; }

# ============================================================================
# FAIL LOUD: Check required dependencies
# ============================================================================

MISSING_DEPS=""
for dep in "${REQUIRED_DEPS[@]}"; do
  if ! has_mix_dependency "$dep" "$PROJECT_ROOT"; then
    MISSING_DEPS="${MISSING_DEPS} ${dep}"
  fi
done

if [[ -n "$MISSING_DEPS" ]]; then
  emit_error_json "Missing required deps:${MISSING_DEPS}. Add to mix.exs: {:credo, \"~> 1.7\", runtime: false}, {:sobelow, \"~> 0.13\", runtime: false}, {:doctor, \"~> 0.21\", runtime: false}"
  exit 0
fi

cd "$PROJECT_ROOT"

# ============================================================================
# Check 1: Mix Format
# ============================================================================

set +e
FORMAT_OUTPUT=$(mix format "$HOOK_FILE_PATH" 2>&1)
FORMAT_EXIT=$?
set -e

if [[ $FORMAT_EXIT -ne 0 ]]; then
  add_section "Format" "Error formatting file:\n${FORMAT_OUTPUT}"
fi
# Format success is silent (file was formatted)

# ============================================================================
# Check 2: Mix Compile
# ============================================================================

set +e
COMPILE_OUTPUT=$(mix compile --warnings-as-errors 2>&1)
COMPILE_EXIT=$?
set -e

if [[ $COMPILE_EXIT -ne 0 ]]; then
  COMPILE_TRUNCATED=$(truncate_output "$COMPILE_OUTPUT" "$MAX_OUTPUT_LINES" "mix compile --warnings-as-errors")
  add_section "Compile" "$COMPILE_TRUNCATED"
fi
# Compile success is silent

# ============================================================================
# Check 3: Corresponding Test (run matching test file)
# ============================================================================

# Map lib/foo.ex → test/foo_test.exs, or run the test file itself if editing a test
CORRESPONDING_TEST=""
if [[ "$HOOK_FILE_PATH" =~ _test\.exs$ ]]; then
  # Editing a test file — run it directly
  CORRESPONDING_TEST="$HOOK_FILE_PATH"
elif [[ "$HOOK_FILE_PATH" =~ ^(.*/)?lib/(.+)\.ex$ ]]; then
  # Editing a lib file — find corresponding test
  RELATIVE_PATH="${BASH_REMATCH[2]}"
  CANDIDATE="${PROJECT_ROOT}/test/${RELATIVE_PATH}_test.exs"
  [[ -f "$CANDIDATE" ]] && CORRESPONDING_TEST="$CANDIDATE"
fi

if [[ -n "$CORRESPONDING_TEST" ]] && has_mix_dependency "ex_unit_json" "$PROJECT_ROOT"; then
  set +e
  TEST_OUTPUT=$(mix test.json "$CORRESPONDING_TEST" 2>&1)
  TEST_EXIT=$?
  set -e

  if [[ $TEST_EXIT -ne 0 ]]; then
    TEST_TRUNCATED=$(truncate_output "$TEST_OUTPUT" "$MAX_OUTPUT_LINES" "mix test.json \"$CORRESPONDING_TEST\"")
    add_section "Test (${CORRESPONDING_TEST##*/})" "$TEST_TRUNCATED"
  fi
fi

# ============================================================================
# Check 4: Credo (static analysis)
# ============================================================================

set +e
# Exclude TODO/FIXME checks - intentional documentation
CREDO_OUTPUT=$(mix credo "$HOOK_FILE_PATH" --format oneline --no-color --ignore-checks Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME 2>&1)
CREDO_EXIT=$?
set -e

# Credo exits non-zero when issues found - don't grep for "issues" (matches "0 issues found")
if [[ $CREDO_EXIT -ne 0 ]]; then
  CREDO_TRUNCATED=$(truncate_output "$CREDO_OUTPUT" 30 "mix credo \"$HOOK_FILE_PATH\" --format oneline --no-color")
  add_section "Credo" "$CREDO_TRUNCATED"
fi

# ============================================================================
# Check 5: Sobelow (security)
# ============================================================================

set +e
SOBELOW_CMD="mix sobelow --format json"
[[ -f .sobelow-skips ]] && SOBELOW_CMD="$SOBELOW_CMD --skip"
SOBELOW_OUTPUT=$($SOBELOW_CMD 2>&1)
SOBELOW_EXIT=$?
set -e

# Check for findings in JSON output
HAS_FINDINGS=false
JSON_OUTPUT=$(echo "$SOBELOW_OUTPUT" | sed -n '/{/,$ p')
if echo "$JSON_OUTPUT" | jq -e '.findings | (.high_confidence + .medium_confidence + .low_confidence) | length > 0' > /dev/null 2>&1; then
  HAS_FINDINGS=true
fi

if [[ $SOBELOW_EXIT -ne 0 ]] || [[ "$HAS_FINDINGS" == "true" ]]; then
  SOBELOW_TRUNCATED=$(truncate_output "$SOBELOW_OUTPUT" 30 "mix sobelow")
  add_section "Security (Sobelow)" "${SOBELOW_TRUNCATED}\n\nTo suppress false positives:\n  - Add inline comment: # sobelow_skip [\"FindingType\"]\n  - Mark all as skipped: mix sobelow --mark-skip-all"
fi

# ============================================================================
# Check 6: Doctor (moduledoc/spec coverage)
# ============================================================================

set +e
DOCTOR_OUTPUT=$(mix doctor --summary --failed 2>&1)
DOCTOR_EXIT=$?
set -e

if [[ $DOCTOR_EXIT -ne 0 ]]; then
  DOCTOR_TRUNCATED=$(truncate_output "$DOCTOR_OUTPUT" 30 "mix doctor --summary --failed")
  add_section "Doctor (docs/specs)" "$DOCTOR_TRUNCATED"
fi

# ============================================================================
# Check 7: Struct Reminder (only for .ex non-test files)
# ============================================================================

if [[ "$HOOK_FILE_PATH" =~ \.ex$ ]] && [[ ! "$HOOK_FILE_PATH" =~ _test\.exs$ ]] && [[ -f "$HOOK_FILE_PATH" ]]; then
  CONTENT=$(cat "$HOOK_FILE_PATH")

  # Skip if already has defstruct
  if ! echo "$CONTENT" | grep -qE '^\s*defstruct\b'; then
    # Check if it's a module file
    if echo "$CONTENT" | grep -qE '^\s*defmodule\b'; then
      STRUCT_REASONS=""

      # Heuristic 1: Map literals with 3+ keys
      if echo "$CONTENT" | grep -qE '%\{[^}]*:[^,}]+,[^}]*:[^,}]+,[^}]*:[^,}]+'; then
        STRUCT_REASONS="${STRUCT_REASONS}- Found map literals with 3+ keys\n"
      fi

      # Heuristic 2: Constructor functions returning maps
      if echo "$CONTENT" | grep -qE 'def\s+(new|build|create|init)\s*\([^)]*\)\s*(do|,)'; then
        if echo "$CONTENT" | grep -qE 'def\s+(new|build|create|init).*%\{'; then
          STRUCT_REASONS="${STRUCT_REASONS}- Found constructor function returning a map\n"
        fi
      fi

      # Heuristic 3: Repeated map patterns
      MAP_KEYS=$(echo "$CONTENT" | grep -oE '%\{[^}]+\}' 2>/dev/null | sed 's/:[^,}]*//g' | sort | uniq -d || true)
      if [[ -n "$MAP_KEYS" ]]; then
        STRUCT_REASONS="${STRUCT_REASONS}- Found repeated map patterns with same keys\n"
      fi

      if [[ -n "$STRUCT_REASONS" ]]; then
        add_section "Struct Hint" "Consider using defstruct:\n${STRUCT_REASONS}\nBenefits: compile-time key validation, @enforce_keys, pattern matching with %MyStruct{}"
      fi
    fi
  fi
fi

# ============================================================================
# Check 8: Hidden Test Failures (only for _test.exs files)
# ============================================================================

if [[ "$HOOK_FILE_PATH" =~ _test\.exs$ ]] && [[ -f "$HOOK_FILE_PATH" ]]; then
  HIDDEN_WARNINGS=""

  # Pattern 1: {:error, _} -> assert true
  if grep -E '\{:error,\s*_[^}]*\}\s*->' "$HOOK_FILE_PATH" 2>/dev/null | grep -qE 'assert\s+true'; then
    HIDDEN_WARNINGS="${HIDDEN_WARNINGS}- '{:error, _} -> assert true' makes ALL failures pass silently\n"
  fi

  # Pattern 2: {:error, _} -> :ok
  if grep -qE '\{:error,\s*_[^}]*\}\s*->\s*:ok' "$HOOK_FILE_PATH" 2>/dev/null; then
    HIDDEN_WARNINGS="${HIDDEN_WARNINGS}- '{:error, _} -> :ok' silently passes on ANY error\n"
  fi

  # Pattern 3: do: :skip (silent skip)
  if grep -qE 'do:\s*:skip' "$HOOK_FILE_PATH" 2>/dev/null; then
    HIDDEN_WARNINGS="${HIDDEN_WARNINGS}- 'do: :skip' silently skips tests instead of failing with instructions\n"
  fi

  if [[ -n "$HIDDEN_WARNINGS" ]]; then
    add_section "Hidden Test Failures" "Patterns that hide failures detected:\n${HIDDEN_WARNINGS}\nTests should FAIL on unexpected errors, not silently pass. Use flunk() with instructions for missing credentials."
  fi
fi

# ============================================================================
# Check 9: mix.exs Checks (only for mix.exs files)
# ============================================================================

if [[ "$HOOK_FILE_PATH" == *"mix.exs" ]] && [[ -f "$HOOK_FILE_PATH" ]]; then
  MIXEXS_CONTENT=$(cat "$HOOK_FILE_PATH")
  MIXEXS_WARNINGS=""

  # Check for missing recommended deps
  for dep in styler dialyxir; do
    if ! echo "$MIXEXS_CONTENT" | grep -qE "\{:${dep}"; then
      MIXEXS_WARNINGS="${MIXEXS_WARNINGS}- Missing {:${dep}, ...}\n"
    fi
  done

  # Check for deps without runtime: false
  for dep in styler credo dialyxir doctor sobelow ex_doc; do
    if echo "$MIXEXS_CONTENT" | grep -qE "\{:${dep}" && ! echo "$MIXEXS_CONTENT" | grep -qE "\{:${dep}[^}]*runtime:\s*false"; then
      MIXEXS_WARNINGS="${MIXEXS_WARNINGS}- {:${dep}} should have runtime: false\n"
    fi
  done

  # Check tidewave without bandit for non-Phoenix
  if echo "$MIXEXS_CONTENT" | grep -qE '\{:tidewave' && ! echo "$MIXEXS_CONTENT" | grep -qE '\{:phoenix\b' && ! echo "$MIXEXS_CONTENT" | grep -qE '\{:bandit'; then
    MIXEXS_WARNINGS="${MIXEXS_WARNINGS}- Has :tidewave but missing :bandit (required for non-Phoenix projects)\n"
  fi

  if [[ -n "$MIXEXS_WARNINGS" ]]; then
    add_section "mix.exs Review" "${MIXEXS_WARNINGS}\nSee /elixir:elixir-setup for full setup guide."
  fi
fi

# ============================================================================
# Output Results
# ============================================================================

if [[ -z "$OUTPUT_SECTIONS" ]]; then
  emit_suppress_json
else
  # Remove trailing newlines and emit
  FINAL_OUTPUT=$(echo -e "$OUTPUT_SECTIONS" | sed 's/\\n/\n/g')
  emit_context_json "$FINAL_OUTPUT"
fi

exit 0
