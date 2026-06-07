# CLAUDE.md

Guidance for Claude Code working in this repository — the **`zenhive`** Claude
Code plugin marketplace (`ZenHive/claude-marketplace`, default branch `main`).

@~/.claude/includes/critical-rules.md

<!-- Selective-load (Opus 4.8): only critical-rules is eager-imported — the
irreducible guardrail floor. Everything else (code-style, rmap, workflow, etc.)
is reachable on demand as a skill or a Read of ~/.claude/includes/*.md. Re-add an
@-import here only if Opus quality drops on that surface. -->

## What this is

A single Claude Code **marketplace** (`zenhive`) distributing ~14 **independent
plugins**. A marketplace is the distribution unit; a plugin is the isolation
unit. Per-repo configurability comes from enabling/disabling plugins in
`enabledPlugins`, not from drawing marketplace boundaries. See `README.md` for
the orchestration-vs-language split and `CHANGELOG.md` for the plugin roster.

This supersedes the older `deltahedge` marketplace
(`ZenHive/claude-marketplace-elixir`) — renamed to the org name and restructured.

## Includes → Skills sync (the load-bearing invariant)

**`~/.claude/includes/*.md` are canonical.** Most skill `SKILL.md` bodies in this
repo are auto-synced *from* those includes — never edit a synced `SKILL.md` body
directly (the `marketplace-hygiene` block hook denies it and redirects you to the
include). The single source of truth for the mapping is
`scripts/skill-include-map.sh`, which drives **both**:

- `scripts/sync-skills-from-includes.sh` — writes synced bodies (preserves
  frontmatter, replaces body with include content).
- `plugins/marketplace-hygiene/scripts/block-skill-edits.sh` — denies direct
  edits to mapped files.

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
| `skill-include-map.sh` | Single source of truth for SKILL.md ↔ include mapping (sourced by the two below + the block hook). |
| `sync-skills-from-includes.sh` | Sync mapped SKILL.md bodies from `~/.claude/includes/`. |
| `sync-agents-md.sh` | **Manual** AGENTS.md generator — inlines a repo's CLAUDE.md @-imports for Codex. Run from inside the target repo. (Was a delegation-plugin auto-hook; retired to manual in the zenhive migration.) |
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
