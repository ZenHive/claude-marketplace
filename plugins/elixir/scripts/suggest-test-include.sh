#!/usr/bin/env bash
# Nudge when `mix test.json` runs without --include flags and the project's
# test_helper.exs excludes tags by default.
#
# The goal is NOT to block iteration (integration/network tags can be slow and
# hit live APIs — running them on every iteration destroys the feedback loop).
# The goal is to inject the list of excluded tags into Claude's context so a
# false "full suite passes" claim becomes harder to make inadvertently.
#
# Non-blocking: emits additionalContext, never permissionDecision.
#
# Fires when:  command starts a `mix test.json` run AND no --include/--only/
#              --failed flag AND no explicit test file path argument
# Silent when: no mix test.json, not an Elixir project, no test_helper.exs,
#              no exclude: list in test_helper.exs, or command is already
#              focused (--include, --only, --failed, or test file path).

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/lib.sh"

read_hook_input
parse_precommit_input || { emit_suppress_json; exit 0; }

# Only fire on `mix test.json` (word-boundary after .json).
echo "$HOOK_COMMAND" | grep -qE 'mix[[:space:]]+test\.json([[:space:]]|$)' \
  || { emit_suppress_json; exit 0; }

# Bail on already-focused runs.
for flag in '--include' '--only' '--failed'; do
  echo "$HOOK_COMMAND" | grep -q -- "$flag" && { emit_suppress_json; exit 0; }
done

# Bail if a test file path argument is present.
echo "$HOOK_COMMAND" | grep -qE '(^|[[:space:]])[^[:space:]]*test/[^[:space:]]+\.exs(:[0-9]+)?' \
  && { emit_suppress_json; exit 0; }

PROJECT_ROOT=$(find_mix_project_root_from_dir "$HOOK_CWD") \
  || { emit_suppress_json; exit 0; }

HELPER="$PROJECT_ROOT/test/test_helper.exs"
[[ -f "$HELPER" ]] || { emit_suppress_json; exit 0; }

# Extract exclude: list from ExUnit.start(exclude: [...]) or
# ExUnit.configure(exclude: [...]). Collapse newlines to tolerate multi-line
# lists. Match the *first* ExUnit.(start|configure) call that contains an
# exclude: keyword.
CONTENT=$(tr '\n' ' ' < "$HELPER")
# `|| true` absorbs grep's non-zero exit when nothing matches; without it,
# `set -o pipefail` would abort the script silently and the user would see no
# output at all for projects that legitimately have no exclude: list.
EXCLUDE_RAW=$(echo "$CONTENT" \
  | grep -oE 'ExUnit\.(start|configure)\([^)]*exclude:[[:space:]]*\[[^]]*\]' \
  | head -1 \
  | grep -oE 'exclude:[[:space:]]*\[[^]]*\]' \
  | sed -E 's/exclude:[[:space:]]*\[//' \
  | sed 's/\]$//' || true)

[[ -n "$EXCLUDE_RAW" ]] || { emit_suppress_json; exit 0; }

# Split on commas, trim whitespace, keep only atom-shaped entries (leading ":").
ATOMS=()
IFS=',' read -ra PARTS <<< "$EXCLUDE_RAW"
for p in "${PARTS[@]}"; do
  trimmed=$(echo "$p" | tr -d '[:space:]')
  case "$trimmed" in
    :*) ATOMS+=("${trimmed#:}") ;;
  esac
done

[[ ${#ATOMS[@]} -gt 0 ]] || { emit_suppress_json; exit 0; }

# Build ":a, :b, :c" display list and " --include a --include b ..." flag chain.
ATOM_LIST=""
INCLUDE_FLAGS=""
for a in "${ATOMS[@]}"; do
  [[ -n "$ATOM_LIST" ]] && ATOM_LIST+=", "
  ATOM_LIST+=":$a"
  INCLUDE_FLAGS+=" --include $a"
done

MESSAGE="ℹ️  mix test.json exclusions detected

test/test_helper.exs excludes these tags by default:
  $ATOM_LIST

What this run covers: offline tests only (excluded tags did NOT run).

If you're iterating — keep going, this is the fast feedback loop.

If you're about to claim the suite passes, either:
  • Run the excluded tags:
      mix test.json$INCLUDE_FLAGS
  • Or state honestly: \"offline tests pass; $ATOM_LIST coverage not verified this run.\""

jq -n --arg ctx "$MESSAGE" '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": $ctx
  }
}'
