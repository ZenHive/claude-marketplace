---
name: ex-dna
description: ex_dna — AST-based clone detector for Elixir (CLI, Credo plugin, LSP). Use when finding duplicated or near-duplicate code (Type I/II/III clones), wiring clone detection into CI or Credo, or configuring suppression. Suppress via inline # ex_dna:disable-* comments, NOT @no_clone. Covers detection modes, CLI flags, .ex_dna.exs config, the Credo plugin, and the LSP server.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/ex-dna.md — do not edit manually -->

## ExDNA — AST Clone Detector for Elixir

Finds code duplication by analyzing abstract syntax trees rather than text — `fn(a, b) -> a + b end` and `fn(x, y) -> x + y end` are the same code. Three clone types: exact (I), renamed-variable/changed-literal (II), near-miss structural (III). Ships a Credo plugin, Mix compiler hook, and LSP server.

**Min version: `{:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false}`.** Pinned at v1.5.3.

**The PostToolUse hook runs `mix ex_dna` bare — Type I (exact) detection, default mass 30, console output, exits 1 on any clone.**

**Three normalization passes feed BLAKE2b hashing:** strip line/column metadata → rename variables to positional placeholders (`$0`, `$1`) → optionally abstract literals → optionally flatten pipes → sort struct/map fields. Fingerprints are cached in `.ex_dna_cache` (add to `.gitignore`) for incremental re-runs.

**Performance:** Plausible (465 files) ~1 second; Ash (554 files) ~6 seconds for full Type-I/II/III.

**Caveat:** Type-III near-miss clones (tree edit distance + Jaccard) can be noisy on large brownfield projects — raise `--min-fuzzy-mass` or `--min-mass` before enabling `--min-similarity`.

**Does NOT cover:** semantic / data-flow duplication (→ Reach), linting anti-patterns (→ ex_slop/Credo), runtime analysis.

### Clone Types and When to Enable Them

| Type | What it catches | How to enable |
|------|----------------|---------------|
| I — Exact | Identical code ignoring whitespace/comments | Default; no flags needed |
| II — Renamed | Variable renames, changed literals, field-order variation, guard class swaps, `&&`/`and` equivalence, sigil expansion | `--literal-mode abstract` (changed literals) — variable renaming is always on |
| III — Structural | Near-miss clones via Jaccard similarity + tree edit distance | `--min-similarity 0.85` (any value < 1.0 enables it) |

Guard normalization, boolean operator normalization (`&&`/`and`, `\|\|`/`or`), and sigil expansion (`~w(foo bar)a` ↔ `[:foo, :bar]`) are always active in Type-II mode regardless of `--literal-mode`.

### CLI Reference (`mix ex_dna`)

```bash
mix ex_dna                               # scan lib/ — what the PostToolUse hook runs
mix ex_dna lib/accounts lib/admin        # specific paths

# Broaden detection progressively:
mix ex_dna --literal-mode abstract       # Type II: also catch changed literals
mix ex_dna --min-similarity 0.85         # Type III: near-miss structural clones
mix ex_dna --normalize-pipes             # treat x |> f() same as f(x)

# Tune sensitivity:
mix ex_dna --min-mass 50                 # fewer, larger clones (default: 30)
mix ex_dna --min-fuzzy-mass 80           # minimum size for Type-III candidates
mix ex_dna --min-occurrences 3           # only report 3+ occurrence groups

# CI budget:
mix ex_dna --max-clones 10               # exit 1 only above threshold, not always

# Output:
mix ex_dna --format json                 # machine-readable
mix ex_dna --format html                 # self-contained browsable report
mix ex_dna --format sarif                # GitHub Code Scanning
mix ex_dna --output report.html          # specify output path for html/sarif

# Deep-dive a specific clone (pass same flags as mix ex_dna for consistent numbering):
mix ex_dna.explain 3
mix ex_dna.explain 3 lib/accounts --min-mass 20

# LSP server (runs alongside Expert/ElixirLS):
mix ex_dna.lsp
```

### Full Options Table

| Option | CLI flag | Default | Description |
|--------|----------|---------|-------------|
| `min_mass` | `--min-mass` | `30` | Minimum AST node count for a fragment |
| `min_occurrences` | `--min-occurrences` | `2` | Minimum locations to label a clone |
| `min_similarity` | `--min-similarity` | `1.0` | Type-III threshold; set < 1.0 to enable |
| `min_fuzzy_mass` | `--min-fuzzy-mass` | `min_mass * 2` | Minimum size for Type-III candidates |
| `literal_mode` | `--literal-mode` | `keep` | `keep` = exact + renamed; `abstract` = also changed literals |
| `normalize_pipes` | `--normalize-pipes` | `false` | Treat `x \|> f()` same as `f(x)` |
| `excluded_macros` | `--exclude-macro` | `[]` | Macro calls to skip entirely |
| `ignored_attributes` | `--ignore-attribute` | *(reserved attrs)* | Module attribute names to skip |
| `max_module_forms` | `--max-module-forms` | `200` | Max top-level forms for sibling-window detection |
| `ignore` | `--ignore` | `[]` | Glob patterns to exclude |
| `output_file` | `--output` | format default | Output path for html/sarif |
| `parse_timeout` | — | `5000` | Max ms per file (kills hung parses) |
| — | `--max-clones` | — | Clone budget (exit 1 only above this count) |
| — | `--format` | `console` | `console`, `json`, `html`, or `sarif` |

Default ignored attributes: all of Elixir's reserved attributes (`moduledoc`, `doc`, `spec`, `type`, `impl`, `behaviour`, `derive`, etc.). **Custom attributes like `@extensions`, `@timeout`, or `@fields` are fingerprinted and will flag as clones when identical across modules.**

### `.ex_dna.exs` Config File

Options are layered: **defaults → `.ex_dna.exs` → CLI flags**.

```elixir
# .ex_dna.exs — project root
%{
  min_mass: 25,
  min_occurrences: 3,
  ignore: ["lib/my_app_web/templates/**"],
  excluded_macros: [:schema, :pipe_through, :plug],
  normalize_pipes: true
}
```

### Programmatic API

```elixir
@spec analyze(path_or_paths() | keyword()) :: ExDNA.Report.t()

report = ExDNA.analyze("lib/")
report = ExDNA.analyze(["lib/", "test/"])
report = ExDNA.analyze(paths: ["lib/", "test/"], min_mass: 20, literal_mode: :abstract)

report.clones   #=> [%ExDNA.Detection.Clone{}, ...]
report.stats    #=> %{files_analyzed: 42, total_clones: 3, ...}
```

### Multi-Clause and Delegation Awareness

- **Multi-clause grouping** — consecutive `def`/`defp` clauses with the same name/arity are analyzed as a single unit. Individual clauses may be below `min_mass`; the combined unit may not be.
- **Delegation grouping** — `def foo(x), do: foo(x, [])` + `def foo(x, opts)` are treated as one unit, catching duplicated wrapper+body pairs across modules.
- **Sibling window detection** — adjacent functions copied between modules are caught even when surrounding code differs.

### Suppression Comments

```elixir
# ex_dna:disable-for-this-file          # suppress entire file
# ex_dna:disable-for-next-line          # suppress following line
# ex_dna:disable-for-previous-line      # suppress preceding line
# ex_dna:disable-for-lines:3            # suppress next N lines
```

### Credo Plugin (replaces built-in DuplicatedCode)

Reuses Credo's already-parsed ASTs — no double parsing. Upgrades `Credo.Check.Design.DuplicatedCode` to full Type-I/II/III with refactoring suggestions.

```elixir
# .credo.exs — recommended: plugin form (auto-disables built-in DuplicatedCode)
%{
  configs: [
    %{
      name: "default",
      plugins: [{ExDNA.Credo, []}]
    }
  ]
}
```

Or add directly to `:enabled` checks and disable the built-in:

```elixir
{ExDNA.Credo, [
  paths: ["lib/", "test/"],
  min_mass: 40,
  literal_mode: :abstract,
  excluded_macros: [:schema, :pipe_through],
  normalize_pipes: true,
  min_similarity: 0.85
]},
{Credo.Check.Design.DuplicatedCode, false}
```

All `mix ex_dna` options are valid as Credo check params. Default path scope is `lib/`; add `paths: ["lib/", "test/"]` to include tests.

### Incremental Mix Compiler

```elixir
# mix.exs — only changed files re-analyzed on mix compile
def project do
  [compilers: Mix.compilers() ++ [:ex_dna]]
end
```

Cache stored in `.ex_dna_cache` — add to `.gitignore`.

### LSP Server (Neovim example)

```bash
mix ex_dna.lsp    # runs alongside Expert or ElixirLS; pushes inline diagnostics on save
```

```lua
-- Neovim config
vim.lsp.config('ex_dna', {
  cmd = { 'mix', 'ex_dna.lsp' },
  root_markers = { 'mix.exs' },
  filetypes = { 'elixir' },
})
```

### Reach Integration

Reach's `.reach.exs` can delegate clone detection to ExDNA via `clone_analysis`:

```elixir
# .reach.exs
[
  clone_analysis: [provider: :ex_dna, min_mass: 30, min_similarity: 1.0, max_clones: 50],
  ...
]
```

When set, `mix reach.check --smells` structural-drift checks (return-contract drift, validation drift, side-effect ordering drift) pull clone data from ExDNA rather than Reach's own heuristics.

### Refactoring Suggestions

`mix ex_dna.explain N` anti-unifies the clone pair: common structure, divergence points, and the suggested extraction with call sites. Three suggestion types:

| Suggestion | When | Extract target |
|------------|------|----------------|
| `extract_function` | Pure common structure | `defp` with positional args |
| `extract_macro` | Common DSL/metaprogramming structure | `defmacro` |
| `extract_behaviour` | Modules expose the same public callback set | `@behaviour` with `@callback` |

Suggestions are named after the dominant struct, call, or pattern (`build_changeset`, `contact_step`) rather than generic `extracted_function`.

### Common Issues

| Problem | Cause | Fix |
|---------|-------|-----|
| Too many false positives on generated code | `min_mass` too low, or generated files not excluded | Add `ignore: ["lib/generated/**"]` to `.ex_dna.exs` |
| Custom `@attrs` flagged as clones | All non-reserved module attributes are fingerprinted | Add to `ignored_attributes` in `.ex_dna.exs` |
| Type-III run very slow | `--min-fuzzy-mass` defaults to `min_mass * 2` — small value scans many candidates | Raise `--min-fuzzy-mass 80` or `--min-mass 50` before enabling Type-III |
| Clone numbers shift between `mix ex_dna` and `mix ex_dna.explain` | Different paths or flags were used | Pass identical paths + flags to both commands |
| `mix ex_dna` not found | Not in `deps` or `runtime: false` omitted | Ensure `{:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false}` |
| Incremental cache stale after branch switch | `.ex_dna_cache` fingerprints reference old ASTs | `rm -rf .ex_dna_cache` and re-run |

### DO NOT

1. Run `mix ex_dna` with `--min-similarity 0.5` or lower — Jaccard similarity at that threshold produces too many low-signal near-misses.
2. Add `ExDNA.Credo` plugin without disabling `Credo.Check.Design.DuplicatedCode` — both will run and double-report clones.
3. Commit `.ex_dna_cache` — it contains file-path-absolute fingerprints that break on other machines.
4. Use `--max-clones 0` as a synonym for "fail on any clone" — the bare invocation already exits 1 on any clone; `--max-clones 0` means budget of zero (same effect but confusing to reviewers).
5. Add `ex_dna` to `:prod` deps — it's a dev-only static analysis tool with no runtime value.

### Portfolio Fit

`harness` and `descripex` already carry `ex_dna` as a dev-dep and the PostToolUse hook fires `mix ex_dna` (bare, Type I) on every Edit/Write — this include closes the documentation gap so future instances understand what that hook does and how to tune it.

### Dependencies

```elixir
{:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false}
```

No additional runtime deps beyond the BEAM. Optional: `{:credo, "~> 1.7"}` for Credo integration (ExDNA reuses Credo's parsed ASTs when both are present).
