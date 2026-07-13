# Skills catalog — `zenhive` marketplace

Every skill shipped by a `zenhive` plugin, grouped by plugin. Invoke as
`<plugin>:<skill>` (e.g. `tasks:rmap`, `elixir-volt:oxc`).

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
- `git-worktrees` (synced ← worktree-workflow.md)
- `dev-lifecycle` (synced ← dev-lifecycle.md)
- `workflow-philosophy` (synced ← workflow-philosophy.md)
- `upstream-pr-workflow` (synced ← upstream-pr-workflow.md)

### tasks
- `rmap` (synced ← rmap.md)
- `task-writing` (synced ← task-writing.md)
- `roadmap-planning` (synced ← task-prioritization.md)
- `task-driver` (native)

### review
- `code-review` (native)
- `audit-review` (native)

### delegation
- `linear-workflow` (synced ← linear-workflow.md)
- `linear-queue` (synced ← linear-queue.md)
- `agent-dispatch` (synced ← agent-dispatch.md)
- `agent-pr-review` (synced ← agent-pr-review.md)
- `flow-review` (synced ← flow-review.md)
- `cloud-agent-environments` (synced ← cloud-agent-environments.md)
- `sprite-claude-code` (synced ← sprite-claude-code.md)
- `delegation-rules` (synced ← delegation-rules.md)

### portfolio
- `portfolio-strategy` (synced ← portfolio-strategy.md)

## Personal tooling

### tools
- `himalaya` (synced ← himalaya.md)

## Per-language dev tooling

### elixir
- synced ← includes: `code-style`, `development-commands`,
  `development-philosophy`, `dialyzer-json`, `ex-unit-json`, `elixir-setup`,
  `reach`, `web-command`, `agent-economy`, `api-toolkit`, `zen-websocket`,
  `nexus-template`
- native: `elixir-ci-harness`, `hex-docs-search`, `integration-testing`,
  `tidewave-guide`, `usage-rules`

### elixir-volt
- synced ← includes: `oxc`, `quickbeam`, `elixir-volt`, `npm-ci-verify`,
  `npm-security-audit`, `npm-dep-analysis`
- native: `popcorn`

### elixir-workflows
- `workflow-generator` (native)

## Hook-only plugins (no skills)

`code-quality`, `dev-discipline`, `marketplace-hygiene`, `git-commit` ship
hooks/commands only — see each plugin's `README.md`.
