#!/usr/bin/env bash
# Ash codegen check - detects when generated code is out of sync
# Kept separate from main post-edit-check.sh because:
# - Ash is rarely used (only in Ash Framework projects)
# - Has different mental model (code generation vs code quality)

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/lib.sh"
source "$SCRIPT_DIR/../lib/postedit-utils.sh"

# Only run if project has Ash dependency
postedit_setup_with_dep "ash" || { emit_suppress_json; exit 0; }
cd "$PROJECT_ROOT"

# Check if generated code is in sync
set +e
CODEGEN_OUTPUT=$(mix ash.codegen --check 2>&1)
CODEGEN_EXIT=$?
set -e

if [[ $CODEGEN_EXIT -ne 0 ]]; then
  OUTPUT=$(truncate_output "$CODEGEN_OUTPUT" 50 "mix ash.codegen --check")
  CONTEXT="Ash codegen is out of sync:

${OUTPUT}

Run 'mix ash.codegen' to regenerate."
  emit_context_json "$CONTEXT"
else
  emit_suppress_json
fi

exit 0
