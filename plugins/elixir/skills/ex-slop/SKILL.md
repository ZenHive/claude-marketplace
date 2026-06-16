---
name: ex-slop
description: ex_slop — Credo plugin that flags AI-generated-code antipatterns in Elixir. Use when configuring Credo to catch AI-slop (over-commenting, redundant code, defensive cruft), wiring the plugin into .credo.exs, or reviewing generated-code quality. Covers all checks across Warning/Refactor/Readability categories, plugin wiring, and opt-in extras.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/ex-slop.md — do not edit manually -->

## ExSlop — Credo plugin for AI-generated code antipatterns

Catches patterns LLMs over-produce but experienced Elixir devs don't: blanket rescues, N+1 queries, narrator docs, obvious comments, anti-idiomatic Enum usage, try/rescue around non-raising functions, and more. 40 checks organized as Warning / Refactor / Readability.

**Min version: `{:ex_slop, "~> 0.1", only: [:dev, :test], runtime: false}`** (latest: 0.4.2, May 2026).
**31 checks enabled by default** when you register `{ExSlop, []}` as a plugin; 9 are opt-in (noisier style/perf).
**Credo plugin — not a standalone Mix task.** Runs inside your existing `mix credo --strict` gate.
**Intentional non-overlap with stock Credo** for doc/comment content and Ecto patterns; a few performance checks intentionally overlap so ExSlop can serve as a generated-code validation pipeline on its own.

**Caveat:** `ObviousComment` accepts `additional_keywords: []` to extend its keyword set — only check with per-check config. All others take `[]`.

**Does NOT cover:** runtime behavior, security (→ Sobelow), duplication (→ ex_dna), structural analysis (→ Reach), import ordering or formatting (→ `mix format`).

**Portfolio fit:** slots beside ex_dna in the PostToolUse hook chain; both target AI-generated code — ex_dna catches structural duplication, ExSlop catches semantic antipatterns. Add to the Credo pipeline that runs on each Edit/Write in tapakly and any project using `mix credo --strict`.

### Wiring `.credo.exs` (plugin registration)

```elixir
# .credo.exs — minimum: register the plugin, get 31 default checks
%{
  configs: [
    %{
      name: "default",
      plugins: [{ExSlop, []}]       # enables all 31 high-signal checks automatically
    }
  ]
}
```

To cherry-pick specific checks (opt-in, or disable defaults), add them to the `checks` list:

```elixir
# Opt-in extras — add to checks: section alongside the plugin registration
{ExSlop.Check.Refactor.ListLast, []},                    # avoid List.last/1 after traversal
{ExSlop.Check.Readability.UnaliasedModuleUse, []},       # module used 2+ times without alias
{ExSlop.Check.Readability.DocFalseOnPublicFunction, []}, # cargo-culted @doc false on def
```

`ObviousComment` keyword extension:

```elixir
{ExSlop.Check.Readability.ObviousComment, [additional_keywords: ["initialize", "execute"]]}
```

### Warning Checks (7) — highest severity, default-enabled

| Check | Pattern caught | Preferred fix |
|---|---|---|
| `BlanketRescue` | `rescue _ -> nil` / `rescue _e -> {:error, "..."}` | Narrow to specific exception |
| `RescueWithoutReraise` | `rescue e -> Logger.error(...); :error` | Re-raise or propagate |
| `RepoAllThenFilter` | `Repo.all(User) \|> Enum.filter(& &1.active)` | Filter in SQL/Ecto query |
| `QueryInEnumMap` | `Enum.map(users, fn u -> Repo.get(...) end)` | Preload or batch query (N+1) |
| `GenserverAsKvStore` | GenServer that's just `Map.get/put` on state | Use ETS or `Agent` |
| `PathExpandPriv` | `Path.expand("...priv...", __DIR__)` | `Application.app_dir/2` |
| `DualKeyAccess` | `m[:key] \|\| m["key"]`, `Map.get(m, :k) \|\| Map.get(m, "k")` | Normalize key type once |

### Refactor Checks (27)

| Check | Bad | Good |
|---|---|---|
| `FilterNil` | `Enum.filter(fn x -> x != nil end)` | `Enum.reject(&is_nil/1)` |
| `RejectNil` | `Enum.reject(fn x -> x == nil end)` | `Enum.reject(&is_nil/1)` |
| `ReduceAsMap` | `Enum.reduce([], fn x, acc -> [f(x) \| acc] end)` | `Enum.map(&f/1)` |
| `MapIntoLiteral` | `Enum.map(...) \|> Enum.into(%{})` | `Map.new(...)` |
| `IdentityPassthrough` | `case r do {:ok, v} -> {:ok, v}; {:error, e} -> {:error, e} end` | `r` |
| `IdentityMap` | `Enum.map(fn x -> x end)` | Remove the call |
| `CaseTrueFalse` | `case flag do true -> a; false -> b end` | `if flag, do: a, else: b` |
| `TryRescueWithSafeAlternative` | `try do String.to_integer(x) rescue _ -> nil end` | `Integer.parse(x)` |
| `WithIdentityElse` | `with {:ok, v} <- f() do v else {:error, r} -> {:error, r} end` | Drop the `else` |
| `WithIdentityDo` | `with {:ok, v} <- f() do {:ok, v} end` | `f()` |
| `SortThenReverse` | `Enum.sort() \|> Enum.reverse()` | `Enum.sort(:desc)` |
| `StringConcatInReduce` | `Enum.reduce("", fn x, acc -> acc <> x end)` | `Enum.join/1` or IO data |
| `ReduceMapPut` | `Enum.reduce(%{}, fn x, acc -> Map.put(acc, k, v) end)` | `Map.new/2` |
| `RedundantBooleanIf` | `if cond, do: true, else: false` | Use the condition directly |
| `FlatMapFilter` | `Enum.flat_map(fn x -> if cond, do: [x], else: [] end)` | `Enum.filter/2` |
| `RedundantEnumJoinSeparator` | `Enum.join(parts, "")` | `Enum.join(parts)` |
| `UseMapJoin` | `Enum.map(...) \|> Enum.join(...)` | `Enum.map_join(...)` |
| `PreferEnumSlice` | `Enum.drop(n) \|> Enum.take(k)` | `Enum.slice(enum, n, k)` |
| `GraphemesLength` | `String.graphemes(s) \|> length()` | `String.length(s)` |
| `ManualStringReverse` | `String.graphemes(s) \|> Enum.reverse() \|> Enum.join()` | `String.reverse(s)` |
| `SortThenAt` | `Enum.sort() \|> Enum.at(0)` | `Enum.min/1` / `Enum.max/1` |
| `SortForTopK` | `Enum.sort() \|> Enum.take(1)` | `Enum.min/1` / top-k selection |
| `ListFold` | `List.foldl(list, acc, fun)` | `Enum.reduce(list, acc, fun)` |
| `ListLast` | `List.last(list)` | Avoid needing last after traversal |
| `LengthInGuard` | `def f(xs) when length(xs) == 0` | Pattern match on `[]` / `[_ \| _]` |
| `LengthComparison` | `if length(xs) == 0`, `length(xs) <= 5` | Pattern match or `Enum.count_until/2` |
| `ExplicitSumReduce` | `Enum.reduce(nums, 0, fn n, acc -> n + acc end)` | `Enum.sum(nums)` |

### Readability Checks (6)

| Check | What it catches |
|---|---|
| `NarratorDoc` | `@moduledoc "This module provides functionality for..."` |
| `DocFalseOnPublicFunction` | Multiple `@doc false` on `def` in one module (cargo-culted) |
| `BoilerplateDocParams` | `## Parameters\n- conn: The connection struct` (redundant) |
| `ObviousComment` | `# Fetch the user` above `Repo.get(User, id)` |
| `StepComment` | `# Step 1: Validate input` (procedural numbered steps) |
| `NarratorComment` | `# Here we fetch` / `# Now we validate` / `# Let's create` |
| `UnaliasedModuleUse` | Module referenced 2+ times without `alias` |

### Companion Credo Built-ins (AI slop complement)

These stock Credo checks pair well — enable them alongside ExSlop:

```elixir
{Credo.Check.Warning.ExpensiveEmptyEnumCheck, []},     # length(list) == 0 → list == []
{Credo.Check.Refactor.AppendSingleItem, []},           # acc ++ [item] → [item | acc]
{Credo.Check.Refactor.DoubleBooleanNegation, []},      # !!var cast-to-boolean
{Credo.Check.Refactor.CondStatements, []},             # case x do true/false → if/else
{Credo.Check.Refactor.MapMap, []},                     # map |> map → single map
{Credo.Check.Refactor.FilterFilter, []},               # filter |> filter → single filter
{Credo.Check.Refactor.RejectReject, []},               # reject |> reject → single reject
{Credo.Check.Refactor.FilterCount, []},                # Enum.count(enum) > 0 → Enum.any?/1
{Credo.Check.Refactor.NegatedConditionsInUnless, []},  # unless !cond → if cond
{Credo.Check.Refactor.UnlessWithElse, []}              # unless/else → if/else
```

### Common Issues

| Problem | Cause | Fix |
|---|---|---|
| ExSlop checks not appearing in `mix credo` | Plugin not registered in `.credo.exs` | Add `plugins: [{ExSlop, []}]` to the named config block |
| `ObviousComment` false positive on domain terms | Default keyword set too broad | Add `additional_keywords: []` option with only the words you want, or disable the check |
| Refactor check fires on intentional code | Legitimate pattern that matches a heuristic | Cherry-pick checks instead of using `{ExSlop, []}` bulk registration; disable specific checks in `checks: [false: [...]]` |
| Overlap with stock Credo output | Some perf checks intentionally overlap | Expected — ExSlop serves as a standalone AI-code gate; suppress duplicates in CI if running both |

### DO NOT

1. Add ExSlop to `:prod` deps — it's a dev/test linter only.
2. Use `{ExSlop, []}` plugin registration AND manually list the same check in `checks:` — it will run twice.
3. Disable entire Warning category to quiet noise — narrow the specific check instead.
4. Expect ExSlop to catch formatting or import issues — those belong to `mix format` and Credo's built-ins.
5. Confuse `ListLast/1` with a hard ban — it's a smell flag for traversal-then-last patterns, not a prohibition on `List.last` in all contexts.

### Testing Notes

ExSlop has no test helpers — assertions live in your normal Credo test pass. To verify a check fires:

```bash
# Run the full slop gate in isolation
mix credo --strict --checks ExSlop.Check.Warning.BlanketRescue

# Targeted: only Warning checks (useful in CI to treat warnings as errors)
mix credo --strict
```

ExSlop respects the standard Credo `# credo:disable-for-next-line` inline suppression syntax.

### Dependencies

```elixir
{:ex_slop, "~> 0.1", only: [:dev, :test], runtime: false}
# Requires :credo as a dep (ex_slop is a Credo plugin, not standalone)
```

Credence (MIT, `hex.pm/packages/credence`) inspired several semantic-performance checks.
