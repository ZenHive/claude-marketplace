---
name: reach
description: Reach — Program Dependence Graph (PDG/SDG) for Elixir, Erlang, Gleam, and compiled BEAM. Use when doing static analysis, backward/forward slicing, taint analysis, dead-code detection, OTP state-machine analysis, impact analysis, or visualizing call graphs via `mix reach`. Also use for cross-language Elixir↔JavaScript graph stitching via Reach.Plugins.QuickBEAM, codebase-level analysis (coupling, hotspots, depth, effects, xref, boundaries, concurrency), or building Reach.Project SDGs across modules. Covers source vs BEAM frontends, dynamic dispatch capture, the `Reach.Plugin` behaviour, and the 1.7 frontend additions.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/reach.md — do not edit manually -->

## Reach: Program Dependence Graph for Elixir

Builds PDG/SDG from Elixir, Erlang, Gleam, or compiled BEAM. Backward/forward slicing, taint analysis, independence checks, dead-code detection, OTP state-machine analysis, `mix reach` HTML viz.

**Min version: `{:reach, "~> 2.7"}`.** Requires `ex_ast ~> 0.12.0` at the dep level. Optional `:boxart, "~> 0.3.3"` for terminal `--graph` rendering.

**Canonical CLI — five commands:** `mix reach.map` (project view), `reach.inspect TARGET` (target-local), `reach.trace` (taint + slicing), `reach.check` (CI gates), `reach.otp` (process / state-machine analysis). `TARGET` accepts `Module.function/arity` or `file:line`.

**`.reach.exs`** at project root drives `reach.check --arch`/`--changed`/`--candidates`. Keys: `layers`, `deps[:forbidden]`, `source[:forbidden_modules]`/`forbidden_files`, `calls[:forbidden]`, `effects[:allowed]`, `boundaries[:public]`/`internal`/`internal_callers`, `risk[:changed]`, `candidates`, `smells`, `tests`. See § `.reach.exs` Architecture Policy below.

**Advisory refactoring candidates** (`reach.check --candidates`, `reach.inspect TARGET --candidates`): `introduce_boundary`, `isolate_effects`, `extract_pure_region`, `break_cycle` — each carries `confidence`, `actionability`, `proof`, and (for cycles) `representative_calls`. Suggestions, not auto-edits.

**Programmatic API** (stable, unchanged across 2.x): `Reach.file_to_graph!`, `string_to_graph`, `module_to_graph`, `ast_to_graph`, `compiled_to_graph`, `backward_slice`, `forward_slice`, `chop`, `context_sensitive_slice`, `taint_analysis`, `dead_code`, `independent?`, `Reach.Plugin` behaviour, `Reach.Project`, `Reach.Frontend.JavaScript`, `Reach.Plugins.QuickBEAM`. Umbrella source scanning includes `apps/*/lib/**/*.ex`.

**Caveat:** `dead_code` false positives are near-zero but not zero — treat as hint material.

**Does NOT cover:** runtime execution (static only), type inference (→ Dialyzer), dep security audit (→ Sobelow, npm_ex audit).

### Two Frontends

Both capture dynamic dispatch. Remaining differences:

| | Source (`file_to_graph!`, `string_to_graph`) | BEAM (`module_to_graph`) |
|---|---|---|
| Dynamic dispatch (`fn_var.(args)`, `state.handler.(args)`) | Captured as `kind: :dynamic` | Captured as `kind: :dynamic` |
| Macro-expanded code | Invisible | Visible |
| `use GenServer` generated callbacks | Invisible | Visible |
| Source spans | Always available | Always available |
| `Reach.Project` cross-module SDG | **Supported** | **Not supported** — `Reach.Project` is source-only |
| Scope | Single file or project glob | Single module |

**Use BEAM when:** you need macro expansion or `use GenServer`-generated callbacks. Otherwise source is faster, supports project-wide SDG, and handles dynamic dispatch correctly.

### Building a Graph

```elixir
graph = Reach.file_to_graph!("lib/my_module.ex")
{:ok, graph} = Reach.string_to_graph("def foo(x), do: x + 1")
{:ok, graph} = Reach.file_to_graph("src/my_module.erl")    # Erlang
{:ok, graph} = Reach.file_to_graph("src/app.gleam")        # Gleam (needs glance)
{:ok, graph} = Reach.ast_to_graph(ast)                     # pre-parsed
{:ok, graph} = Reach.module_to_graph(MyApp.Accounts)       # BEAM — macros + generated callbacks

# Whole project (source frontend only)
project = Reach.Project.from_mix_project()
project = Reach.Project.from_glob("lib/**/*.ex")

# JavaScript — returns IR nodes (NOT a graph), consumed by Reach.Plugins.QuickBEAM
{:ok, js_nodes} = Reach.Frontend.JavaScript.parse("function f(x) { return x + 1 }")
{:ok, js_nodes} = Reach.Frontend.JavaScript.parse_file("priv/handler.js")
```

### Structural Queries

```elixir
Reach.nodes(graph)
Reach.nodes(graph, type: :call, module: :gun, function: :ws_send)
Reach.nodes(graph, type: :call, kind: :dynamic)
Reach.nodes(graph, type: :function_def, name: :handle_info)

# node.type         :call | :function_def | :var | :match | :case | ...
# node.meta         %{module:, function:, arity:, kind: :remote | :local | :dynamic}
# node.source_span  %{file:, start_line:, ...}
# node.id           opaque handle for slice/taint
```

### Slicing

```elixir
Reach.backward_slice(graph, node.id)              # what affects this node?
Reach.forward_slice(graph, node.id)               # what does this node affect?
Reach.chop(graph, source_id, sink_id)             # all paths A→B
Reach.context_sensitive_slice(graph, node.id)     # Horwitz-Reps-Binkley interprocedural
Reach.Project.taint_analysis(project, ...)        # project-level (source)
```

### Taint Analysis

```elixir
# Single-graph — result: %{source:, sink:, path: [node_id], sanitized: bool}
results = Reach.taint_analysis(graph,
  sources: [type: :call, function: :params],
  sinks: [type: :call, module: System, function: :cmd],
  sanitizers: [type: :call, function: :sanitize]
)

# Cross-module (source frontend; dynamic-dispatch sinks reachable)
Reach.Project.taint_analysis(project,
  sources: [type: :call, function: :params],
  sinks: &(&1.type == :call and &1.meta[:kind] == :dynamic)
)
```

Source/sink/sanitizer specs: keyword list (matched against `node.type` + `node.meta`) or predicate `(node -> boolean)`.

### Independence / Reordering

```elixir
Reach.independent?(graph, a.id, b.id)                    # safe to reorder?
Reach.depends?(graph, id_a, id_b)
Reach.data_flows?(graph, source_id, sink_id)
Reach.passes_through?(graph, source_id, mid_id, sink_id)
Reach.controls?(graph, control_id, controlled_id)
Reach.canonical_order(graph, node_ids)                   # topo-sort
```

Two public GenServer client functions on the same PID correctly report `independent?: false` (they mutate shared server state).

### Effects

```elixir
Reach.pure?(node)
Reach.classify_effect(node)       # :pure | {:io, ...} | {:send, ...} | ...
Reach.Effects.classify(node)
Reach.Effects.effectful?(node, kind)
Reach.Effects.conflicting?(a, b)
```

Built-in classification covers Enum, Map, String, Process, :ets, :code, Node, System, Access, Calendar, Date, Time, `:atomics`/`:counters`/`:persistent_term`, and 30+ more. `Enum.each` → `:io`, `Application.get_env` → `:read`, term-store ops → `:read`/`:write`. Effects of local functions are inferred via fixed-point iteration. On Elixir 1.19+ the classifier reads the `ExCk` BEAM chunk for compiler-inferred type signatures (gracefully disabled on older Elixir).

**Plugin `classify_effect/1` callback.** Plugins teach the classifier about framework calls. All built-ins implement it — Phoenix assigns/route helpers → `:pure`, Ecto queries → `:pure`, Repo reads → `:read`, writes → `:write`, Oban `insert` → `:write`, GenStage/Jido signal dispatch → `:send`, OpenTelemetry spans → `:io`, Jason → `:pure`, Poison → `:pure` (split out of the Jason plugin into `Reach.Plugins.Poison`).

**Alias/import/field access.** `alias Plausible.Ingestion.Event; Event.build()` resolves correctly (incl. `:as`, multi-alias `{}`). `import Ecto.Query` then bare `from(...)` resolves to `Ecto.Query.from` (honours `:only`/`:except`). `socket.assigns`, `conn.params`, `state.count` are tagged `kind: :field_access` (pure), not fake remote calls. Compile-time noise (`@doc`, `use`, `::`, `__aliases__`) is classified `:pure`.

### Dead Code

```elixir
for node <- Reach.dead_code(graph) do
  IO.warn("#{node.source_span.start_line}: unused #{node.type}")
end
```

False positives are kept low via fixed-point alive expansion, branch-tail return tracing, guard exclusion, comprehension generator/filter exclusion, an impure-module blocklist (Process, :code, :ets, Node, System, …), typespec exclusion, macro-aware filtering (source-first macro/DSL facts via `Reach.MacroFact`, refined by plugins — Phoenix `Component.attr/3`/`slot/3`, router macros, Ecto schema fields, migration `table`/`column` declarations skip without hardcoded allowlists), and impure-call descendant marking. Still a hint source — verify before deleting.

### Canonical CLI (`mix reach.*`)

Five commands replace the 16 legacy tasks. `--format text` (default, colored), `json`, or `oneline`. ANSI auto-disables when piped. Analysis commands accept a positional path filter where applicable (e.g. `mix reach.map lib/my_app/`).

CLI option parsing is strict — unknown switches raise instead of being silently ignored, and the legacy Mix task shims are gone, so reach for the five canonical commands above.

**`mix reach.map`** — project bird's-eye view.

```bash
mix reach.map                                # default: modules summary
mix reach.map --modules                      # inventory, OTP/LiveView detection
mix reach.map --coupling --sort instability  # afferent/efferent, Martin's instability, cycles
mix reach.map --coupling --orphans           # unreferenced modules
mix reach.map --hotspots                     # complexity × caller count (with clause breakdown)
mix reach.map --depth --top 20               # dominator-tree depth (control-flow nesting)
mix reach.map --effects                      # effect distribution + top unclassified calls
mix reach.map --boundaries --min 2           # functions with multiple distinct side effects
mix reach.map --data                         # cross-function data flow via SDG
```

**`mix reach.inspect TARGET`** — target-local view. `TARGET` accepts `Module.function/arity` or `file:line`.

```bash
mix reach.inspect MyApp.Accounts.register/2 --context
mix reach.inspect MyApp.Accounts.register/2 --deps        # direct callers, callee tree, shared writers
mix reach.inspect MyApp.Accounts.register/2 --impact      # transitive callers, risk
mix reach.inspect MyApp.Accounts.register/2 --data --variable user
mix reach.inspect MyApp.Accounts.register/2 --why MyApp.Auth.login/1
mix reach.inspect MyApp.Accounts.register/2 --candidates  # advisory refactoring (see below)
mix reach.inspect lib/my_app/accounts.ex:45 --graph
```

**`mix reach.trace`** — taint flow + slicing.

```bash
mix reach.trace --from conn.params --to Repo                        # taint
mix reach.trace --from conn.params --to System.cmd --all
mix reach.trace --variable token --in MyApp.Auth.login/2            # variable trace
mix reach.trace MyApp.Accounts.register/2                           # backward slice (default)
mix reach.trace lib/my_app/accounts.ex:45 --forward                 # forward slice
```

**`mix reach.check`** — CI / release-safety gates.

```bash
mix reach.check --arch                       # validate against .reach.exs policy
mix reach.check --changed --base main        # changed-risk report (callers, public-API touches, suggested tests)
mix reach.check --dead-code                  # unused pure expressions
mix reach.check --smells                     # the full smell surface (see below)
mix reach.check --candidates                 # advisory refactoring candidates
```

**`mix reach.otp`** — OTP / process analysis.

```bash
mix reach.otp                                # GenServer + gen_statem state machines, supervision trees,
                                             # ETS/process-dict coupling, dead replies, missing handlers
mix reach.otp MyApp.Worker                   # scope to one module
mix reach.otp --concurrency                  # Task.async/await, monitors, spawn/link, supervisor topology
mix reach.otp --format json
```

**Terminal rendering (`--graph`, requires `{:boxart, "~> 0.3.3"}`):**

```bash
mix reach.inspect MyApp.Server.handle_call/3 --graph        # CFG with highlighted source
mix reach.inspect MyApp.Server.handle_call/3 --graph --call-graph
mix reach.map --coupling --graph                            # module dependency graph
mix reach.map --depth --graph                               # CFG of deepest function
mix reach.map --effects --graph                             # effect distribution
mix reach.otp --graph                                       # GenServer state diagrams
```

Without boxart, `--graph` exits cleanly with a message asking you to add it. 0.3.3 is required for Unicode-safe syntax highlighting.

### `.reach.exs` Architecture Policy

Drives `mix reach.check --arch`/`--changed`/`--candidates`/`--smells`. The file evaluates to a keyword list. Patterns are module-name strings with `*` wildcards.

```elixir
# .reach.exs
[
  layers: [
    web: "MyAppWeb.*",
    domain: "MyApp.*",
    data: ["MyApp.Repo", "MyApp.Schemas.*"]
  ],
  deps: [forbidden: [{:domain, :web}, {:data, :web}]],
  source: [
    forbidden_modules: ["MyApp.Legacy.*"],
    forbidden_files: ["lib/my_app/legacy/**"]
  ],
  calls: [
    forbidden: [
      {"MyApp.Domain.*", ["IO.puts", "Jason.encode!"]},
      {"MyApp.Workers.*", ["System.cmd"], except: ["MyApp.Workers.Cleanup"]}
    ]
  ],
  effects: [allowed: [{"MyApp.Pure.*", [:pure, :unknown]}]],
  boundaries: [
    public: ["MyApp.Accounts"],
    internal: ["MyApp.Accounts.Internal.*"],
    internal_callers: [
      {"MyApp.Accounts.Internal.*", ["MyApp.Accounts", "MyApp.Accounts.*"]}
    ]
  ],
  risk: [
    changed: [
      many_direct_callers: 5,
      wide_transitive_callers: 10,
      branch_heavy: 8,
      high_risk_reason_count: 3
    ]
  ],
  candidates: [
    thresholds: [mixed_effect_count: 2, branchy_function_branches: 8, high_risk_direct_callers: 4],
    limits: [per_kind: 20, representative_calls: 10, representative_calls_per_edge: 3]
  ],
  clone_analysis: [provider: :ex_dna, min_mass: 30, min_similarity: 1.0, max_clones: 50],
  smells: [
    fixed_shape_map: [min_keys: 3, min_occurrences: 3, evidence_limit: 10],
    behaviour_candidate: [min_modules: 3, min_callbacks: 3, module_display_limit: 8, callback_display_limit: 8]
  ],
  tests: [hints: [{"lib/my_app/accounts/**", ["test/my_app/accounts_test.exs"]}]]
]
```

Start from `examples/reach.exs` in the Reach repo. Reach itself ships a root `.reach.exs` and gates CI on `mix reach.check --arch`.

`--arch` validates layer references (typos in `deps[:forbidden]` against missing layer names raise instead of silently passing), supports allowlist-style dependency policy alongside the forbidden list, and reports layer cycles. Architecture checks use source-only loading; changed-code checks return immediately when the diff is empty.

### Smell Checks

`mix reach.check --smells` covers (non-exhaustive):

- **Loop antipatterns** — `Enum.at`/`List.delete_at` in loops (O(n²)); `++`/`<>` inside loops; manual `Enum.reduce` min/max/sum/frequency; append in recursion (`++ [item]` in recursive tail call) → prepend + `Enum.reverse/1`; repeated traversal (same variable traversed by 2+ different `Enum` fns) → one `Enum.reduce/3`; nested enum (`Enum.member?` inside another `Enum` of the same var) → precompute `MapSet`; 3+ `Enum.at` calls on same var with literal indices → pattern match
- **Pipeline waste** — `Enum.reverse |> Enum.reverse`, `filter |> count`, `map |> count`, `filter |> filter`, `sort |> take`/`reverse`/`at`, `drop |> take`, `take_while |> count`/`length`, `map |> Enum.join`, `List.foldr/3`, `Enum.min_by`/`max_by`/`dedup_by` w/ identity fn, `Enum.map |> Enum.flat_map`/`List.flatten`, `Enum.sort/2 |> Enum.reverse`, `Enum.with_index |> Enum.reduce`, redundant `Enum.map_join("")`; sort then negative take (`Enum.sort |> Enum.take(-n)`) → `Enum.sort(:desc) |> Enum.take(n)`; split then head (`String.split |> hd/List.first`) → `parts: 2`; filter then first (`Enum.filter |> List.first/hd`) → `Enum.find/2`
- **Collection idioms** — `Enum.reverse |> hd`, `Enum.reverse ++ tail`, `inspect |> String.starts_with?`, chained `String.replace`, `Map.keys |> Enum.map`, `List.to_tuple |> elem`, redundant `Enum.join("")`, negative `Enum.take`, `String.graphemes |> length`, `String.length == 1`, `Integer.to_string |> String.to_charlist`, anon-fn `.()` in pipes; `Map.keys`/`Map.values` patterns (`|> Enum.join`, `|> Enum.uniq`, `|> Enum.count`/`length` → `map_size/1`, `Map.keys |> Enum.member?` → `Map.has_key?/2`, `Map.values |> Enum.sum`/`max`/`min`/`join`); `Integer.to_string |> String.graphemes` → `Integer.digits`; `length(String.split) - 1` (Python count idiom); `Enum.at(list, -1)` → `List.last/1`; `Map.new`/`MapSet.new` patterns (`Enum.map |> Enum.into(%{})`, `Enum.into(_, %{})`, `Enum.into(_, MapSet.new())`, `Enum.map |> Enum.concat`); piped `Regex.replace` where the pipe injects the string as regex arg → `String.replace/3` (via ExAST `piped()` predicate)
- **Idiom mismatch** — `Enum.count/1` (no predicate) → `length/1`; `Map.values |> Enum.all?/any?/find/filter/map` → iterate `{k, v}`; `Enum.map → Enum.max/min/sum`; `List.foldl/3` → `Enum.reduce/3`; `String.graphemes |> Enum.reverse |> Enum.join` → `String.reverse/1`; guard equality where pattern match suffices; `Map.update` then `Map.get/fetch` on same var; `Map.put` w/ variable boolean key → `MapSet`
- **Boolean / conditional idiom** — case-on-boolean (`case expr do true -> ...; false -> ... end` when subject is comparison/boolean op) → `if/else`; case→`match?/2` (`case _ do pat -> true; _ -> false end`); needless bool (`if cond, do: true, else: false` and inverse); manual max/min (`if a > b, do: a, else: b`) → `Kernel.max/2`/`Kernel.min/2`; cond two-clause (`cond do ... true -> ... end` w/ exactly two) → `if/else`; `unless/else` → `if` positive case first; redundant assignment (`result = expr; result`); redundant nil default (`Keyword.get`/`Map.get(_, _, nil)`); `@doc false` on `defp`
- **Length comparisons** — `length(list) == 0`/`0 == length(list)`/`length(list) > 0` → pattern match or `== []`/`!= []`; small-literal `length/1` comparisons in guards
- **Identity callbacks** — `Enum.uniq_by(coll, fn x -> x end)` → `Enum.uniq/1`; `Enum.sort_by(coll, fn x -> x end)` → `Enum.sort/1`
- **Map contracts** — same-variable atom/string fallback (`metadata["id"] || metadata[:id]`); repeated atom-key map literals with same shape (struct/contract candidate); fixed-shape map detection
- **Structural drift (clone-backed)** — return-contract drift, side-effect ordering drift, validation drift across similar code
- **Error handling** — bare rescue clauses (`rescue _ ->` / `rescue error ->`) requiring exception-set narrowing; false-success error handling (functions silently converting `{:error, _}` into success-shaped returns)
- **Concurrency** — ETS partial-key match (wildcard matches over tuple keys); ExUnit `async: true` modules that mutate global state
- **Stdlib bypass** — hand-written basename / extension / URL splitting / order-safe patterns where a stdlib call covers the case
- **Other** — redundant negated guards (`when x != y` after `when x == y`); destructure-then-reconstruct (`[a, b, c]` rebuilt as same list); behaviour-candidate detection (modules exposing the same public callback set; macro-aware — Phoenix `use ..., :live_view` and similar callback surfaces don't false-positive); compile-time vs runtime config (`Application.get_env`/`fetch_env` in module attrs, `compile_env` inside runtime fns); trivial delegate (pass-through `defdelegate` / hand-written forwarding, excluding documented facades + behaviour adapters); identity float arithmetic (`x * 1.0`, `x + 0.0`)

**False-positive scope.** `++`-in-reduce checks verify an operand references the reduce accumulator before flagging. IR-based checks (repeated traversal, multiple `Enum.at`) scope per-clause to avoid multi-clause-function FPs. `Code.string_to_quoted` calls pass `emit_warnings: false` so reparsing dep source emits no tokenizer noise. Corpus-tested against the top 200 Hex packages: 0 crashes, 0 false positives.

**Credo overlap.** The Reach README documents which smells overlap Credo and which don't — useful when deciding whether to run both or gate CI on `mix reach.check --smells` alone. Reach's own CI runs `mix reach.check --arch --smells`.

Custom pattern checks via the ExAST-backed DSL: `use Reach.Smell.PatternCheck`, `smell ~p[<source pattern>]`. Guarded patterns: `from(~p[...]) |> where(...)`. Pipes, operators, function calls, and module attributes all work with the `~p` sigil; pattern checks share a zipper cache across modules. The `piped()` selector predicate distinguishes form — `where(piped())` matches only `|>` calls, `where(not piped())` matches only direct calls. Useful when a pattern means different things in pipe vs direct form (e.g. `Regex.replace` where the piped subject is the regex argument vs the source string).

### Suppressing Smells

Two layers, used together:

- **Config-level** — `.reach.exs` `smells: [ignore: [paths: ["lib/legacy/**"], modules: ["MyApp.Legacy.*"]]]` skips checks across whole paths or module patterns.
- **Inline** — Credo-style comments at the call site:
  - `# reach:disable-next-line <check>` — suppress the named check on the following line
  - `# reach:disable-for-next-line <check>` — alternate phrasing accepted
  - File-, previous-line-, and range-scoped variants also recognized

Inline suppressions carry source text alongside the AST so they survive Credo's cached-AST integration. Non-Elixir source files from plugin frontends (e.g. JS via `Reach.Frontend.JavaScript`) are skipped during smell analysis rather than parsed as Elixir.

### Framework Smell Plugins

`mix reach.check --smells` runs framework-specific checks contributed by plugins. Auto-activate when the host package is in the dep tree (same `Code.ensure_loaded?/1` gate as the other plugin built-ins):

- **Phoenix** — LiveView lifecycle mistakes (e.g. `assign_new` misuse, raw HTML interpolation), socket-assigns shape drift, direct `Repo.*` calls in `mount/3` without connection guards.
- **Phoenix LiveView (HEEx lowering)** — recognizes `~H` templates and `.heex` files, lowering control flow into Reach IR. Adds semantic edges connecting `JS.push`/`push_event` calls to their handlers, assign writes to subsequent assign reads, and stream writes to stream consumers.
- **Ecto** — query pitfalls (cross-join surfaces, missing pinning), unsafe SQL interpolation in `fragment/1`, money-like `:float` field declarations.
- **Oban** — `args` shape pitfalls (mixed atom/string keys, non-JSON-encodable values).
- **Jason** — hand-rolled JSON sanitizers detected against the Jason protocol surface (use `defimpl Jason.Encoder` instead).
- **Security / source** — unsafe dynamic atom creation (`String.to_atom/1` on untrusted input), unsafe `:erlang.binary_to_term/1`, missing `@external_resource` declarations on macros that read files, conservative Ecto cross-join detection.

Real-world false positives in these checks have been narrowed against open-source Elixir corpora — Phoenix raw HTML, LiveView `assign_new`, and Oban `args` checks are intentionally conservative.

**Source smell DSL.** Define custom checks with `use Reach.Smell.Check.Source` and the `smell/4` macro. AST callback rules with `mode: :ast` cover hot source-shape checks that need custom matching beyond the `~p` sigil. ExAST selectors compile to source prefilters automatically, so hot pattern scans skip unrelated files cheaply; prefilters route through `Reach.Smell.PatternConfig` / `Reach.Smell.SourceRunner`.

**Custom plugin smells.** Plugins register checks via the `Reach.Plugin.smell_checks/0` callback (part of the `Reach.Plugin` behaviour). Projects can also load custom smell modules from `.reach.exs`. Plugin smells run only when their host plugin is active — never auto-discovered as generic built-ins.

### Smell Corpus & Profiling Tooling

For tuning new smell checks against real codebases:

```bash
mix run scripts/smell_corpus_scan.exs      # repeatable scans across external repos
                                           # (plugin and kind filters supported)
mix run scripts/profile_smells.exs         # per-check, per-pattern, per-query profiling
                                           # against the current project or an external repo
```

Both live in the Reach repo (not shipped as `mix` tasks) — clone Reach to use them.

### Advisory Refactoring Candidates

`mix reach.check --candidates` and `mix reach.inspect TARGET --candidates` surface graph-backed suggestions:

- **`introduce_boundary`** — split a function with mixed effects into pure core + effectful shell
- **`isolate_effects`** — group side-effecting calls
- **`extract_pure_region`** — move a pure subexpression out of an effectful function
- **`break_cycle`** — suggest where to cut a module dependency cycle, with `representative_calls` evidence
- **`map_contract`** — maps created with a fixed shape and returned from local functions (struct or contract candidate); evidence carried by `Reach.Evidence.MapContract` and refined by plugin `evidence_refinement` hooks

Each candidate carries `confidence`, `actionability`, `proof`, and (for cycles) `representative_calls` — agents should treat them as suggestions, not automatic edits.

### HTML Visualization

```bash
mix reach lib/my_app/accounts.ex lib/my_app/auth.ex
# → reach_report/index.html (self-contained, offline)
```

Three tabs: Control Flow (CFG), Call Graph (cross-module), Data Flow (def→use chains). Graph data embedded as `window.graphData = {call_graph, control_flow, data_flow}`. `data_flow.taint_paths` slot exists but the CLI doesn't expose source/sink flags — use `mix reach.trace` for taint. Optional deps: `:jason`, `:makeup`, `:makeup_elixir`.

### Recipes

**Call sites of a remote function:**
```elixir
Reach.nodes(graph, type: :call, module: :gun, function: :ws_send)
|> Enum.map(&{&1.source_span.start_line, &1.meta.arity})
```

**What data flows into this call?**
```elixir
[target] = Reach.nodes(graph, type: :call, module: Repo, function: :insert)
Reach.backward_slice(graph, target.id) |> Enum.map(&Reach.node(graph, &1))
```

**Is the inbound-frame → handler path sanitized?**
```elixir
Reach.taint_analysis(graph,
  sources: [type: :call, module: MyApp.MessageHandler, function: :decode],
  sinks: &(&1.type == :call and &1.meta[:kind] == :dynamic),
  sanitizers: [[type: :call, module: Jason, function: :decode]]
) |> Enum.filter(&(not &1.sanitized))
# Use module_to_graph/2 if the handler is generated by `use GenServer`.
```

**Reorder two side-effecting calls?**
```elixir
Reach.independent?(graph, call_a.id, call_b.id)
```

### Tidewave Exploration

Graphs don't persist between `project_eval` calls — rebuild each query:
```elixir
graph = Reach.file_to_graph!("lib/my_module.ex")
Reach.nodes(graph, type: :function_def) |> length()
```

For many related queries in one IEx session, build once and persist via process dictionary or an Agent.

### Plugins

`Reach.Plugin` adds domain-specific edges (framework dispatch, message routing, pipeline topology) not visible to language-level analysis.

Built-ins auto-detect via `Code.ensure_loaded?/1`: `Reach.Plugins.Phoenix`, `Ecto`, `Oban`, `GenStage`, `Jido`, `OpenTelemetry`, `QuickBEAM`. They run when the host package is in the dep tree.

```elixir
Reach.string_to_graph!(source, plugins: [Reach.Plugins.Phoenix])
Reach.Project.from_mix_project(plugins: [Reach.Plugins.Ecto])
Reach.string_to_graph!(source, plugins: [])            # disable all
```

Custom skeleton:
```elixir
defmodule MyPlugin do
  @behaviour Reach.Plugin
  @impl true
  def analyze(all_nodes, _opts), do: []                 # [{from_id, to_id, label}, ...]
  @impl true
  def analyze_project(_modules_map, _all_nodes, _opts), do: []   # optional, cross-module

  # For plugins that splice additional nodes (e.g. embedded JS) into the host graph.
  # Return {new_nodes, new_edges} — nodes get merged into the IR before analysis queries.
  @impl true
  def analyze_embedded(_all_nodes, _opts), do: {[], []}

  # Teach the effect classifier about framework calls.
  @impl true
  def classify_effect(_node), do: nil                    # :pure | :read | :write | :io | :send | nil

  # Register framework-specific smell checks. Each module must use
  # Reach.Smell.Check.Source (or .AST) and is wired into `mix reach.check --smells`.
  @impl true
  def smell_checks, do: []
end
```

### Reach.Plugins.QuickBEAM — Cross-Language Analysis

Stitches Elixir and JavaScript into one graph. Scans for `QuickBEAM.eval/2,3` and `QuickBEAM.call/3,4` callsites where the JS source is a **string literal**, parses it via `Reach.Frontend.JavaScript`, and adds cross-language edges. Auto-enabled when QuickBEAM is in the dep tree.

| Edge label | From | To | Meaning |
|---|---|---|---|
| `:js_eval` | Elixir runtime-run callsite | JS function_def in the literal source | Defines a JS fn in the runtime |
| `{:js_call, name}` | Elixir `QuickBEAM.call(rt, name, ...)` | JS function_def with matching name | Invokes a previously-defined JS fn |
| `:beam_call` | JS `Beam.call("handler", ...)` site | Elixir fn registered in `QuickBEAM.start(handlers: %{...})` | JS calling back into Elixir |

Also classifies effects on `QuickBEAM.*`: the JS-runtime entrypoints (`eval`, `call`, `load_module`, `load_bytecode`, `send_message`, `start`, `stop`, `reset`) → `:io`; `set_global` → `:write`; `compile`/`disasm`/`globals`/`get_global`/`info`/`memory_usage`/`coverage` → `:read`. OXC AST ops (`parse`, `postwalk`, `patch_string`, `imports`, `format`, `rewrite_specifiers`) → `:pure`; other OXC → `:io`.

```elixir
# Auto-enabled if QuickBEAM is in deps
graph = Reach.file_to_graph!("lib/my_runner.ex")
Reach.nodes(graph) |> Enum.filter(&(&1.meta[:language] == :javascript))
```

Limitation: cross-language edges only form when the JS source is a **literal** at the callsite. Runtime-computed JS (e.g. sourced from a variable or `File.read!/1`) won't be stitched, since the plugin works by peeking at the literal AST node.

### Other Public API

- `Reach.compiled_to_graph/2` — graph from `:beam_lib` chunks (alt to `module_to_graph/2`)
- `Reach.call_graph/1`, `function_graph/2` — derive subgraphs
- `Reach.control_deps/2`, `data_deps/2`, `neighbors/3` — direct dep queries
- `Reach.has_dependents?/2` — quick existence check
- `Reach.string_to_graph!/2` — bang variant
- `Reach.to_dot/1`, `to_graph/1` — export to GraphViz / `:digraph`
- `Reach.Project.from_sources/2` — build from `{path, source}` pairs (fixtures, piped code)
- `Reach.Project.summarize_dependency/1` — text summary of an edge

### Dependencies

```elixir
{:reach, "~> 2.7", only: [:dev, :test], runtime: false},
{:boxart, "~> 0.3.3", only: [:dev, :test], runtime: false}   # terminal --graph rendering
```

Requires `ex_ast ~> 0.12.0` at the dep level. Pulls in `libgraph`. Optional companion deps: `jason`, `makeup`, `makeup_elixir`, `makeup_js` (HTML viz), `boxart` (terminal). For the JS frontend + cross-language plugin, add `{:quickbeam, "~> 0.10.15"}` — the plugin activates automatically when QuickBEAM is in the dep tree.
