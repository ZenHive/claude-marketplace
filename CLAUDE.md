# CLAUDE.md

@~/.claude/includes/verification-policy.md

Guidance for Claude Code working in this repository — the **`zenhive`** Claude
Code plugin marketplace (`ZenHive/claude-marketplace`, default branch `main`).

@~/.claude/includes/critical-rules.md

## What this is

A single Claude Code **marketplace** (`zenhive`) distributing six **independent
plugins**. A marketplace is the distribution unit; a plugin is the isolation
unit. Per-repo configurability comes from enabling/disabling plugins in
`enabledPlugins`, not from drawing marketplace boundaries. See `README.md` for
the roster and the phxagents boundary, `SKILLS.md` for the skill catalog, and
`CHANGELOG.md` for history.

The marketplace ships only what a current model does not carry and what
phxagents does not cover: harness orchestration, ZenHive's roadmap/workflow
methodology, ZenHive's own Hex packages, and a handful of deterministic
mechanic hooks. Generic Elixir/Phoenix knowledge, style nudges and
"model-limitation" reminder hooks were removed in 0.2.0; do not reintroduce
them. A hook earns its place by running a tool (format, compile, a test, a
git check), not by reminding the model of a rule it already has in
`critical-rules.md`.

## Includes → Skills sync (the load-bearing invariant)

**`~/.claude/includes/*.md` are canonical.** Most skill `SKILL.md` bodies in this
repo are auto-synced *from* those includes — never edit a synced `SKILL.md` body
directly (the repo-local MH-1 hook denies it and redirects you to the include).
The single source of truth for the mapping is `scripts/skill-include-map.sh`,
which drives **both**:

- `scripts/sync-skills-from-includes.sh` — writes synced bodies (preserves
  frontmatter, replaces body with include content).
- `scripts/hooks/block-skill-edits.sh` — denies direct edits to mapped files.
  Wired in this repo's `.claude/settings.json` (PreToolUse), together with
  `scripts/hooks/validate-marketplace-json.sh` (PostToolUse, MH-2). Rule IDs in
  `HOOK-RULES.md`.

After editing any include:

```bash
./scripts/sync-skills-from-includes.sh            # sync all mapped skills
./scripts/sync-skills-from-includes.sh --dry-run  # preview
```

The `harness` plugin's skills (`harness-driver`, `harness-workflow`) are **not**
in the map — they self-sync from their own canonical sources with per-file
headers. Native (hand-authored) skills are copied directly, not synced.

## Scripts (`scripts/`)

| Script | Purpose |
|---|---|
| `skill-include-map.sh` | Single source of truth for SKILL.md ↔ include mapping (sourced by the sync script and the block hook). |
| `sync-skills-from-includes.sh` | Sync mapped SKILL.md bodies from `~/.claude/includes/`. |
| `hooks/block-skill-edits.sh`, `hooks/validate-marketplace-json.sh` | Repo-local hooks (MH-1, MH-2). |
| `sync-agents-md.sh` | **Manual** AGENTS.md generator — inlines a repo's CLAUDE.md @-imports for Codex. Run from inside the target repo. |
| `sync-coderabbit-yaml.sh` | Sync the comments-only `.coderabbit.yaml` from `templates/` into a target repo. |
| `clear-cache.sh` | Clear zenhive plugin cache + stale registry entries (also sweeps legacy deltahedge/claude-code-elixir). |
| `migrate-repos-deltahedge-to-zenhive.sh` | Rename `@deltahedge` → `@zenhive` in a repo's `.claude/settings.json` (dry-run by default). |

## Roadmap

This repo uses `rmap` — `roadmap/tasks.toml` is canonical, `ROADMAP.md` +
`roadmap/data.json` are rendered. Propose plugin changes (hook misfires, missing
skills, command bugs) via `rmap new` here; don't edit installed copies in
`~/.claude/plugins/`. After any hand-edit of `tasks.toml`, run `rmap validate`.

## Validation

```bash
claude plugin validate --strict   # manifest validation (CI-grade)
```
