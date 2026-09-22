#!/usr/bin/env bash
# Post-edit hook for Elixir files: format the edited file, compile with
# warnings-as-errors, run the matching test file. Deterministic mechanics
# only — no style nudges, no project-wide analyzers (those belong to the
# reviewer, CI and post-merge QA per verification-policy.md).

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/lib.sh"
source "$SCRIPT_DIR/../lib/postedit-utils.sh"

MAX_OUTPUT_LINES=50
OUTPUT_SECTIONS=""

add_section() {
  local title="$1"
  local content="$2"
  if [[ -n "$content" ]]; then
    OUTPUT_SECTIONS="${OUTPUT_SECTIONS}## ${title}\n${content}\n\n"
  fi
}

read_hook_input
parse_postedit_input || { emit_suppress_json; exit 0; }
is_elixir_file "$HOOK_FILE_PATH" || { emit_suppress_json; exit 0; }
PROJECT_ROOT=$(find_mix_project_root_from_file "$HOOK_FILE_PATH") || { emit_suppress_json; exit 0; }
cd "$PROJECT_ROOT"

# 1. Format the edited file (success is silent)
set +e
FORMAT_OUTPUT=$(mix format "$HOOK_FILE_PATH" 2>&1)
FORMAT_EXIT=$?
set -e
if [[ $FORMAT_EXIT -ne 0 ]]; then
  add_section "Format" "Error formatting file:\n${FORMAT_OUTPUT}"
fi

# 2. Compile with warnings-as-errors (success is silent)
set +e
COMPILE_OUTPUT=$(mix compile --warnings-as-errors 2>&1)
COMPILE_EXIT=$?
set -e
if [[ $COMPILE_EXIT -ne 0 ]]; then
  COMPILE_TRUNCATED=$(truncate_output "$COMPILE_OUTPUT" "$MAX_OUTPUT_LINES" "mix compile --warnings-as-errors")
  add_section "Compile" "$COMPILE_TRUNCATED"
fi

# 3. Matching test: lib/foo.ex → test/foo_test.exs, or the edited test file itself
CORRESPONDING_TEST=""
if [[ "$HOOK_FILE_PATH" =~ _test\.exs$ ]]; then
  CORRESPONDING_TEST="$HOOK_FILE_PATH"
elif [[ "$HOOK_FILE_PATH" =~ ^(.*/)?lib/(.+)\.ex$ ]]; then
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

if [[ -z "$OUTPUT_SECTIONS" ]]; then
  emit_suppress_json
else
  FINAL_OUTPUT=$(echo -e "$OUTPUT_SECTIONS" | sed 's/\\n/\n/g')
  emit_context_json "$FINAL_OUTPUT"
fi

exit 0
