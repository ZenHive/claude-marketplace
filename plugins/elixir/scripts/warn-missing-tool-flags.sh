#!/usr/bin/env bash
# Warn (non-blocking) when project-standard tooling flags are missing:
#
#   - `mix credo` without both `--strict` AND `--format json`
#     (development-commands.md mandates `mix credo --strict --format json`)
#   - `mix compile` without a leading `time` prefix
#     (development-commands.md: "Always prefix `mix compile` with `time` —
#     tracks compilation duration")
#
# Both checks run independently — the message lists every applicable nudge.
#
# False-positive guard: post-edit-check.sh and pre-commit-unified.sh run
# `mix credo` / `mix compile` as INTERNAL subprocesses inside the hook
# scripts, NOT through Claude's Bash tool. The PreToolUse hook only sees
# Claude-initiated Bash calls, so no special guard is needed for hook-script
# internals.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/lib.sh"

read_hook_input
parse_precommit_input || { emit_suppress_json; exit 0; }

WARNINGS=""

# --- Check 1: mix credo without --strict + --format json -------------------

if echo "$HOOK_COMMAND" | grep -qE '(^|[[:space:]])mix[[:space:]]+credo([[:space:]]|$)'; then
  # Skip flag check when credo is invoked for non-analysis subcommands
  # (e.g. `mix credo --version`, `mix credo gen.config`).
  if ! echo "$HOOK_COMMAND" | grep -qE 'mix[[:space:]]+credo[[:space:]]+(--version|gen\.|help)'; then
    has_strict=false
    has_json=false
    echo "$HOOK_COMMAND" | grep -q -- '--strict' && has_strict=true
    echo "$HOOK_COMMAND" | grep -qE -- '--format([[:space:]]+|=)json' && has_json=true
    if [[ "$has_strict" != "true" || "$has_json" != "true" ]]; then
      WARNINGS+="• \`mix credo\` is missing required flags. Project standard:
    mix credo --strict --format json
  (see development-commands.md — \"Credo: always \`mix credo --strict --format json\`\")

"
    fi
  fi
fi

# --- Check 2: mix compile without `time` prefix ----------------------------
# Matches `mix compile` and `mix compile.elixir` etc. — every compile shape
# benefits from timing. Allow:
#   time mix compile
#   time MIX_ENV=prod mix compile
#   time MIX_ENV=test mix compile.elixir

if echo "$HOOK_COMMAND" | grep -qE '(^|[[:space:]])mix[[:space:]]+compile(\.|[[:space:]]|$)'; then
  if ! echo "$HOOK_COMMAND" | grep -qE '(^|[[:space:]])time([[:space:]]+MIX_ENV=[^[:space:]]+)?[[:space:]]+mix[[:space:]]+compile'; then
    WARNINGS+="• \`mix compile\` should be prefixed with \`time\` to track compilation duration:
    time mix compile
    time MIX_ENV=prod mix compile
  (see development-commands.md — \"Always prefix \`mix compile\` with \`time\`\")

"
  fi
fi

# --- Emit ------------------------------------------------------------------

if [[ -z "$WARNINGS" ]]; then
  emit_suppress_json
  exit 0
fi

MESSAGE="⚠️  Missing project-standard tooling flags

${WARNINGS}The command will still run — this is a non-blocking nudge."

jq -n --arg ctx "$MESSAGE" '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": $ctx
  }
}'
