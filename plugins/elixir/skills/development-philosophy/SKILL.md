---
name: development-philosophy
description: Elixir documentation and internal-API conventions. Use when writing @doc/@moduledoc/@spec, hiding internal functions (defp vs @doc false vs @moduledoc false vs leading underscore; @opaque/@typep for types), choosing doctests vs ExUnit assertions, tagging deferred work with TODO:, tightening a validator at an API boundary, or before objecting that a macro/abstraction is complex or some cost is real friction — cite ecosystem precedents and check hex.pm for a library first.
allowed-tools: Read, Grep, Glob, Bash
---

<!-- Auto-synced from ~/.claude/includes/development-philosophy.md — do not edit manually -->

## Elixir Documentation Standards

**No IO in `@doc` examples.** `@doc` demonstrates API usage, not console output.

```elixir
# ❌ IO.puts("User: #{user[:name]}")  /  IO.inspect(user)
# ✅ {:ok, user} = MyApp.get_user("id")
# ✅ users = MyApp.list_users()
```

## Marking Internal API Surface

Elixir has no true visibility modifier on `def`. These markers communicate "not public API" to docs tooling, callers, and Dialyzer — none make a function actually private (only `defp` does that).

### Functions

| Marker | Hides from HexDocs? | Importable via `import`? | When to use |
|---|---|---|---|
| `defp` | ✅ | N/A (not callable) | True privacy. Default for any helper that doesn't need cross-module visibility. |
| `@doc false` on `def` | ✅ (function only) | ✅ | `def` that *must* be public (macro target, behaviour callback shim, called by sibling internal module) but isn't part of the consumer contract. |
| `@moduledoc false` on whole module | ✅ (entire module) | ✅ | Every function in the module is internal. Group internal helpers in `MyLib.Internal` / `MyLib.Impl` and mark the module — cleaner than scattering `@doc false`. **Elixir-core-recommended pattern.** |
| Leading `_` in name (`_foo`) | ✅ (with `@doc false`) | ❌ — compiler skips on `import` | Strongest "do not depend on this" signal. Compiler-enforced no-import. Rare in practice; reach for it when the function shape looks public-ish and you want a name-level deterrent. |
| `__foo__/N` (double underscore) | — | — | **Reserved for compile-time metadata / introspection** (`__info__/1`, `__struct__/0`, `__changeset__/0`, `__schema__/1`). Don't use for ordinary internal helpers — confuses readers who associate it with macro-generated metadata. |

**Decision tree:**
1. Can it be `defp`? → `defp`. Stop.
2. Must it be `def` (cross-module, macro target, behaviour shim)? → `@doc false`.
3. Is the *whole module* internal? → put it in `MyLib.Internal` (or similar) with `@moduledoc false`. Skip per-function `@doc false` inside.
4. Want compiler-enforced no-import? → leading single underscore. Reserve `__foo__/N` for metadata.

### Types

| Marker | Visible in docs? | Usable in other modules' specs? | Internal structure visible? |
|---|---|---|---|
| `@type` | ✅ | ✅ | ✅ |
| `@opaque` | ✅ | ✅ | ❌ — pattern-matching on internals is a contract violation |
| `@typep` | ❌ | ❌ — module-local only | ✅ (within the module) |

**Decision:**
- Public type, structure is part of the contract → `@type`.
- Public type, structure is implementation detail (callers shouldn't pattern-match) → `@opaque`. Use this for tokens, handles, IDs, anything where you want freedom to change the internal representation.
- Type only used inside this module → `@typep`. Keeps the public type surface clean.

### Specs

**Mandate: every function gets a `@spec` — `def` and `defp` alike.** No exceptions for "trivial" helpers; the spec is one line and pins the contract Dialyzer can't always infer (e.g. `integer() | float()` vs the narrower `integer()` you actually meant).

- **Why mandate, not "publics-only" (the community default):** community default optimizes for team-onboarding cost — irrelevant here. Solo-dev library portfolio with Credo strict + Dialyzer in CI on every repo. Cost is one line per function; payoff is Dialyzer pointing at the spec mismatch (fast) instead of a downstream call site three layers away (slow). Domain is signing / wallet / wire-format code where binary-length, hex-vs-binary, and union-narrowing bugs are exactly what specs on `defp` catch.
- **CI enforcement:** in `.credo.exs`, configure `{Credo.Check.Readability.Specs, [include_defp: true]}`. The Credo default is `include_defp: false` (publics-only). We override to `true` because the mandate covers every function. Doctor's spec-coverage gate handles publics; this Credo check closes the gap on privates.
- **Placement:** `@spec` line goes immediately above the `def` / `defp`, after `@doc` / `@doc false`.
- **The one trade-off:** macro-generated `defp` functions can trip the Credo check. Suppress per-callsite with `# credo:disable-for-next-line Credo.Check.Readability.Specs` rather than dropping `include_defp` back to `false`.

## Doctests Are Documentation, Not Tests

**Doctests prove the happy path as readable prose. They are not a substitute for focused ExUnit assertions on edge cases, boundary conditions, or invariants.** When the question is "does my code work the way the readme suggests?", doctests are perfect. When the question is "does my code behave correctly across the full input space?", you need real tests.

**Why the distinction matters:**
- Doctests read top-to-bottom as a narrative. Adding three more doctests to cover empty-list, nil, and union-element cases turns the moduledoc into a wall of fixture noise that future readers skip past.
- Doctests pin one input → one output per example. They don't compose well for "for all X in this set, F(X) preserves invariant Y."
- Doctests can't easily share `setup` blocks, fixtures, or helper functions. ExUnit `describe` blocks can.
- Doctests have no `assert_raise`, no parameterized cases, no `assert_in_delta`, no custom failure messages. They check `inspect/1` equality on the literal expression result.
- Coverage that comes only from doctests is shallow — the doctest proves "this representative input works," not "this branch of the function is exercised."

**The rule:**
- **Add doctests when the example clarifies how the API is meant to be called.** Treat them as compile-checked README snippets.
- **Add ExUnit assertions for everything else** — boundaries (empty/nil/zero/max), unions (each variant of a sum type), invariants (round-trips, idempotence), error paths (`assert_raise`, `flunk`-on-unexpected), and any case where the input space is wider than one demonstrative shape.
- **When a spec narrows or an invariant changes, add focused ExUnit assertions even if a doctest exists.** A doctest that happened to match the new spec doesn't *prove* the spec; it proves one example of it. The assertions document what the spec actually guarantees.

**Concrete heuristic:** if you find yourself writing a second doctest "to also cover the empty case" or "to also cover the integer branch of the union," stop and write an ExUnit `describe` block instead. Doctests that exist to cover edge cases are the failure mode this rule guards against — they bloat the moduledoc, they're harder to maintain, and they signal that the test suite isn't carrying its share of the load.

## Explore Before Coding (Tidewave Workflow)

For external APIs, databases, or unfamiliar code: **explore with `mcp__tidewave__project_eval` before writing any implementation.** Test real API calls, inspect real response structures, field names, data types, and error formats. Never assume. When something breaks, inspect real data flow — don't add debug prints.

Understand reality before implementing against it. Tidewave is the exploration tool; use it liberally before and during development.

## TODO Comment Requirements

**All temporary implementations and production references MUST use the `TODO:` prefix** so `mix credo` can track them. Without the prefix, technical debt is invisible to automated review.

Rewrite phrases like "For now...", "Currently...", "Temporarily...", "In production...", "This is a workaround..." with a `TODO:` prefix. When uncertain about the correct approach, write a TODO explaining the uncertainty — better than a wrong guess; Credo will surface it.

```elixir
# ❌ BAD: credo won't find this
# For now, hardcoded timeout
timeout = 5000

# ✅ GOOD
# TODO: For now, hardcoded timeout — should be configurable
timeout = 5000

# ✅ When genuinely uncertain:
# TODO: Uncertain whether this should retry on :timeout or fail fast — both patterns exist
```

## Cite Ecosystem Precedents Before Crying Complexity

**Before objecting that a macro / DSL / abstraction "is risky" or "could grow knobs," check whether a battle-tested Elixir precedent already solves the same shape.** Generic FUD without a named failure pattern is risk-aversion theater.

Elixir has mature, working-at-scale macro patterns for declarative DSLs. If the proposed shape matches one of these, the "macros are scary" objection is **already disproven by existence**:

| Precedent | Shape | What it proves |
|---|---|---|
| **`Phoenix.Router`** (`get/2`, `post/2`, `scope/2`, `pipe_through/1`) | Declarative HTTP route DSL: verb + path + controller + action + pipeline + helper-name | One macro family handles 6+ orthogonal concerns, working since 2014, used by every Phoenix app |
| **`Ecto.Schema`** (`field/3`, `belongs_to/3`, `has_many/3`, `embeds_many/3`) | Multiple specialized macros instead of one fits-all | Lesson: when shapes genuinely diverge, split macros — don't grow a single one |
| **`NimbleOptions`** | Compile-time validated option-keyword schemas | Removes the "macro grows unchecked knobs" failure mode by making the option surface declarative + validated. Used in Bandit, Plug, Broadway, Oban, hundreds of others |
| **`Absinthe.Schema`** (`field/3`, `arg/3`, `resolve/1`) | GraphQL DSL with arg validation, resolvers, middleware | Variance + composition + introspection in one declaration |
| **LiveView** (`attr/3`, `slot/3`) | Component prop typing + validation + defaults | Modern (2023+) example of disciplined macro DSL |
| **`TypedStruct`** | Single declaration → struct + types + dialyzer specs + validations | Multi-output codegen from one declarative input |
| **`Ash.Resource`** | Whole-resource DSL: attributes, relationships, actions, policies | Largest-scale Elixir DSL in production; proves the pattern scales arbitrarily |

**Rule:** when about to push back on a macro proposal, either (a) name the **specific** Elixir precedent that fails the same way, or (b) accept the proposal as a well-trodden pattern and move to concrete design questions. "Macros are complex" / "DSLs grow" / "this could become a tarball" — without a specific failure pattern — is hedging, not analysis.

**Concrete pattern for new macro DSLs.** Define a `NimbleOptions` schema for the option keyword list:

```elixir
@defrpc_schema NimbleOptions.new!(
  decode: [type: {:in, [:hex_unsigned, :raw_hex, :tx_receipt]}, default: :raw_hex],
  params: [type: :keyword_list, default: []],
  description: [type: :string, required: true]
)

defmacro defrpc(name, method, opts \\ []) do
  opts = NimbleOptions.validate!(opts, @defrpc_schema)
  # expand to function + bang + api() + @spec
end
```

The schema **is** the macro's public contract. Adding a knob requires changing the schema, which makes drift visible at code-review time. This is the pattern Bandit, Plug, Broadway, and Oban all use — proven, mechanical, surfaces complexity instead of hiding it.

## Recommend Libraries Before Crying Friction

**When you're about to characterize some cost as a real trade-off (case-conversion friction, validation boilerplate, encoding wire-format edge cases, parity-maintenance overhead), first check hex.pm.** The default failure mode is treating a solved problem as a cost when a ~5-line dependency reduces it to near-zero. Friction cited without a hex check is hedging dressed up as analysis — and it can flip a real decision (e.g. "stick with the inferior format" / "build it ourselves" / "skip this integration") on the back of a non-existent cost.

**Failure-mode test — about to write any of these? STOP, search hex.pm first:**
- "X feels foreign in idiomatic Elixir" / "X requires manual conversion at the boundary"
- "You'd have to hand-write Y at every call site"
- "Z requires custom encoding/parsing"
- "Maintaining parity between A and B is error-prone"
- "It'd be a lot of boilerplate to bridge that"

**Common reaches (non-exhaustive — search the package, don't recite from this list):**

| Friction the model might claim | Hex package that mostly eliminates it |
|---|---|
| snake_case ↔ camelCase / kebab-case key conversion at API boundaries | `recase` (`Recase.to_camel/1`, `Recase.Enumerable.convert_keys/2`) |
| Hand-validating + defaulting keyword option lists | `nimble_options` |
| Compile-time option/config parsing, doc generation from the schema | `nimble_options` (it generates `@moduledoc` fragments too) |
| Hand-rolling enum values + Ecto type + DB constraint | `ecto_enum` |
| HTTP client with retries, decompression, redirect-handling, JSON, multipart | `req` (almost always the right answer over `httpoison` / raw `:hackney`) |
| JSON encode/decode | `jason` |
| CSV reading with header handling, streaming, large files | `nimble_csv` |
| Struct + types + dialyzer specs + validations from one declaration | `typed_struct` |
| Schema-validated maps (incl. JSON Schema) | `nimble_options`, `peri`, `ex_json_schema` |
| Parameter parsing for CLI tools | `optimus` |
| Cron-like scheduling, recurring jobs | `oban` (also a generic background job runner — usually the right answer over custom GenServer pools) |

**How to apply:**
1. Notice the friction-claim trigger — you're about to write a sentence describing a "cost" or "downside."
2. Search hex.pm for the obvious keywords (one short search; `WebFetch` against `https://hex.pm/packages?search=<term>&sort=downloads` works). Look for packages with > a few thousand downloads + recent commits.
3. If a library handles it, **that's the recommendation** — surface it, show the ~5-line shape, and either drop the friction claim or reframe it honestly ("the boundary code is ~5 lines via `recase`").
4. If you searched and found nothing serious, *say so explicitly* ("checked hex.pm for case-conversion libraries; the choices are recase, proper_case, and macro/ — recase is the right fit") so the cost characterization comes with a citation, not an assertion.

**Sister rules:**
- "Cite Ecosystem Precedents Before Crying Complexity" (above) — same instinct narrowed to macros / DSLs.
- "Investigate Before Building" (`~/.claude/CLAUDE.md` § Working Wisdom) — same instinct for codebase dependencies.

This rule is broader than both: it catches friction-citations in *any* trade-off analysis, not just architectural pushback.

## Tightening a Validator: Trace Inputs, Not Just Callsites

**When narrowing what a function accepts at an API boundary, audit what types flow *into* it — not just who calls it.** Callsite lists are a local neighborhood; the upstream call graph is the actual contract surface.

**Three signals you're about to break a contract:**

1. **The public docstring already lists multiple shapes.** If `@doc` says "0x hex string or 20-byte binary," both shapes ARE the contract. Tightening to one shape is a breaking change, not a cleanup — even if the loose form "feels wrong."
2. **Existing tests named `"accepts X"` are about to flip to `"rejects X"`.** Stop. Those tests document the contract. Ask why they exist before flipping them. They aren't legacy noise; they're the spec.
3. **Upstream normalizers return the "wrong" shape by design.** If a helper like `Address.validate/1` is documented to return a 20-byte binary, every caller of it hands binaries forward. The validator at the boundary inherits that flow whether the local callsite list shows it or not.

**Why this fails repeatedly:** broad solutions look cleaner on paper. "Only accept the canonical form" reads as discipline. But if 30 callsites legitimately pass a non-canonical-but-documented shape, the broad fix produces 30+ failures masquerading as bugs. The lure is real — recognize it as a lure.

**How to apply:**
- Before tightening a validator, search for what types flow *into* it. `Grep` for the input — not just `Grep` for the function name.
- When flipping a test from `accepts X` → `rejects X`, pause. What contract was that test documenting? If the public API says X is legal, the test IS the spec.
- Prefer surgical fixes. The real bug is usually narrow (one ambiguous case colliding with another shape's branch). The surgical fix — accept both shapes, explicitly reject the one ambiguous combination — is almost always correct over the "while we're here, let's only accept canonical" cleanup.
- If you must broaden scope, propose it explicitly: "I can fix the narrow bug, OR I can tighten the contract to canonical-only — the second breaks N internal callers. Which?"
