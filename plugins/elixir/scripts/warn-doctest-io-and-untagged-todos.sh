#!/usr/bin/env bash
# Warn (non-blocking) on two patterns credo can't easily see:
#
#   1. IO.puts / IO.inspect inside an @doc or @moduledoc heredoc.
#      development-philosophy.md § "No IO in @doc examples" — @doc demonstrates
#      API usage, not console output.
#
#   2. `#` comments containing deferred-work phrases ("For now,", "Currently,",
#      "Temporarily,", "In production,", "This is a workaround,") that are NOT
#      prefixed with TODO:.
#      development-philosophy.md § "TODO Comment Requirements" — without the
#      TODO: prefix, technical debt is invisible to credo and slips review.
#
# False-positive guards (acceptance criterion):
#   - String literals / ~s / ~S sigils: only matches `^[[:space:]]*#` for
#     comments (anchors to line-leading whitespace + #, never a # inside a
#     string mid-line). For IO calls, only matches inside a `@doc """ ... """`
#     heredoc range tracked by awk state.
#   - Non-.ex/.exs files: suppressed via is_elixir_file.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/lib.sh"
source "$SCRIPT_DIR/../lib/postedit-utils.sh"

read_hook_input
parse_postedit_input || { emit_suppress_json; exit 0; }

is_elixir_file "$HOOK_FILE_PATH" || { emit_suppress_json; exit 0; }
[[ -f "$HOOK_FILE_PATH" ]] || { emit_suppress_json; exit 0; }

FINDINGS=""

# --- Check 1: IO.puts / IO.inspect inside @doc heredoc --------------------
# awk tracks doc-heredoc state: entering on `@doc """` or `@moduledoc """`,
# exiting on the closing `"""` line. Inside that range, flag IO calls.

DOC_IO=$(awk '
  /^[[:space:]]*@(module)?doc[[:space:]]+"""/ { in_doc = 1; next }
  in_doc && /^[[:space:]]*"""[[:space:]]*$/   { in_doc = 0; next }
  in_doc && /IO\.(puts|inspect)/ {
    print FILENAME ":" NR ": IO." (match($0, /IO\.puts/) ? "puts" : "inspect") " inside @doc heredoc"
  }
' "$HOOK_FILE_PATH" || true)

if [[ -n "$DOC_IO" ]]; then
  FINDINGS+="• IO calls inside @doc — @doc demonstrates API usage, not console output:
$(echo "$DOC_IO" | sed 's/^/    /')
  Replace with the function call shape, e.g.:
    @doc \"\"\"
        iex> {:ok, user} = MyApp.get_user(\"id\")
    \"\"\"
  (see development-philosophy.md § Elixir Documentation Standards)

"
fi

# --- Check 2: Untagged deferred-work comments ------------------------------
# Match `^[[:space:]]*#[[:space:]]+(<phrase>),` — leading whitespace + # +
# space + one of the trigger phrases. The leading-anchor guarantees we never
# match a # mid-line inside a string literal.

UNTAGGED=$(grep -nE '^[[:space:]]*#[[:space:]]+(For now|Currently|Temporarily|In production|This is a workaround),' "$HOOK_FILE_PATH" 2>/dev/null \
  | grep -v 'TODO:' || true)

if [[ -n "$UNTAGGED" ]]; then
  FINDINGS+="• Untagged deferred-work comment — credo won't track this without TODO::
$(echo "$UNTAGGED" | sed "s|^|    $HOOK_FILE_PATH:|")
  Rewrite with a TODO: prefix:
    # TODO: For now, hardcoded timeout — should be configurable
  (see development-philosophy.md § TODO Comment Requirements)

"
fi

# --- Emit ------------------------------------------------------------------

if [[ -z "$FINDINGS" ]]; then
  emit_suppress_json
  exit 0
fi

MESSAGE="⚠️  Post-edit nudges (non-blocking)

${FINDINGS}These won't fail any check — they're reminders for cleanup."

emit_context_json "$MESSAGE"
