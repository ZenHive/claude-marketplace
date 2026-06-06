# ZenHive Claude Code Marketplace

A single Claude Code **marketplace** (`zenhive`) distributing a set of **independent plugins**. Install the whole marketplace once; enable only the plugins a given repo needs.

```
/plugin marketplace add ZenHive/claude-marketplace
/plugin install harness@zenhive
```

## Separation of concerns

The guiding split: **a marketplace is the distribution unit; a plugin is the isolation unit.** One marketplace registers many plugins, each with its own `plugin.json`, its own version, and its own per-repo on/off toggle in `enabledPlugins`. Per-repo configurability comes from enabling/disabling plugins — not from drawing marketplace boundaries.

Plugins fall into two kinds, kept deliberately separate:

| Kind | Example | Scope |
|---|---|---|
| **Orchestration** | `harness` | Language-agnostic. Drives the implement → review → land loop over harness's MCP surface. Applies to *any* consuming repo regardless of language. |
| **Per-language dev tooling** | `elixir`, (future) `rust` | Language-specific hooks, skills, and commands (formatters, test runners, idiom checks). Enabled only in repos of that language. |

A repo composes the plugins it wants: an Elixir service driven by harness enables `harness@zenhive` + `elixir@zenhive`; a Rust service enables `harness@zenhive` + a future `rust@zenhive`; a non-harness repo enables just the language plugin. The orchestration surface never drags language tooling into a repo that doesn't want it, and vice versa.

## Why this exists / migration note

This marketplace supersedes the older `deltahedge` marketplace (`ZenHive/claude-marketplace-elixir`), rebranded to the `zenhive` org name and restructured so orchestration and per-language concerns are distinct plugins rather than one Elixir-centric bundle. The rename changes every plugin id (`x@deltahedge` → `x@zenhive`), so adopting it is a one-time cutover of `enabledPlugins` keys in `~/.claude/settings.json` and per-repo settings. Because the marketplace names differ, the old and new marketplaces can be registered simultaneously during a plugin-by-plugin migration; unregister `deltahedge` once everything has moved.

> **Forward note (future session):** `elixir@deltahedge` currently bundles workflow concerns (worktree, Linear) that are not language-specific. A later refactor will extract those into their own plugin here, leaving `elixir` as pure Elixir dev tooling. No action needed now — recorded so a future Claude Code session knows the intended end state.

## Plugins

- **`harness`** — orchestration surface for the harness OTP engine. Two skills (`harness-driver` = API/MCP contract, `harness-workflow` = the loop) plus a SessionStart stale-base guard hook. See `plugins/harness/README.md`.

## Local development

```
/plugin marketplace add ./        # from this repo root, registers the local marketplace
/plugin install harness@zenhive
/reload-plugins                   # after editing plugin files
claude plugin validate --strict   # CI-grade manifest validation
```

Skills under `plugins/*/skills/` are **synced from canonical sources** (the harness repo and `~/.claude/includes/`), not hand-authored here — each carries a sync-note header pointing at its source. Edit the source and re-sync; don't edit the copy.
