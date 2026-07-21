# Changelog

All notable changes to the `zenhive` Claude Code marketplace are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/); versions
track `.claude-plugin/marketplace.json` `metadata.version`.

## [Unreleased]

### Added

- **`tools`** (new plugin) — personal/utility CLI-usage reference skills.
  Skill: `himalaya` (synced ← himalaya.md), registering the existing
  `~/.claude/includes/himalaya.md` include as a self-invocable skill.
- **README** — recommends [phxagents.dev](https://phxagents.dev)
  (`oliver-kriska/claude-elixir-phoenix`, MIT) as an optional companion
  marketplace for Phoenix repos, with the boundary stated: zenhive is
  orchestration/workflow, phxagents is Phoenix domain knowledge. Not
  forked, vendored, or bundled — install separately per repo.

### Changed

- **`harness` 0.2.7 → 0.2.8** — aligns the driver and dogfooding contracts
  with portfolio-wide inline routing while preserving the reviewer's intentional
  fix-and-approve role for dispatched work.
- **`harness` 0.2.6 → 0.2.7** — routes bounded local work inline by default
  and reserves the full implement→review→land cycle for tasks with a positive
  safety, evidence, or parallelism reason.
- **`dev-discipline` 0.2.0 → 0.3.0** — added a fourth `roadmap/tasks.toml`
  integrity guard: `tasks-toml-block-stale-model.sh` (PreToolUse
  Edit/Write/MultiEdit) **blocks** any edit introducing `model = "gpt-5-codex"`
  into a `tasks.toml`. That model id is absent from the codex catalog and is
  operator-blocked (subscription Codex accounts can't run it); because a
  per-task `model` pin overrides `agent_model.codex`, a stale pin silently
  breaks dispatch (codex → "unavailable", claude adapter →
  "invalid_model_for_adapter"). The deny message points to the valid
  `gpt-5.5`. Distributes to every repo that enables the plugin.
- **`elixir` 0.2.5 → 0.2.6** — rescued the `nexus-template` skill from the
  retired `phoenix` plugin (org/template-specific artifact not covered by
  phxagents.dev).
- **`elixir` 0.2.6 → 0.2.7**, **`elixir-volt` 0.1.1 → 0.1.2**, **`harness`
  0.2.5 → 0.2.6**, **`tasks` 0.1.5 → 0.1.6** — skill-include sync: upstream
  version bumps (`ex-ast`, `npm-security-audit`, `oxc`) plus content updates
  (`integration-testing` reality-first workflow, `harness-workflow` reviewer-
  owned external-evidence judgment, `rmap`/`task-writing`/`roadmap-planning`
  verified-by/verification-ref provenance fields) and the stale `--verified`
  example fix.

### Removed

- **`phoenix` plugin** — retired. phxagents.dev covers Phoenix/LiveView setup
  (phx.gen.auth, Sobelow, LiveDebugger, formatter) far deeper than
  `phoenix-setup` did; that skill is dropped. `nexus-template` (a Nexus admin
  dashboard template phxagents does not cover) survives as `elixir:nexus-template`.

## [0.1.0] — 2026-06-08

Initial `zenhive` marketplace. Supersedes the older `deltahedge` marketplace
(`ZenHive/claude-marketplace-elixir`), rebranded to the org name and
restructured so orchestration and per-language concerns are distinct plugins
rather than one Elixir-centric bundle.

### Added — plugins (14)

- **`harness`** — orchestration surface for the harness OTP engine (implement →
  review → land loop). Skills: `harness-driver`, `harness-workflow`. SessionStart
  stale-base guard hook.
- **`workflow`** — language-agnostic dev workflow: `git-worktrees`,
  `dev-lifecycle` (+ command), `workflow-philosophy`, `upstream-pr-workflow`.
- **`tasks`** — rmap roadmap substrate + D/B/U scoring: `rmap`, `task-driver`,
  `task-writing`, `roadmap-planning`.
- **`review`** — staged review chain: `code-review`, `audit-review` (+ commands +
  SessionStart unaudited-tail hook).
- **`delegation`** — Linear-as-queue + cloud-agent delegation: `linear-queue`,
  `agent-dispatch`, `agent-pr-review`, `flow-review`, `delegation-rules`,
  `cloud-agent-environments`, `sprite-claude-code`.
- **`portfolio`** — power-law portfolio decision framework: `portfolio-strategy`.
- **`git-commit`** — AI-assisted commit workflow (`/git-commit:commit`).
- **`code-quality`** — LLM pre-commit gate (TODO / stub / silent-workaround
  blocker hook).
- **`dev-discipline`** — pause-and-pick PreToolUse ceremony reminders.
- **`marketplace-hygiene`** — blocks edits to auto-synced SKILL.md files +
  validates marketplace/plugin/hooks JSON on every edit.
- **`elixir`** — Elixir/OTP per-edit check hooks + core skills (16).
- **`elixir-volt`** — JS-on-BEAM stack (Volt/Phoenix client toolchain + npm
  hygiene), skills only.
- **`phoenix`** — Phoenix setup/template skills.
- **`elixir-workflows`** — workflow-generator plugin + command.

### Changed — vs `deltahedge`

- Renamed for consistency: `task-driver`→`tasks`, `staged-review`→`review`,
  `cloud-delegation`→`delegation`, `portfolio-strategy`→`portfolio`;
  `dev-lifecycle` folded into the new `workflow` plugin.
- Split concerns out of the old 26-skill `elixir` grab-bag into `workflow`,
  `tasks` (`roadmap-planning`), and the new `elixir-volt`.
- Every plugin id changes `x@deltahedge` → `x@zenhive`; adopting is a one-time
  `enabledPlugins` cutover (see README).

### Removed

- The `delegation` plugin's PostToolUse `agents-md-sync.sh` auto-sync hook. The
  AGENTS.md generator survives as a **manual** tool at
  `scripts/sync-agents-md.sh` — run it from inside a target repo. Re-wrap it in
  a hook if portfolio-wide auto-sync is wanted again.
