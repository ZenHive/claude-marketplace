---
name: development-philosophy
description: Elixir documentation and internal-API conventions. Use when writing @doc/@moduledoc/@spec, hiding internal functions (defp vs @doc false vs @moduledoc false vs leading underscore; @opaque/@typep for types), choosing doctests vs ExUnit assertions, tagging deferred work with TODO:, tightening a validator at an API boundary, or before objecting that a macro/abstraction is complex or some cost is real friction — cite ecosystem precedents and check hex.pm for a library first.
allowed-tools: Read, Grep, Glob, Bash
---

<!-- Auto-synced from ~/.claude/includes/development-philosophy.md — do not edit manually -->

## Elixir Documentation Standards

**No IO in `@doc` examples.** `@doc` demonstrates API usage (`{:ok, user} = MyApp.get_user("id")`), not console output (`IO.puts` / `IO.inspect`).

**Doctests are documentation, not tests.** Add a doctest when the example clarifies how the API is called. Boundaries, union variants, invariants and error paths go in ExUnit `describe` blocks — a second doctest "to also cover the empty case" is the signal to switch.

## Specs on Every Function

**Every function gets a `@spec` — `def` and `defp` alike.** The community default is publics-only; this portfolio overrides it because Dialyzer pointing at a spec mismatch is faster than a downstream call site three layers away, and signing / wire-format code is exactly where binary-length, hex-vs-binary and union-narrowing bugs live.

- **Enforcement:** `.credo.exs` → `{Credo.Check.Readability.Specs, [include_defp: true]}` (Credo default is `false`). Doctor covers publics.
- **Placement:** `@spec` immediately above the `def` / `defp`, after `@doc` / `@doc false`.
- **Macro-generated `defp`** tripping the check → `# credo:disable-for-next-line Credo.Check.Readability.Specs` at the callsite; never drop `include_defp`.

## TODO Comment Requirements

**Temporary implementations and production references use the `TODO:` prefix** so `mix credo` tracks them. Rewrite "For now…", "Currently…", "Temporarily…", "This is a workaround…" as a `TODO:` — this is the one place sequencing language is allowed (see critical-rules § scope-sequencing qualifiers), because a `TODO:` exists to be tracked and removed.

```elixir
# TODO: hardcoded timeout — should be configurable
timeout = 5000

# TODO: Uncertain whether this should retry on :timeout or fail fast — both patterns exist
```

Genuinely uncertain about the approach → a `TODO:` explaining the uncertainty beats a wrong guess.

## Cite Precedents Before Crying Complexity

Before objecting that a macro / DSL / abstraction "is risky" or "could grow knobs", either (a) name the **specific** precedent that failed the same way, or (b) accept it as a well-trodden pattern (Phoenix.Router, Ecto.Schema, LiveView `attr`, Ash.Resource …) and move to concrete design questions. Generic "macros are complex" without a named failure is risk-aversion theater.

For a new macro DSL, the option surface is a `NimbleOptions` schema validated in the macro — the schema is the public contract, so adding a knob is a visible schema change.

## Recommend Libraries Before Crying Friction

About to characterize a cost as a trade-off ("manual conversion at the boundary", "hand-written at every call site", "custom encoding", "parity is error-prone")? Search hex.pm first. A library that handles it is the recommendation — show the ~5-line shape and drop or reframe the claim. Found nothing serious → say so with what you checked, so the cost comes with a citation.

## Tightening a Validator: Trace Inputs, Not Just Callsites

When narrowing what a function accepts at an API boundary, audit what types flow *into* it — the upstream call graph is the contract surface, not the local callsite list. Three signals you're about to break a contract:

1. **The public `@doc` already lists multiple shapes** ("0x hex string or 20-byte binary") — both ARE the contract; tightening is a breaking change.
2. **Tests named `"accepts X"` are about to flip to `"rejects X"`** — they document the contract; ask why they exist first.
3. **Upstream normalizers return the "wrong" shape by design** (e.g. `Address.validate/1` returns a binary) — every caller forwards it.

Prefer the surgical fix (accept both shapes, reject the one ambiguous combination). If broadening is warranted, propose it explicitly with the number of callers it breaks.
