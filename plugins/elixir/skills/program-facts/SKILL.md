---
name: program-facts
description: program_facts — oracle-fact program generation for testing Elixir analyzers. Use when generating ground-truth fixture programs to test static analyzers, writing property/differential/metamorphic tests for analysis tools, or building StreamData generators and Graph adapters. Covers policies, ExUnit helpers (assert_compiles, assert_manifest_round_trip, with_tmp_project), generators, and shrink/differential testing.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/program-facts.md — do not edit manually -->

## ProgramFacts — Ground-Truth Fixtures for Static-Analysis Testing

Generates valid Elixir projects paired with oracle facts (call edges, data flows, effects, branches, locations, architecture policies) so analyzers can be verified against known-correct expected output rather than arbitrary random source.

**Min version: `{:program_facts, "~> 0.2", only: [:dev, :test]}`.**
**Optional: `{:stream_data, "~> 1.1"}` for `ProgramFacts.StreamData` generators; `{:libgraph, "~> 0.16"}` for `ProgramFacts.Graph` helpers.**
**Seeds are bounded to `0..10_000`** — generated module names are atoms; stay in range.
**Requires Elixir ~> 1.19.** CI gates on Credo, ExDNA, Dialyzer, and ExSlop.

**Caveat:** `ProgramFacts.Graph` silently becomes unavailable if `libgraph` is not in deps; `ProgramFacts.StreamData` requires `stream_data`. Both are optional — check `Code.ensure_loaded?/1` if using from a library.

**Does NOT cover:** running the generated programs, property-based shrinking beyond the built-in `shrink/2,3`, or generating Erlang/BEAM source (roadmap item).

**Portfolio fit:** directly used when testing reach plugins and the exograph indexer — generate a `:layered_valid` or `:forbidden_dependency` program, write it via `Project.write_tmp!`, run the analyzer, and assert against `program.facts.architecture`.

---

### Core Concepts

```text
policy + seed → semantic model → source files + oracle facts (manifest)
```

- **`ProgramFacts.Program`** — the mutable working object: `id`, `seed`, `files`, `facts`, `metadata`.
- **`ProgramFacts.Facts`** — struct of expected facts used for assertions; fields are tuple/map-compatible.
- **`ProgramFacts.Manifest`** — typed JSON export boundary (`schema_version`, `program_facts_version`, files, facts as `ProgramFacts.Fact.*` structs).

Facts are generated *with* the source code, not inferred afterward by the tool under test.

---

### Generation (`ProgramFacts.generate!/1`)

```elixir
# Basic generation — returns %ProgramFacts.Program{}
program = ProgramFacts.generate!(policy: :linear_call_chain, seed: 123, depth: 4)

program.id          #=> "pf_123_linear_call_chain"
program.files       #=> [%ProgramFacts.File{path: "lib/generated/...", ...}, ...]
program.facts.modules
program.facts.functions       # [{module, name, arity}, ...]
program.facts.call_edges      # [{{m, f, a}, {m, f, a}}, ...]
program.facts.call_paths
program.facts.data_flows
program.facts.effects
program.facts.branches
program.facts.architecture
program.facts.locations       # source-location oracle per function/call
program.facts.features        # set of enabled feature atoms

# List available policies and layouts at runtime
ProgramFacts.policies()
ProgramFacts.layouts()   #=> [:plain, :umbrella, :package_style]

# Umbrella or package-style layout (tests source-discovery: lib/**/*.ex, apps/*/lib/**/*.ex, */lib/**/*.ex)
program = ProgramFacts.generate!(policy: :linear_call_chain, layout: :umbrella, seed: 7)
```

**Key options for `generate!/1`:**

| Option | Default | Notes |
|--------|---------|-------|
| `:policy` | `:linear_call_chain` | See policy table below |
| `:seed` | `1` | `0..10_000`; deterministic output |
| `:depth` | `3` | Call-chain depth for chain/graph policies |
| `:layout` | `:plain` | `:plain \| :umbrella \| :package_style` |

---

### Policies

**Call graph:**

| Policy | Shape |
|--------|-------|
| `:single_call` | One function calling one other |
| `:linear_call_chain` | A → B → C → … depth calls |
| `:branching_call_graph` | Fan-out call tree |
| `:module_dependency_chain` | Module-level chain |
| `:module_cycle` | Cycle between modules |

**Data flow:**

`:straight_line_data_flow`, `:assignment_chain`, `:branch_data_flow`, `:helper_call_data_flow`, `:pipeline_data_flow`, `:return_data_flow`

**Branches / control flow:**

`:if_else`, `:case_clauses`, `:cond_branches`, `:with_chain`, `:anonymous_fn_branch`, `:multi_clause_function`, `:nested_branches`

**Effects:**

`:pure`, `:io_effect`, `:send_effect`, `:raise_effect`, `:read_effect`, `:write_effect`, `:mixed_effect_boundary`

**OTP / syntax fixtures:**

`:gen_server_callbacks`, `:guard_clause`, `:try_rescue_after`, `:receive_message`, `:comprehension`, `:struct_update`, `:default_arguments`

**Architecture fixtures** (for reach `.reach.exs` / `mix reach.check --arch` testing):

`:layered_valid`, `:forbidden_dependency`, `:layer_cycle`, `:public_api_boundary_violation`, `:internal_boundary_violation`, `:allowed_effect_violation`

---

### Writing a Temporary Mix Project (`ProgramFacts.Project`)

```elixir
# write_tmp! generates + writes; returns {:ok, dir, program}
{:ok, dir, program} =
  ProgramFacts.Project.write_tmp!(
    policy: :forbidden_dependency,
    seed: 42
  )

# Generated tree includes intentional exclusion fixtures
# mix.exs, program_facts.json, lib/generated/..., deps/ignored/..., _build/dev/...

File.ls!(dir)  #=> ["_build", "deps", "lib", "mix.exs", "program_facts.json"]

# write!/3 — explicit destination; refuses to overwrite unless force: true
ProgramFacts.Project.write!(dir, program, force: true)
```

---

### ExUnit Helpers (`ProgramFacts.ExUnit`)

```elixir
# assert_compiles/1 — compiles generated source, verifies expected modules are produced
ProgramFacts.ExUnit.assert_compiles(program)

# assert_manifest_round_trip/1 — encodes and decodes the manifest, validates shape
ProgramFacts.ExUnit.assert_manifest_round_trip(program)

# with_tmp_project/2 — writes a tmp Mix project, yields {dir, program}, then removes it
ProgramFacts.ExUnit.with_tmp_project(program, fn dir, program ->
  assert File.exists?(Path.join(dir, "mix.exs"))
  # run analyzer against dir here
end)
```

---

### Recipes

**Basic analyzer round-trip (ExUnit):**

```elixir
test "analyzer finds generated call edges" do
  {:ok, dir, program} =
    ProgramFacts.Project.write_tmp!(policy: :linear_call_chain, seed: 100, depth: 3)

  project = MyAnalyzer.load_project!(dir)

  expected_edges = MapSet.new(program.facts.call_edges)
  actual_edges   = MapSet.new(MyAnalyzer.call_edges(project))

  assert MapSet.subset?(expected_edges, actual_edges)
end
```

**Reach architecture-policy fixture:**

```elixir
test "reach detects forbidden dependency" do
  ProgramFacts.ExUnit.with_tmp_project(
    ProgramFacts.generate!(policy: :forbidden_dependency, seed: 7),
    fn dir, program ->
      result = Reach.Project.from_glob(Path.join(dir, "lib/**/*.ex"))
      violations = Reach.check_arch(result)
      assert length(violations) > 0
      # program.facts.architecture carries the expected violation details
    end
  )
end
```

**Property test with StreamData (`stream_data` required):**

```elixir
use ExUnitProperties

property "analyzer finds all generated call edges" do
  check all program <- ProgramFacts.StreamData.program(
    policies: [:single_call, :linear_call_chain],
    seed_range: 0..100
  ) do
    ProgramFacts.ExUnit.with_tmp_project(program, fn dir, program ->
      expected = MapSet.new(program.facts.call_edges)
      actual   = MapSet.new(MyAnalyzer.call_edges(dir))
      assert MapSet.subset?(expected, actual)
    end)
  end
end
```

**Reproduce a specific seed failure:**

```elixir
program = ProgramFacts.generate!(policy: :linear_call_chain, seed: 347, depth: 4)
# Seed is deterministic — same output every run
```

---

### Shrinking

```elixir
program = ProgramFacts.generate!(policy: :linear_call_chain, seed: 80, depth: 5)

result =
  ProgramFacts.shrink(program, fn candidate ->
    MyAnalyzer.fails?(candidate)
  end)

result.program   # minimal reproducer
result.options   # smallest gen options that still fail
result.steps     # trace of accepted/rejected shrink steps

# Skip regeneration-based shrinking, focus on transforms/structure:
ProgramFacts.shrink(program, &MyAnalyzer.fails?/1, option_shrink: false)
```

Reduces layout, width, depth, transform sequences, then removes unrelated modules/files. Deterministic.

---

### Transforms (Metamorphic Testing)

```elixir
variant =
  program
  |> ProgramFacts.Transform.apply!([
    :rename_variables,
    :add_dead_pure_statement,
    :wrap_in_if_true
  ])

ProgramFacts.compare_transform(program, variant)          # returns comparison
ProgramFacts.assert_transform_preserved!(program, variant) # raises on invariant violation

ProgramFacts.transforms()  # list all available transforms
```

Available transforms include: `:rename_variables`, `:add_dead_pure_statement`, `:add_dead_branch`, `:extract_helper`, `:inline_helper`, `:wrap_in_if_true`, `:wrap_in_case_identity`, `:reorder_independent_assignments`, `:split_module_files`, `:add_unrelated_module`, `:add_alias_and_rewrite_remote_call`. Uses `Code.string_to_quoted!/2` + `Macro` — no regex rewriting.

---

### Graph Adapters (`ProgramFacts.Graph`, requires `libgraph ~> 0.16`)

```elixir
call_graph   = ProgramFacts.Graph.call_graph(program)    # Graph.t() of functions
module_graph = ProgramFacts.Graph.module_graph(program)  # module-collapsed graph

ProgramFacts.Graph.reachable?(program, source, target)   # true/false
ProgramFacts.Graph.path?(program, path)                  # every consecutive pair is an edge
ProgramFacts.Graph.cycles(program)                       # strongly connected components
ProgramFacts.Graph.metrics(program)                      # scoring/shrink metrics
ProgramFacts.Graph.subgraph(program, vertices)           # induced subgraph
ProgramFacts.Graph.validate!(program)                    # raises if graph facts inconsistent
ProgramFacts.Graph.architecture_graph(program)           # architecture-fixture graph
ProgramFacts.Graph.call_edges(program)                   # raw call edges as list
```

Useful when integrating with Reach — both use `libgraph`, so graphs can be compared directly.

---

### Differential Testing

```elixir
ProgramFacts.differential(program, [
  {:source_frontend, &SourceAnalyzer.facts/1},
  {:beam_frontend,   &BeamAnalyzer.facts/1},
  MyAnalyzerAdapter   # implements ProgramFacts.Analyzer behaviour
])
# result.agreed? / result.disagreements
```

Adapter modules implement `ProgramFacts.Analyzer` and may return maps, facts structs, programs, or `ProgramFacts.Analyzer.Result`.

---

### Corpus & Replay

```elixir
program = ProgramFacts.generate!(policy: :case_clauses, seed: 43)
dir     = ProgramFacts.Corpus.save!(program, "corpus/analyzer")

# Reload later
%ProgramFacts.Manifest{} = ProgramFacts.Corpus.load_manifest!(dir)

ProgramFacts.Corpus.manifests("corpus/analyzer")
ProgramFacts.Corpus.load_manifests!("corpus/analyzer")
```

Each entry contains source files + `program_facts.json`. Use for regression suites and CI replay.

---

### Feedback-Directed Search

```elixir
result =
  ProgramFacts.Search.run(
    iterations: 50,
    seed: 100,
    scoring: [:features, :graph_complexity, :cycles, :long_paths]
    # or: interesting?: fn candidate, state -> candidate.score > state.best_score end
  )

result.programs    # collected programs
result.candidates
result.coverage
result.features
```

Built-in scoring: `:features`, `:new_features`, `:graph_complexity`, `:cycles`, `:long_paths`.

---

### Custom Semantic Model

```elixir
source = {MyApp.A, :entry, 1}
target = {MyApp.B, :sink, 1}

model =
  ProgramFacts.Model.builder(id: "custom", seed: 1, policy: :custom)
  |> ProgramFacts.Model.Builder.add_call(source, target)
  |> ProgramFacts.Model.Builder.add_call_path([source, target])
  |> ProgramFacts.Model.Builder.add_feature(:remote_call)
  |> ProgramFacts.Model.Builder.build()

program = ProgramFacts.Model.to_program(model)

# Project back to model
model = ProgramFacts.model(program)
model.modules
model.relationships.call_edges
model.features
```

---

### JSON Export

```elixir
ProgramFacts.to_map(program)    # atom-keyed Elixir map
ProgramFacts.to_json!(program)  # JSON string; includes schema_version, program_facts_version
```

Manifest facts are typed via `ProgramFacts.Fact.*` structs (CallEdge, DataFlow, Effect, Branch, Location).

---

### DO NOT

1. Generate module names outside the `0..10_000` seed range — atom table exhaustion.
2. Use `ProgramFacts.Graph.*` without `{:libgraph, "~> 0.16"}` in deps — silent unavailability.
3. Use `ProgramFacts.StreamData.*` without `{:stream_data, "~> 1.1"}` in deps.
4. Pass `:policy` atoms not in `ProgramFacts.policies/0` — no error, but undefined behavior.
5. Call `Project.write!/3` on a non-empty directory without `force: true` — it refuses.
6. Infer facts from the generated source with your analyzer and then compare to oracle facts — that defeats the oracle model; always compare *analyzer output* against `program.facts.*`.
7. Parse or rewrite generated source with regex — transforms use `Code.string_to_quoted!/2`.

---

### Common Issues

| Problem | Cause | Fix |
|---------|-------|-----|
| `ProgramFacts.Graph` functions undefined | `libgraph` not in deps | Add `{:libgraph, "~> 0.16", optional: true}` |
| `ProgramFacts.StreamData` undefined | `stream_data` not in deps | Add `{:stream_data, "~> 1.1", optional: true}` |
| Atom exhaustion / BEAM crash | Seeds outside `0..10_000` | Clamp seed before passing to `generate!` |
| `write!/3` raises on existing dir | Non-empty target | Pass `force: true` or clean directory first |
| Facts don't include architecture fields | Wrong policy | Use an `:architecture_*` policy (e.g. `:forbidden_dependency`) |
| Different runs produce different output | Seed not fixed | Always pass an explicit `:seed` for reproducibility |

---

### Dependencies

```elixir
# mix.exs — test/dev only; no runtime dep
{:program_facts, "~> 0.2", only: [:dev, :test]}

# Optional: StreamData property generators
{:stream_data, "~> 1.1", only: [:dev, :test]}

# Optional: libgraph adapters (ProgramFacts.Graph.*)
{:libgraph, "~> 0.16", only: [:dev, :test]}
```

Source: [github.com/elixir-vibe/program_facts](https://github.com/elixir-vibe/program_facts) | [hexdocs.pm/program_facts](https://hexdocs.pm/program_facts) — v0.2.1.
