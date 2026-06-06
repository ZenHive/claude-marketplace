#!/usr/bin/env bash
set -eo pipefail

# =============================================================================
# Unified Pre-Commit Check
# =============================================================================
# Runs the standard Elixir quality gate before `git commit`. The hook is
# AUTHORITATIVE: it always runs its own inline checks and does NOT defer to a
# project `mix precommit` alias. The alias stays for deliberate manual / CI
# runs (`mix precommit`, `mix precommit.full`); the commit hook no longer
# invokes it.
#
# Checks (optional ones gated on the dep being present):
#   - Always:     format, compile --warnings-as-errors, deps.unlock --check-unused, credo
#   - If present: doctor, sobelow, mix_audit, ash.codegen
#
# NOT run at commit time (deliberately — too slow / flaky for the inner loop):
#   - tests     → post-edit-check.sh already runs the matching test file per edit;
#                 the full suite belongs in CI / manual `mix test.json`.
#   - dialyzer  → cold-PLT runs blow the hook timeout; belongs in CI /
#                 manual `mix precommit.full`.
#   - ex_doc    → `mix docs --warnings-as-errors` builds the full HTML doc site;
#                 too slow for the inner loop. Run in CI or manually.
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

# -----------------------------------------------------------------------------
# Always Required: Credo (fail if missing - this is a required dep)
# -----------------------------------------------------------------------------

if ! has_mix_dependency "credo" "$PROJECT_ROOT"; then
  ERRORS="${ERRORS}## Missing Required Dependency: credo\nAdd {:credo, \"~> 1.7\", only: [:dev, :test], runtime: false} to mix.exs\n\n"
else
  # Exclude TODO/FIXME checks - these are intentional documentation
  CREDO_OUTPUT=$(mix credo --strict --format oneline --no-color --ignore-checks Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME 2>&1)
  if [ $? -ne 0 ]; then
    CREDO_LOG=$(save_check_output "credo" "$CREDO_OUTPUT")
    CREDO_OUTPUT=$(truncate_output "$CREDO_OUTPUT" 30 "mix credo --strict --format oneline --no-color")
    ERRORS="${ERRORS}## Credo Issues\n${CREDO_OUTPUT}\n\nFull output: ${CREDO_LOG}\n\n"
  fi
fi

# -----------------------------------------------------------------------------
# Optional: Doctor (moduledoc/spec coverage)
# -----------------------------------------------------------------------------

if has_mix_dependency "doctor" "$PROJECT_ROOT"; then
  DOCTOR_OUTPUT=$(mix doctor --summary --failed 2>&1)
  if [ $? -ne 0 ]; then
    DOCTOR_LOG=$(save_check_output "doctor" "$DOCTOR_OUTPUT")
    DOCTOR_OUTPUT=$(truncate_output "$DOCTOR_OUTPUT" 20 "mix doctor --summary --failed")
    ERRORS="${ERRORS}## Doctor Issues\n${DOCTOR_OUTPUT}\n\nFull output: ${DOCTOR_LOG}\n\n"
  fi
fi

# -----------------------------------------------------------------------------
# Optional: Sobelow (security scanning)
# -----------------------------------------------------------------------------

if has_mix_dependency "sobelow" "$PROJECT_ROOT"; then
  # Always pass --skip so inline `# sobelow_skip` annotations are honored —
  # sobelow gates inline skips on this flag (`if get_env(:skip) ...`), while the
  # `.sobelow-skips` fingerprint file is read unconditionally regardless. Mirrors
  # a project's own `mix sobelow --skip` so the hook doesn't surface findings the
  # project's stack tolerates. (`.sobelow-conf` is NOT honored here — it loads
  # only with --config, which would replace --format json and break JSON parsing.)
  CMD="mix sobelow --format json --skip"

  SOBELOW_OUTPUT=$($CMD 2>&1)
  JSON_OUTPUT=$(echo "$SOBELOW_OUTPUT" | sed -n '/{/,$ p')

  if echo "$JSON_OUTPUT" | jq -e '.findings | (.high_confidence + .medium_confidence + .low_confidence) | length > 0' > /dev/null 2>&1; then
    SOBELOW_LOG=$(save_check_output "sobelow" "$SOBELOW_OUTPUT")
    SOBELOW_OUTPUT=$(truncate_output "$SOBELOW_OUTPUT" 20 "mix sobelow")
    ERRORS="${ERRORS}## Security Issues (Sobelow)\n${SOBELOW_OUTPUT}\n\nFull output: ${SOBELOW_LOG}\n\nOptions:\n  1. Fix the issues (recommended)\n  2. Mark false positives: mix sobelow --mark-skip-all\n\n"
  fi
fi

# -----------------------------------------------------------------------------
# Optional: MixAudit (dependency vulnerability scanning)
# -----------------------------------------------------------------------------

if has_mix_dependency "mix_audit" "$PROJECT_ROOT"; then
  AUDIT_OUTPUT=$(mix deps.audit 2>&1)
  if [ $? -ne 0 ]; then
    AUDIT_LOG=$(save_check_output "mix-audit" "$AUDIT_OUTPUT")
    AUDIT_OUTPUT=$(truncate_output "$AUDIT_OUTPUT" 20 "mix deps.audit")
    ERRORS="${ERRORS}## Vulnerable Dependencies\n${AUDIT_OUTPUT}\n\nFull output: ${AUDIT_LOG}\n\n"
  fi
fi

# -----------------------------------------------------------------------------
# Optional: Ash codegen (Ash Framework)
# -----------------------------------------------------------------------------

if has_mix_dependency "ash" "$PROJECT_ROOT"; then
  CODEGEN_OUTPUT=$(mix ash.codegen --check 2>&1)
  if [ $? -ne 0 ]; then
    CODEGEN_LOG=$(save_check_output "ash-codegen" "$CODEGEN_OUTPUT")
    ERRORS="${ERRORS}## Ash Codegen Out of Sync\n${CODEGEN_OUTPUT}\n\nFull output: ${CODEGEN_LOG}\n\nRun 'mix ash.codegen' to update.\n\n"
  fi
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
