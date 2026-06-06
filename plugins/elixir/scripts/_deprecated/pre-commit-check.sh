#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/lib.sh"
source "$SCRIPT_DIR/../lib/precommit-utils.sh"

precommit_setup || exit 0
cd "$PROJECT_ROOT"

# Disable errexit to capture exit codes from commands that may fail
set +e
FORMAT_OUTPUT=$(mix format --check-formatted 2>&1)
FORMAT_EXIT=$?

COMPILE_OUTPUT=$(mix compile --warnings-as-errors 2>&1)
COMPILE_EXIT=$?

DEPS_OUTPUT=$(mix deps.unlock --check-unused 2>&1)
DEPS_EXIT=$?
set -e

if [ $FORMAT_EXIT -ne 0 ] || [ $COMPILE_EXIT -ne 0 ] || [ $DEPS_EXIT -ne 0 ]; then
  ERROR_MSG="Core plugin pre-commit validation failed:\n\n"

  if [ $FORMAT_EXIT -ne 0 ]; then
    ERROR_MSG="${ERROR_MSG}[ERROR] Format check failed:\n${FORMAT_OUTPUT}\n\n"
  fi

  if [ $COMPILE_EXIT -ne 0 ]; then
    ERROR_MSG="${ERROR_MSG}[ERROR] Compilation failed:\n${COMPILE_OUTPUT}\n\n"
  fi

  if [ $DEPS_EXIT -ne 0 ]; then
    ERROR_MSG="${ERROR_MSG}[ERROR] Unused dependencies check failed:\n${DEPS_OUTPUT}\n\n"
  fi

  ERROR_MSG="${ERROR_MSG}Fix these issues before committing."

  emit_deny_json "$ERROR_MSG" "Commit blocked: core validation checks failed"
  exit 0
fi

emit_suppress_json
exit 0
