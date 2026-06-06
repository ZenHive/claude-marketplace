#!/usr/bin/env bash
# Block (deny) two command shapes Claude is explicitly told never to run:
#
#   1. `mix phx.server`
#      critical-rules.md § NEVER START THE PHOENIX SERVER —
#      the server is always already running; assume localhost:4000.
#
#   2. Destructive dependency / build operations:
#      `mix deps.clean`, `mix clean`, `mix deps.unlock --all`,
#      `rm -rf _build`, `rm -rf deps`
#      critical-rules.md § NEVER RUN DESTRUCTIVE DEPENDENCY COMMANDS.
#      Allows: `mix deps.unlock --check-unused`, `mix deps.compile <dep> --force`.
#
# Each block returns a deny-JSON with a permissionDecisionReason naming the
# safe alternative.
#
# NOTE: bare `rm` is NOT blocked. The `rm -rf _build` / `rm -rf deps` targets
# above stay denied (they're the genuinely destructive deps/build case), but
# ordinary file deletion (temp files, scratch fragments) passes through.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/lib.sh"
source "$SCRIPT_DIR/../lib/precommit-utils.sh"

read_hook_input
parse_precommit_input || { emit_suppress_json; exit 0; }

# --- Category 1: mix phx.server --------------------------------------------

if echo "$HOOK_COMMAND" | grep -qE '(^|[[:space:]])mix[[:space:]]+phx\.server([[:space:]]|$)'; then
  REASON="BLOCKED: 'mix phx.server' — the Phoenix server is always already running.

The user starts and stops the server manually. Assume localhost:4000 is up;
to verify behavior, ask the user to check the browser. (See critical-rules.md
§ NEVER START THE PHOENIX SERVER.)"
  emit_deny_json "$REASON" "Blocked: mix phx.server (server is always already running)"
  exit 0
fi

# --- Category 2: destructive deps / build ---------------------------------
# Must NOT match `mix deps.unlock --check-unused` (used by pre-commit-unified.sh
# and legitimately by users) or `mix deps.compile foo --force`.

destructive_match=""
if echo "$HOOK_COMMAND" | grep -qE '(^|[[:space:]])mix[[:space:]]+deps\.clean([[:space:]]|$)'; then
  destructive_match="mix deps.clean"
elif echo "$HOOK_COMMAND" | grep -qE '(^|[[:space:]])mix[[:space:]]+clean([[:space:]]|$)'; then
  destructive_match="mix clean"
elif echo "$HOOK_COMMAND" | grep -qE '(^|[[:space:]])mix[[:space:]]+deps\.unlock[[:space:]]+--all([[:space:]]|$)'; then
  destructive_match="mix deps.unlock --all"
elif echo "$HOOK_COMMAND" | grep -qE '(^|[[:space:]])rm[[:space:]]+-rf?[[:space:]]+(_build|deps)([[:space:]]|/|$)'; then
  destructive_match="rm -rf _build/deps"
fi

if [[ -n "$destructive_match" ]]; then
  REASON="BLOCKED: '$destructive_match' is a destructive dependency / build command.

Most 'corrupt cache' issues are transient. Try one of these first:
  • Re-run \`mix compile\` or \`mix test\` (often the simplest fix)
  • Specific dep issue: \`mix deps.compile <dep_name> --force\`

The command Claude tried to run nukes build artifacts and slows recovery
significantly. Ask the user before running any destructive deps/build command.
(See critical-rules.md § NEVER RUN DESTRUCTIVE DEPENDENCY COMMANDS.)"
  emit_deny_json "$REASON" "Blocked: destructive deps/build command"
  exit 0
fi

# --- No match — allow through ---------------------------------------------
# Bare `rm` (file deletion) is intentionally allowed; only `rm -rf _build` /
# `rm -rf deps` are denied above as part of Category 2.

emit_suppress_json
exit 0
