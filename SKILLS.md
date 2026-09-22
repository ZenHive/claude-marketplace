# Skills catalog — `zenhive` marketplace

Every skill shipped by a `zenhive` plugin, grouped by plugin. Invoke as
`<plugin>:<skill>` (e.g. `workflow:rmap`, `elixir-volt:oxc`).

**Sync status:**
- **synced** — body auto-generated from `~/.claude/includes/<file>.md` via
  `scripts/sync-skills-from-includes.sh` (mapping in `scripts/skill-include-map.sh`).
  Never edit the body; edit the include and re-sync.
- **native** — hand-authored in this repo; edit directly.
- **self-sync** — `harness` skills carry their own per-file headers and sync from
  their own canonical sources (not in the include map).

## Orchestration

### harness
- `harness-driver` (self-sync) — API/MCP contract for driving harness.
- `harness-workflow` (self-sync) — the implement → review → land loop.

### workflow
- `rmap` (synced ← rmap.md)
- `task-writing` (synced ← task-writing.md)
- `roadmap-planning` (synced ← task-prioritization.md)
- `task-driver` (native)
- `git-worktrees` (synced ← worktree-workflow.md)
- `upstream-pr-workflow` (synced ← upstream-pr-workflow.md)
- `onchain-verification` (synced ← onchain-verification.md)

## Personal tooling

### tools
- `himalaya` (synced ← himalaya.md)
- `gloomberb` (synced ← gloomberb.md)

## Per-language dev tooling

Generic Elixir / Phoenix / Ecto / LiveView knowledge is not shipped here —
that is [phxagents.dev](https://phxagents.dev)'s job. These skills cover
ZenHive's own packages and conventions only.

### elixir
- conventions, synced ← includes: `code-style`, `development-commands`,
  `development-philosophy`, `elixir-setup`, `web-command`
- own packages, synced ← includes: `dialyzer-json`, `ex-unit-json`, `reach`,
  `agent-economy`, `api-toolkit`, `zen-websocket`, `nexus-template`,
  `elixir-vibe`, `building-blocks`, `ex-ast`, `ex-dna`, `ex-slop`, `exograph`,
  `program-facts`, `pi-elixir`, `vibe`, `vibe-kit`, `vibe-actions`,
  `hex-playground`, `quackdb`, `fsst`, `phoenix-replay`, `cringe`, `ttycast`,
  `theoria`, `muex`, `systemdkit`, `host-kit`, `safe-rpc`, `unitctl`

### elixir-volt
- synced ← includes: `oxc`, `quickbeam`, `elixir-volt`, `npm-ci-verify`,
  `npm-security-audit`, `npm-dep-analysis`
- native: `popcorn`

## Hook-only plugins (no skills)

`dep-audit` ships a SessionStart hook only — see its `README.md`.
