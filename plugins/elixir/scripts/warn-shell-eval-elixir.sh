#!/usr/bin/env bash
# Warn (non-blocking) when Claude is about to run Elixir code through the shell
# — the cases with a direct mcp__tidewave__project_eval / get_logs equivalent.
#
# Tidewave attaches to the same BEAM as the running dev server, so the
# project-eval tool sees current state and skips the fresh-VM startup that
# `mix run` incurs. The tidewave-guide skill exists, but Claude regularly
# forgets it under shell-muscle-memory; this hook puts the reminder in front
# of the call.
#
# Warn-only — must NOT block. Seeds (priv/repo/seeds.exs) and one-shot CI
# scripts share the same `mix run X.exs` shape; the warning footer names them
# as legitimate exceptions.
#
# Fires on:    mix run -e "..."
#              elixir -e "..."
#              iex -e "..."
#              mix run <anything>.exs
# Silent on:   mix test, iex -S mix, iex -S mix tidewave, mix phx.server,
#              mix compile (structurally — the four alternates above don't
#              match any of those).
#
# Reference: ~/_DATA/code/hieroglyph/.claude/hookify.prefer-tidewave-over-shell-eval.local.md

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/lib.sh"

read_hook_input
parse_precommit_input || { emit_suppress_json; exit 0; }

# Single ERE with four alternates. BSD-portable: [[:space:]] not \s.
# Word-boundary equivalent for end-of-token: ([[:space:]]|$).
PATTERN='(^|[[:space:]])(mix[[:space:]]+run[[:space:]]+-e([[:space:]]|$)'
PATTERN+='|elixir[[:space:]]+-e([[:space:]]|$)'
PATTERN+='|iex[[:space:]]+-e([[:space:]]|$)'
PATTERN+='|mix[[:space:]]+run[[:space:]]+[^[:space:]]+\.exs)'

echo "$HOOK_COMMAND" | grep -qE "$PATTERN" \
  || { emit_suppress_json; exit 0; }

MESSAGE="🌊 Use Tidewave instead of shelling out to evaluate Elixir

You're about to run Elixir code from the shell. The dev server is already
running in the same BEAM that Tidewave attaches to — use the
mcp__tidewave__project_eval tool instead.

Why this matters:
- Same BEAM as dev — sees current state, GenServers, ETS, in-memory caches,
  application env
- No fresh-VM startup (~3–10s saved per call); reuses module compile cache
- Returns structured Elixir terms, not stringified stdout
- No scratch .exs file to clean up

Direct replacements:
  mix run -e \"ABI.encode(...)\"      →  mcp__tidewave__project_eval with code: \"ABI.encode(...)\"
  mix run scripts/explore.exs       →  paste the script body as the code arg
  iex -e \"Foo.bar()\"                →  mcp__tidewave__project_eval with code: \"Foo.bar()\"
  tail -f on app logs               →  mcp__tidewave__get_logs

If the running server has stale bytecode: call recompile() via
project_eval (or r(SomeModule) for one module). Don't restart the server,
don't shell out — the tidewave-guide skill covers this.

Legitimate exceptions (proceed past the warning):
- mix run priv/repo/seeds.exs — actual seeding, not exploration
- One-shot CI / release scripts that must run in a fresh VM
- Tidewave isn't running (rare — verify with \`claude mcp get tidewave\`)

If you're not sure which side of the line you're on, you're probably
exploring — use the project-eval tool."

jq -n --arg ctx "$MESSAGE" '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": $ctx
  }
}'
