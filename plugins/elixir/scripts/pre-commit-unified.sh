#!/usr/bin/env bash
set -eo pipefail

# =============================================================================
# Unified Pre-Commit Check
# =============================================================================
# Runs three fast, deterministic checks before `git commit`:
#   format --check-formatted, compile --warnings-as-errors, deps.unlock --check-unused
#
# Deliberately NOT run here (see ~/.claude/includes/verification-policy.md —
# a commit is not a reason for project-wide gates): credo, doctor, sobelow,
# mix_audit, ash.codegen, tests, dialyzer, ex_doc. Those belong to the
# reviewer, CI, and the post-merge QA audit. The project's own `mix precommit`
# alias remains the manual / CI entry point for the full gate.
#
# Full (untruncated) output of every FAILING check is written to
#   /tmp/elixir-precommit/<sha256(project_root)>/<check>.log
# and the paths are listed in the deny message, so the agent can READ the
# failure instead of re-running the check.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/lib.sh"
source "$SCRIPT_DIR/../lib/precommit-utils.sh"

# =============================================================================
# Setup - Don't use precommit_setup (we ARE the precommit runner now)
# =============================================================================

read_hook_input
parse_precommit_input || { emit_suppress_json; exit 0; }
is_git_commit_command "$HOOK_COMMAND" || { emit_suppress_json; exit 0; }

# Individually switchable — see "Per-Hook Enable / Disable" in lib.sh.
# Off for this repo:     .claude/zenhive-hooks.json  { "pre-commit-unified": false }
# Off for one session:   ZENHIVE_HOOKS_DISABLED=pre-commit-unified
hook_enabled "pre-commit-unified" "$HOOK_CWD" || { emit_suppress_json; exit 0; }

GIT_DIR=$(extract_git_dir "$HOOK_COMMAND" "$HOOK_CWD")

# Determine effective working directory for project-root resolution.
# Order: explicit `-C <path>` in command (already in GIT_DIR) → leading
# `cd <path> && ...` in command → HOOK_CWD. The CD_PATH parser handles
# the `cd <worktree> && git commit` pattern from a main-checkout session
# so the hook runs against the worktree's source tree, not main's.
#
# Conservative regex: matches `cd ` followed by an unquoted
# non-whitespace path. Won't match `cd ..`, `cd -`, quoted paths with
# spaces, or `bash -c "..."`. Failure mode is "fall through to GIT_DIR".
EFFECTIVE_CWD="$GIT_DIR"

CD_PATH=$(echo "$HOOK_COMMAND" | sed -n 's|.*[[:space:];&|]cd[[:space:]]\{1,\}\([^[:space:];&|]\{1,\}\).*|\1|p; s|^cd[[:space:]]\{1,\}\([^[:space:];&|]\{1,\}\).*|\1|p' | head -1)
[ -n "$CD_PATH" ] && CD_PATH="${CD_PATH/#\~\//$HOME/}"
if [ -n "$CD_PATH" ] && [ -d "$CD_PATH" ]; then
  EFFECTIVE_CWD="$CD_PATH"
fi

PROJECT_ROOT=$(find_mix_project_root_from_dir "$EFFECTIVE_CWD") || { emit_suppress_json; exit 0; }
cd "$PROJECT_ROOT"

# =============================================================================
# Full-output capture: save each FAILING check's untruncated output to a
# project-scoped /tmp dir so the agent reads the file instead of re-running.
# Files are named <slug>.log and cleared at the start of every run.
# =============================================================================

TMP_DIR="/tmp/elixir-precommit/$(printf '%s' "$PROJECT_ROOT" | shasum -a 256 | cut -d' ' -f1)"
mkdir -p "$TMP_DIR"
rm -f "$TMP_DIR"/*.log 2>/dev/null || true

# save_check_output <slug> <full_output> → writes $TMP_DIR/<slug>.log, echoes path
save_check_output() {
  local path="$TMP_DIR/$1.log"
  printf '%s\n' "$2" > "$path"
  printf '%s' "$path"
}

# =============================================================================
# Run all quality checks
# =============================================================================

ERRORS=""

# -----------------------------------------------------------------------------
# Always Required: Format + Compile + Unused Deps
# -----------------------------------------------------------------------------

set +e

FORMAT_OUTPUT=$(mix format --check-formatted 2>&1)
if [ $? -ne 0 ]; then
  FORMAT_LOG=$(save_check_output "format" "$FORMAT_OUTPUT")
  ERRORS="${ERRORS}## Format Check Failed\n${FORMAT_OUTPUT}\n\nFull output: ${FORMAT_LOG}\n\n"
fi

COMPILE_OUTPUT=$(mix compile --warnings-as-errors 2>&1)
if [ $? -ne 0 ]; then
  COMPILE_LOG=$(save_check_output "compile" "$COMPILE_OUTPUT")
  COMPILE_TRUNCATED=$(truncate_output "$COMPILE_OUTPUT" 30 "mix compile --warnings-as-errors")
  ERRORS="${ERRORS}## Compilation Failed\n${COMPILE_TRUNCATED}\n\nFull output: ${COMPILE_LOG}\n\n"
fi

DEPS_OUTPUT=$(mix deps.unlock --check-unused 2>&1)
if [ $? -ne 0 ]; then
  DEPS_LOG=$(save_check_output "deps-unlock" "$DEPS_OUTPUT")
  ERRORS="${ERRORS}## Unused Dependencies\n${DEPS_OUTPUT}\n\nFull output: ${DEPS_LOG}\n\n"
fi

set -e

# =============================================================================
# Report Results
# =============================================================================

if [ -n "$ERRORS" ]; then
  ERROR_MSG="Pre-commit validation failed:\n\n${ERRORS}"
  ERROR_MSG="${ERROR_MSG}Fix these issues before committing.\n\nFull untruncated output of each failing check is saved under ${TMP_DIR}/ — read those files instead of re-running the checks."
  emit_deny_json "$ERROR_MSG" "Commit blocked: pre-commit validation failed"
  exit 0
fi

emit_suppress_json
exit 0
