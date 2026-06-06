---
name: npm-dep-analysis
description: npm_ex dependency graph analysis, size optimization, and package quality scoring. Use when node_modules is too large, investigating why a package was pulled in, deduplicating dependencies, understanding the dependency graph shape (fan-in/fan-out/cycles), evaluating package quality, or optimizing install size. Covers mix npm.stats, npm.size, npm.tree, npm.why, npm.dedupe, npm.deps, and the programmatic NPM.DepGraph/NPM.Size/NPM.Why/NPM.Dedupe/NPM.PackageQuality/NPM.Health APIs with correct argument types and two-step patterns.
allowed-tools: Read, Bash
---

<!-- Auto-synced from ~/.claude/includes/npm-dep-analysis.md — do not edit manually -->

## npm_ex Dependency Graph Analysis & Size Optimization

Understand your dep tree, find heavy packages, reduce bloat.

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

### Gotchas

- `Dependency.Graph`: lockfile → `adjacency_list/1`; adj → everything else. Passing lockfile to `fan_out` crashes `(ArgumentError) not a list`.
- `Size.analyze/1`, `Size.top/2`: path strings, not lists. `top/2` re-analyzes.
- `Package.Quality.score/1`: single entry (`lockfile["name"]`), not whole lockfile.
- `Why.direct?/2`: checks lockfile keys — misleading; use `pkg_json`.
- `Diagnostics.Health.score/1`: checks map with `:lockfile`, `:pkg_json`, `:node_modules`.

### Optimization Playbook

1. `mix npm.stats` — transitive >> direct? Investigate heavy fan-out.
2. `mix npm.size` — top 10 largest.
3. `mix npm.why <pkg>` on each — chain necessary?
4. `mix npm.dedupe` — flatten duplicate versions where semver allows.
5. `mix npm.stats` again — measure improvement.
6. `mix npm.remove` for packages only used transitively by optional features.
