# elixir

Elixir/OTP development support plugin for Claude Code: four deterministic hooks
plus skills for ZenHive's own Hex packages and conventions.

Generic Elixir / Phoenix / Ecto / LiveView knowledge (idioms, hexdocs lookup,
Tidewave, testing patterns, deps vetting) is **not** shipped here — enable
[phxagents.dev](https://phxagents.dev) (`elixir-phoenix`, `ecto`, `lv`) for
that. The two compose: phxagents is the framework layer, this plugin is the
ZenHive layer.

## Installation

```bash
claude
/plugin install elixir@zenhive
```

Requirements: Elixir + Mix on `PATH`, run from a Mix project, `jq`.

## Hooks

All four are mechanics — they run a tool and report its output. No style
nudges, no LLM prompts, no project-wide analyzers (those belong to the
reviewer, CI and post-merge QA per `~/.claude/includes/verification-policy.md`).

| Hook | Event | Does |
|---|---|---|
| `post-edit-check.sh` | PostToolUse Edit/Write | `mix format <file>`, `mix compile --warnings-as-errors`, `mix test.json <matching test>` (lib/foo.ex → test/foo_test.exs, or the edited test itself; only when `ex_unit_json` is a dep). Silent on success. |
| `pre-commit-unified.sh` | PreToolUse Bash (`git commit`) | `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix deps.unlock --check-unused`. Denies the commit on failure; full output of each failing check is saved under `/tmp/elixir-precommit/<hash>/<check>.log` and the paths are in the deny message. Resolves the Mix project from `-C`, a leading `cd`, or cwd. |
| `block-destructive-bash.sh` | PreToolUse Bash | Denies `mix phx.server` (server is always already running) and `mix deps.clean`, `mix clean`, `mix deps.unlock --all`, `rm -rf _build`, `rm -rf deps`. Allows `mix deps.unlock --check-unused` and `mix deps.compile <dep> --force`. |
| `prefer-test-json.sh` / `prefer-dialyzer-json.sh` | PreToolUse Bash | Silently rewrites `mix test …` → `mix test.json …` and `mix dialyzer …` → `mix dialyzer.json …` via `updatedInput`, args preserved. |

### Switching a hook off

Each hook's id is its script filename without `.sh`. Resolution order, first
match wins: `ZENHIVE_HOOKS_ENABLED` → `ZENHIVE_HOOKS_DISABLED` (comma/space
separated ids, `*` = all) → `<repo>/.claude/zenhive-hooks.json` →
`~/.claude/zenhive-hooks.json` → on.

```json
{ "pre-commit-unified": false }
```

```bash
ZENHIVE_HOOKS_DISABLED=pre-commit-unified
```

Currently wired: `pre-commit-unified`. Any other hook adopts the switch with
`hook_enabled "<id>" "$HOOK_CWD" || { emit_suppress_json; exit 0; }` after its
input parsing.

### Cursor

Cursor loads hooks from `~/.cursor/hooks.json` with a different schema.
`scripts/cursor-post-edit-adapt.sh` wraps `post-edit-check.sh` for it; copy
`cursor-hooks.example.json` and replace the absolute path.

## Skills

Synced from `~/.claude/includes/` (edit the include, re-sync with
`scripts/sync-skills-from-includes.sh`; never edit the copy):

- **Conventions:** `elixir-setup`, `development-commands`,
  `development-philosophy`, `code-style`, `web-command`
- **Own packages:** `ex-unit-json`, `dialyzer-json`, `reach`, `agent-economy`,
  `api-toolkit`, `zen-websocket`, `nexus-template`, and the elixir-vibe family
  (`elixir-vibe`, `building-blocks`, `ex-ast`, `ex-dna`, `ex-slop`, `exograph`,
  `program-facts`, `pi-elixir`, `vibe`, `vibe-kit`, `vibe-actions`,
  `hex-playground`, `quackdb`, `fsst`, `phoenix-replay`, `cringe`, `ttycast`,
  `theoria`, `muex`, `systemdkit`, `host-kit`, `safe-rpc`, `unitctl`)

See `SKILLS.md` at the repo root for the full catalog.
