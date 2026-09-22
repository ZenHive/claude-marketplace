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


## Plugins

| Plugin | Kind | Ships |
|---|---|---|
| `harness` | orchestration | `harness-driver` + `harness-workflow` skills, SessionStart stale-base guard. See `plugins/harness/README.md`. |
| `workflow` | methodology | rmap substrate, D/B/U prioritization, task-as-prompt authoring, pickup / plan-and-file modes, worktrees, upstream PRs, onchain verification. Skills only. |
| `elixir` | per-language | Four mechanic hooks (post-edit format/compile/matching test, pre-commit format/compile/unused-deps, destructive-command block, test.json / dialyzer.json rewrites) + skills for ZenHive's own Hex packages and conventions. See `plugins/elixir/README.md`. |
| `elixir-volt` | per-language | JS-on-BEAM stack skills (oxc, quickbeam, popcorn, npm_ex). Skills only. |
| `tools` | personal | CLI reference skills (himalaya, gloomberb). Skills only. |
| `dep-audit` | hygiene | SessionStart dependency-advisory nag across Hex / Cargo / npm. |

`workflow`, `elixir-volt` and `tools` carry no hooks and are safe to enable globally. Full skill catalog: `SKILLS.md`. Hook rule IDs: `HOOK-RULES.md`.

**What was deliberately removed (0.2.0):** review, delegation, dev-discipline, code-quality, git-commit, portfolio, elixir-workflows, marketplace-hygiene (now repo-local hooks), and the `elixir` plugin's reminder hooks and generic Elixir skills. Rationale in `CHANGELOG.md`: a current model does not need trigger-word nudges, and phxagents covers the framework layer.

## Recommended companion for Phoenix repos: phxagents.dev

zenhive is deliberately thin on Phoenix/LiveView/Ecto/Oban domain knowledge — the `elixir` plugin covers generic Elixir/OTP dev tooling, not the web framework itself. For repos built on Phoenix, [phxagents.dev](https://phxagents.dev) (`oliver-kriska/claude-elixir-phoenix`, MIT) is a recommended external companion: a deep Phoenix vertical (LiveView, Ecto, Oban, Ash, Tidewave, a Phoenix-specific "Iron Laws" rule set) that goes further into the framework than zenhive does or intends to.

The two compose rather than overlap: **zenhive** is "how we work" — harness orchestration, roadmap/task management, review, delegation, cross-cutting dev discipline, language-agnostic. **phxagents** is "Phoenix domain knowledge" — the runtime and framework layer. Nothing from phxagents is forked, vendored, or auto-installed here; it's a separate marketplace you opt into per repo:

```
/plugin marketplace add oliver-kriska/claude-elixir-phoenix
/plugin install elixir-phoenix
```

## Local development

```
/plugin marketplace add ./        # from this repo root, registers the local marketplace
/plugin install harness@zenhive
/reload-plugins                   # after editing plugin files
claude plugin validate --strict   # CI-grade manifest validation
```

Skills under `plugins/*/skills/` are **synced from canonical sources** (the harness repo and `~/.claude/includes/`), not hand-authored here — each carries a sync-note header pointing at its source. Edit the source and re-sync; don't edit the copy.
