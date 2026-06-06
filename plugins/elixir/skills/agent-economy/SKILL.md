---
name: agent-economy
description: Designing apps and libraries for AI agent consumers using Descripex (`api()` macro, `__api__/0` introspection, progressive disclosure with `describe/0..3`), JSON Schema generation, MCP tool surfacing, and EIP-8004 trustless verification. Use when building APIs that AI agents will call, annotating existing modules with `api()` and `describe(:internal)`, generating MCP tool lists with `Descripex.MCP.tools/1`, building manifests via `Descripex.Manifest.build/1`, exposing libraries through `Descripex.Discoverable`, or designing for trustless re-execution. Distinguishes `:value` vs `:exchange_data` param kinds and explains coexistence with hand-written `@doc`.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/agent-economy.md — do not edit manually -->

## Agent Economy Design

Every app and library should treat AI agents as first-class consumers. Design for discovery, calling, and verification now.

### Tier 2: Self-Describing with Descripex (default)

`descripex`'s `api()` macro generates `@doc`, `@doc hints:`, compile-time validation, and runtime introspection from a single declaration:

```elixir
use Descripex, namespace: "/funding"

api(:annualize, "Annualize a per-period funding rate.",
  params: [
    rate: [kind: :value, description: "Per-period funding rate as decimal", schema: float()],
    period_hours: [kind: :value, default: 8, description: "Hours per funding period", schema: pos_integer()]
  ],
  returns: %{type: :float, description: "Annualized percentage rate", schema: float()}
)

@spec annualize(number(), pos_integer()) :: float()
def annualize(rate, period_hours \\ 8), do: ...
```

**What `api()` generates at compile time:**
- `@doc` (BEAM slot 4) + `@doc hints:` (slot 5) — human-readable + machine-readable
- `@moduledoc namespace:` — URL grouping
- `__api__/0`, `__api__/1` — runtime introspection
- `schema:` — Elixir type syntax compiled to JSON Schema via json_spec
- Param names validated against function args

**Manual `@doc` coexistence:** Place `api()` *before* an existing `@doc`. Hand-written `@doc` overwrites only slot 4 (prose); slot 5 (hints) survives. Standard for annotating existing codebases. For multi-clause functions, place `api()` before the first clause only.

**Param kinds (the key distinction agents need):**
- `:value` — caller provides (number, date, config)
- `:exchange_data` — must be fetched first; include `source: "fetch_trades(symbol)"`

**Two modes: using and understanding.** Agents call the public API (using) *and* debug why something happened (understanding). Both need rich metadata. Annotate internal infrastructure too — a reconnection failure needs `describe(:reconnection)` to expose `calculate_backoff/2` and `should_reconnect?/1`. Public/internal is a documentation grouping concern, not a discoverability depth concern.

### Manifest & Progressive Disclosure

Flow: `api()` → compile-time `@doc` + `hints` → `Code.fetch_docs/1` → `Manifest.build(modules)` → consumed by HTTP endpoint / static JSON / MCP tools / A2A cards.

**App wrapper:**
```elixir
defmodule MyApp.Manifest do
  @modules [MyApp.Funding, MyApp.Risk, MyApp.Options]
  def build, do: Descripex.Manifest.build(@modules)
end
```

**Progressive disclosure:**
```elixir
defmodule MyApp do
  use Descripex.Discoverable, modules: [MyApp.Funding, MyApp.Risk]
end

MyApp.describe()                     # L1: modules, namespaces, function counts
MyApp.describe(:funding)             # L2: function list (name, arity, spec, description)
MyApp.describe(:funding, :annualize) # L3: full detail — params, returns, errors
```

Short names: last module segment lowercased (`MyApp.Funding` → `:funding`). Non-Descripex modules get basic listings. Or use `Descripex.Describe.describe/1-3` directly.

**MCP tool generation:**
```elixir
Descripex.MCP.tools([MyApp.Funding, MyApp.Risk])
# => [%{name: "funding__annualize", description: "...", inputSchema: %{...}}]
```
`name_style: :full` for fully-qualified names. Serve the list from your MCP endpoint.

**Validation test:** walk all public modules, assert every exported function has `:hints`. Without enforcement, hints rot.

### Consuming Descripex-Powered Libraries

Use structured discovery instead of reading source. Contracts are compile-time validated — if it compiles, they're accurate.

- **Detect:** `function_exported?(SomeModule, :__api__, 0)` or `function_exported?(MyLib, :describe, 0)`
- **Discover:** `MyLib.describe()` / `.describe(:funding)` / `.describe(:funding, :annualize)` — Level 3 has everything needed to call correctly (param order, kinds, defaults, return shape, errors, composition hints)
- **Direct module access:** `Module.__api__()` / `.__api__(:func)` — `hints` has the same fields as Level 3
- **Batch:** `Descripex.Manifest.build(modules)` — JSON-serializable map of the whole API

See the library's `SKILLS.md` for exact output shapes.

### Tier 3: Trustless Verification (EIP-8004 ecosystem)

[ERC-8004](https://eips.ethereum.org/EIPS/eip-8004) defines three registries — Identity, Reputation, Validation. The manifest bridges code to all three: validators read it to understand contracts, re-execute with the same inputs, and compare results.

**Static export:** `mix descripex.manifest [--app my_app] [--pretty] [--output PATH]` generates `api_manifest.json`. Ship as static artifact, reference from EIP-8004 registration.

**Design for verifiability:** pure functions re-execute trivially; stateful ops need input/output logging for replay; side effects need receipts/attestations. The more pure your core, the easier trustless verification.

### What Belongs Where

| Concern | Where |
|---------|-------|
| Param hints, response shapes, errors | `@doc` metadata in library |
| Namespace, module grouping | `@moduledoc` metadata |
| Composition hints | `@doc` metadata |
| Tier/pricing, rate limits, authentication | API layer (not library) |
| EIP-8004 registration | Agent wrapper project (Ethereum coupling stays separate) |
