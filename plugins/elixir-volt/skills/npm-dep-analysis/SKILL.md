---
name: npm-dep-analysis
description: npm_ex dependency graph analysis, size optimization, and package quality scoring. Use when node_modules is too large, investigating why a package was pulled in, deduplicating dependencies, understanding the dependency graph shape (fan-in/fan-out/cycles), evaluating package quality, or optimizing install size. Covers mix npm.stats, npm.size, npm.tree, npm.why, npm.dedupe, npm.deps, and the programmatic NPM.DepGraph/NPM.Size/NPM.Why/NPM.Dedupe/NPM.PackageQuality/NPM.Health APIs with correct argument types and two-step patterns.
allowed-tools: Read, Bash
---

<!-- Auto-synced from ~/.claude/includes/npm-dep-analysis.md — do not edit manually -->

## npm_ex Dependency Graph Analysis & Size Optimization

Understand your dep tree, find heavy packages, reduce bloat.

**`{:npm, "~> 0.7.6"}`** — Windows filesystem-root traversal fix + nested-dep conflict resolution + lockfile persistence for nested subtrees (0.7.6).

### Caveat / Does NOT cover

- Does not install or manage packages — use `mix npm.install` / `mix npm.get` for that
- `NPM.Package.Quality` scores are relative comparisons only; lockfile metadata is too sparse for absolute quality judgments
- `mix npm.dedupe` suggests deduplication candidates; it does not rewrite `package.json` for you

### Investigation Workflow

```bash
mix npm.stats            # overview — direct vs transitive counts
mix npm.size             # disk usage
mix npm.why <package>    # why is this installed?
mix npm.tree             # full tree
mix npm.dedupe           # flatten duplicate versions
```

### Dependency Graph (`NPM.Dependency.Graph`)

**Two-step pattern:** `adjacency_list/1` takes lockfile; everything else takes the adjacency list.

```elixir
{:ok, lockfile} = NPM.Lockfile.read()
adj = NPM.Dependency.Graph.adjacency_list(lockfile)

NPM.Dependency.Graph.fan_out(adj)    # pkg → num deps pulled in (high = bloat risk)
NPM.Dependency.Graph.fan_in(adj)     # pkg → num dependents (high = critical)
NPM.Dependency.Graph.roots(adj)      # direct dependencies
NPM.Dependency.Graph.leaves(adj)     # no sub-deps
NPM.Dependency.Graph.cycles(adj)     # [] = healthy
```

### Size Analysis (`NPM.Size`)

```elixir
sizes = NPM.Size.analyze("node_modules")    # PATH string; sorted largest first
# => [%{name: "typescript", size: 66_849_652, version: "4.9.5", file_count: 108}, ...]

NPM.Size.top("node_modules", 5)             # PATH string — re-analyzes, not "take N"
NPM.Size.total_size(sizes)                  # bytes
NPM.Size.total_files(sizes)
NPM.Size.format_size(66_849_652)            # "63.8 MB"
NPM.Size.summary(sizes)
```

### Dependency Tracing (`NPM.Why`)

```elixir
{:ok, lockfile} = NPM.Lockfile.read()
{:ok, pkg_json} = NPM.Package.JSON.read()

NPM.Why.explain("ws", lockfile, pkg_json)
# => [%{path: ["ccxt", "ws"], range: "^8.8.1", direct: false}]

NPM.Why.dependents("ws", lockfile)
NPM.Why.format_reasons(reasons)
```

**`NPM.Why.direct?/2` is misleading** — checks lockfile key presence, so transitive deps appearing as top-level lockfile entries report `true`. Use `Map.has_key?(pkg_json, name)` for a real direct check.

### Deduplication (`NPM.Dependency.Dedupe`)

```elixir
NPM.Dependency.Dedupe.find_duplicates(lockfile)       # [%{name:, versions:, ...}]
NPM.Dependency.Dedupe.summary(lockfile)               # %{total_packages:, duplicate_groups:, saveable:, unique_packages:}
NPM.Dependency.Dedupe.best_shared_version("lodash", lockfile)
NPM.Dependency.Dedupe.savings_estimate(lockfile)
```

### Package Quality (`NPM.Package.Quality`)

Takes a **single lockfile entry**, not the whole lockfile:

```elixir
entry = lockfile["ccxt"]
NPM.Package.Quality.score(entry)            # 0-100
NPM.Package.Quality.grade(entry)            # "A"-"F"
NPM.Package.Quality.missing_fields(entry)
NPM.Package.Quality.rank(lockfile)
NPM.Package.Quality.average(lockfile)
```

Scores will be low — lockfile metadata is sparse (no description/keywords/engines). More useful as comparison between packages than as absolute score.

### Project Health (`NPM.Diagnostics.Health`)

Takes a **checks map**, not just a lockfile. Sibling diagnostics live under `NPM.Diagnostics.*` (`Doctor`, `EngineCheck`, `EnvCheck`).

```elixir
health = NPM.Diagnostics.Health.score(%{
  lockfile: lockfile, pkg_json: pkg_json, node_modules: "node_modules"
})
# => %{score: 25, details: %{has_lockfile:, has_package_json:, has_license:,
#       integrity_coverage:, no_deprecated:, up_to_date:, no_vulnerabilities:}}

NPM.Diagnostics.Health.grade(health)                   # "D"
NPM.Diagnostics.Health.recommendations(health)
```

### Common Issues

| Symptom | Cause | Fix |
|---|---|---|
| `(ArgumentError) not a list` on `fan_out/1` | Passed lockfile directly instead of adj | `adjacency_list(lockfile)` first |
| `top/2` is slow | Re-analyzes from disk every call | Cache `analyze/1` result; call `top` only for display |
| `Quality.score/1` crashes | Passed whole lockfile | Pass single entry: `lockfile["pkg-name"]` |
| `Why.direct?/2` returns `true` for transitive | Checks lockfile keys, not `package.json` | Use `Map.has_key?(pkg_json, name)` |
| `Health.score/1` raises | Passed lockfile directly | Pass `%{lockfile:, pkg_json:, node_modules:}` map |
| Nested dep missing after reinstall | Pre-0.7.5 lockfile lacks nested metadata | Run `mix npm.install` once to regenerate; 0.7.5+ persists nested subtrees |
| Scoped package (`@scope/pkg`) nested conflict unresolved | Pre-0.7.5 conflict resolver didn't handle scoped names | Upgrade to 0.7.5; re-run `mix npm.install` |
| `node_modules` traversal hangs or errors on Windows | Pre-0.7.6 traversal didn't stop correctly at filesystem roots (e.g. `C:\`) | Upgrade to 0.7.6 |

### DO NOT

- Do not call `Size.top/2` in a tight loop — it re-analyzes from disk on each call; call `analyze/1` once and slice the result
- Do not treat `Quality.score` as an absolute signal — lockfile entries lack enough metadata; use it for relative ranking only
- Do not rely on `Why.direct?/2` to distinguish real direct deps from hoisted transitive ones — use `pkg_json` directly

### Optimization Playbook

1. `mix npm.stats` — transitive >> direct? Investigate heavy fan-out.
2. `mix npm.size` — top 10 largest.
3. `mix npm.why <pkg>` on each — chain necessary?
4. `mix npm.dedupe` — flatten duplicate versions where semver allows.
5. `mix npm.stats` again — measure improvement.
6. `mix npm.remove` for packages only used transitively by optional features.

### Dependencies

```elixir
# mix.exs
{:npm, "~> 0.7.6"}
```

No runtime Elixir dependencies beyond the standard library. Requires Node.js on `PATH` for the mix tasks; the Elixir API modules (`NPM.Dependency.Graph`, `NPM.Size`, etc.) work against lockfile data without Node.

**Portfolio fit:** used in `elixir-volt` repos (tapakly, etc.) to audit `node_modules` bloat and trace why heavy packages like `ccxt` pull in a given transitive dep.
