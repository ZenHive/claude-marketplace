---
name: ex-ast
description: ex_ast — structural AST search, replace, and diff for Elixir source. Use when searching code by syntactic pattern, doing AST-aware find/replace or rewrites, diffing trees, or building code intelligence (index, symbols, comments). Mature. Covers the pattern language, Query DSL, Patcher/Rewriter/Diff API, the ~p sigil, and the CLI.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/ex-ast.md — do not edit manually -->

## ExAST — AST-Pattern Search, Replace, and Diff for Elixir

Structural code search, rewrite, and diff using plain Elixir syntax as patterns — no regex, no custom DSL. The backbone of `reach` smell checks, `ex_dna` clone indexing, and descripex's codemods.

**Min version: `{:ex_ast, "~> 0.12", only: [:dev, :test], runtime: false}`.** Requires `sourceror ~> 1.7` (transitive dep). Ships `jason ~> 1.4` for `--json` CLI output.

**Three mix tasks:** `mix ex_ast.search`, `mix ex_ast.replace`, `mix ex_ast.diff` — operate on files and globs.

**Three API layers:** `ExAST` (file-level), `ExAST.Patcher` (source-string / AST / zipper), `ExAST.Rewriter` (plan-then-apply).

**Pattern language is valid Elixir** — no quoting or escaping beyond what Elixir itself needs. `~p"..."` sigil parses patterns at compile time for zero-overhead hot paths.

**Caveat:** Alias/import expansion is syntax-aware, not full macro-expanded. Struct/map patterns match partially; replacement formatting uses `Macro.to_string/1` — run `mix format` or pass `format: true` after rewrites.

**Does NOT cover:** type analysis (→ Dialyzer), runtime call graphs (→ Reach), clone detection scoring (→ ExDNA).

**Portfolio fit:** `harness` and `descripex` already pull `ex_ast` as a dev dep; `reach` builds its `~p` smell-check DSL on top of it. Codemods in any of these repos (API migrations, deprecation sweeps) are safer via `ExAST.replace` than regex-over-source.

---

### Pattern Language

Patterns are valid Elixir strings. Variable names bind captures; `_` / `_name` are wildcards; `...` is ellipsis (zero or more nodes); `^name` pins to a literal variable name.

| Syntax | Meaning | Example |
|--------|---------|---------|
| `expr`, `result`, `x` | Capture — binds matched node | `{:ok, result}` |
| `_` or `_name` | Wildcard — matches anything, no capture | `Enum.map(_, _)` |
| `...` | Ellipsis — zero or more args / items / body stmts | `IO.inspect(...)` |
| `^name` | Pin — matches a literal variable named `name` | `{:reply, ^state, ^state}` |
| `name` / `fun` / `function` | Captures the function name in `def`/call heads | `def name(_, _) do ... end` |
| Everything else | Literal match | `{:error, :not_found}` |

**Repeated variable names require the same value** at every position:
```elixir
# Matches "{x, x}" but NOT "{x, y}"
ExAST.Patcher.find_all(source, "{a, a}")
```

**Pipes are normalized** — write either form, matches both:
```elixir
# Matches both direct and piped forms
ExAST.Patcher.find_all(source, "Enum.map(_, _)")
# Matches: Enum.map(users, f)  AND  users |> Enum.map(f)
```

**Structs and maps match partially** — only listed keys must be present:
```elixir
ExAST.Patcher.find_all(source, "%User{role: role}")
#=> matches %User{name: "Alice", age: 30, role: :admin}
#   captures: %{role: :admin}
```

**Multi-node patterns** match contiguous statements (separated by `;`):
```elixir
ExAST.Patcher.find_all(source, "a = Repo.get!(_, _); Repo.delete(a)")
```

**Alias/import expansion** — canonical remote-call patterns match aliased/imported call sites:
```elixir
# Matches `Form.for_update(...)` when `alias AshPhoenix.Form` is in scope
ExAST.Patcher.find_all(source, "AshPhoenix.Form.for_update(_, _)")

# Matches `from(...)` when `import Ecto.Query` is present
ExAST.Patcher.find_all(source, "Ecto.Query.from(_, _)")
```

**Module attribute names** are capturable:
```elixir
ExAST.Patcher.find_all(source, "@name Application.get_env(_, _)")
#=> captures: %{name: :env}  for `@env Application.get_env(:app, :key)`
# Use @_ to wildcard the attribute name
```

**What you can match:**
```elixir
"IO.inspect(...)"                          # Any arity
"fun(changeset)"                           # Local call, captures name
"Repo.fun(changeset)"                      # Remote call, captures name
"def name(_, _) do ... end"               # Def, captures function name
"case _ do _ -> _ end"                    # Control flow
"fn _ -> _ end"                           # Anonymous fn
"{:error, e} -> raise e"                  # Standalone clause
"use GenServer"                            # Directive
"@env Application.get_env(_, _)"          # Module attribute
"%{name: name}"                            # Map with partial keys
```

#### Pattern Recipes

```elixir
"Enum.take(_, -_)"                         # Negative literal arg (potential bug)
"{a, a}"                                   # Same value in two positions
"@_ Application.get_env(_, _)"            # Any compile-time config read
"Enum.filter(_, _) |> Enum.map(_)"        # Pipe chain (matches direct form too)
"Logger.info(\"starting\")"               # String literal in call
"def _ do ... end"                         # Any function definition
```

---

### Core API — `ExAST.Patcher` (source / AST / zipper)

`ExAST.Patcher` is the lowest-level entry point. Accepts source strings, `Sourceror.Zipper`, or raw AST.

```elixir
# Find all matches — returns list of match maps
ExAST.Patcher.find_all(source, "IO.inspect(_)")
ExAST.Patcher.find_all(source, "IO.inspect(_)", inside: "test _ do _ end")
ExAST.Patcher.find_all(ast, quote(do: IO.inspect(_)))  # quoted pattern also accepted

# Match map fields:
#   :node     — matched AST node
#   :range    — Sourceror.Range.t() | nil; access as match.range.start[:line]
#   :captures — %{variable_name => AST_node}
#   :source   — matched source text (nil for AST/zipper input)

# Run many patterns in one scan — efficient for analyzers
ExAST.Patcher.find_many(source,
  get_env: "@_ Application.get_env(_, _)",   # tagged :get_env
  dbg_call: "dbg(expr)"                       # tagged :dbg_call
)
# Returns matches with :pattern field added to each match map
```

**Options for `find_all/3`:** `:inside` (ancestor filter), `:not_inside` (exclusion).

---

### File-Level API — `ExAST`

Operates on file paths and globs. Wraps `Patcher` with parallel file scanning.

```elixir
# Search — returns list of match maps with :file field added
ExAST.search("lib/**/*.ex", "IO.inspect(_)")
ExAST.search("lib/", "Repo.get!(_, _)", inside: "defp _ do _ end")
ExAST.search("lib/", query)                # also accepts ExAST.Query selectors

# Options: :limit (stop after N), :allow_broad (allow _ catch-all), :concurrency,
#          :inside, :not_inside

# Multi-pattern search — one pass over files
ExAST.search_many("lib/", get_env: "@_ Application.get_env(_, _)", dbg: "dbg(_)")

# Replace — returns [{file, count}] for modified files
ExAST.replace("lib/**/*.ex", "dbg(expr)", "expr")
ExAST.replace("lib/", "IO.inspect(expr, _)", "Logger.debug(inspect(expr))",
  dry_run: true,      # preview without writing
  format: true,       # run formatter on modified files
  not_inside: "test _ do _ end"
)

# Diff — structural diff between two source strings or files
result = ExAST.diff(old_source, new_source)
result = ExAST.diff_files("lib/old.ex", "lib/new.ex")
result = ExAST.diff(old_source, new_source, include_moves: false)

result.edits  #=> [%ExAST.Diff.Edit{op: :update, kind: :function, summary: "...", ...}]
ExAST.apply_diff(result)  #=> patched source string
```

---

### Rewrite Plans — `ExAST.Rewriter`

Plan-then-apply: preview changes, detect conflicts, then write.

```elixir
# Build a plan (no files written)
plan = ExAST.rewrite_plan(source, "dbg(expr)", "expr")
# %ExAST.Rewriter.Plan{replacements: [...], conflicts: [...]}

# Inspect before committing
plan.replacements
#=> [%ExAST.Rewriter.Replacement{range:, original:, replacement:, captures:}]
plan.conflicts  #=> overlapping ranges, if any

# Apply plan to produce patched source string
ExAST.Rewriter.apply(source, plan)
ExAST.Rewriter.apply(source, plan, on_conflict: :skip)   # :raise | :skip | :keep
```

---

### Query DSL — `ExAST.Query`

Add relationship filters on top of pattern matches.

```elixir
import ExAST.Query

# Find functions that have a Repo.transaction but no debug output
query =
  from("def _ do ... end")
  |> where(contains("Repo.transaction(_)"))
  |> where(not contains("IO.inspect(...)"))

ExAST.search("lib/", query)

# Alternative patterns — match either shape
from(["def _ do ... end", "defp _ do ... end"])

# Capture guards — filter on captured values with ^pin
query =
  from("def handle(event, _) do ... end")
  |> where(^event == :click or ^event == :keydown)

# Structural type check on a capture
query =
  from("Enum.filter(expr, _)")
  |> where(match?({{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, _}, ^expr))

# Any Elixir expression works inside where — match?/2, is_atom/1, comparisons
```

#### Relationship Predicates

| Predicate | Meaning |
|-----------|---------|
| `contains(pat)` | Has a descendant matching pat |
| `has_child(pat)` | Has a direct child matching pat |
| `inside(pat)` | Is inside an ancestor matching pat |
| `parent(pat)` | Has a direct parent matching pat |
| `follows(pat)` | Previous sibling matches pat |
| `precedes(pat)` | Following sibling matches pat |
| `immediately_follows(pat)` | Immediately after a sibling matching pat |
| `immediately_precedes(pat)` | Immediately before a sibling matching pat |
| `first()` | First sibling in parent |
| `last()` | Last sibling in parent |
| `nth(n)` | nth sibling (1-based) |
| `any([...])` | Any predicate in list matches |
| `all([...])` | All predicates in list match |
| `comment_before(text)` | Comment immediately before contains text |
| `comment_after(text)` | Comment immediately after contains text |
| `comment_inside(text)` | Comment inside range contains text |
| `comment_inline(text)` | Inline comment on start line contains text |

Combine with `not`, `and`, `or`. Navigation: `find/2` (descendants), `find_child/2` (direct children).

---

### Diff

Syntax-aware structural comparison — understands Elixir structure; moves are detected, rename/reorder reported separately.

```elixir
result = ExAST.diff_files("lib/old.ex", "lib/new.ex")
result.edits
# [%ExAST.Diff.Edit{op: :update, kind: :function, summary: "updated def first/0", ...}]
```

| `kind` | What changed |
|--------|-------------|
| `:function` | Body or guard |
| `:call` / `:remote_call` | Call site |
| `:map` / `:struct` | Literal shape |
| `:keyword` | Keyword list |
| `:assignment` | Assignment |
| `:module` | Module-level |

Operations: `:insert`, `:delete`, `:update`, `:move`.

Limitations: macros not expanded; moves only detected within the same module body.

---

### Compile-Time Patterns — `~p` Sigil

```elixir
import ExAST.Sigil

# Parses at compile time — no runtime parsing overhead
ExAST.Patcher.find_all(source, ~p"IO.inspect(expr, ...)")
```

Use `~p` in hot paths (Reach smell checks iterate across project files). Reach's own `~p`-backed DSL (`use Reach.Smell.PatternCheck`, `smell ~p[...]`) is built on this.

---

### Code Intelligence APIs

Advisory metadata for external indexes — use to find candidates, then verify with `find_all/3`.

```elixir
# Index plan — what terms to query in an external index
import ExAST.Query

plan =
  from("def _ do ... end")
  |> where(contains("Repo.transaction(_)"))
  |> ExAST.Index.plan()

plan.required_terms   #=> MapSet.new(["call.remote:Repo.transaction/1", ...])
plan.negative_terms   #=> MapSet.new([...])
plan.requires_source? #=> bool — whether source text is needed (not AST alone)
plan.requires_comments? #=> bool — whether comment metadata is needed

# Symbol extraction
ExAST.Symbols.definitions(source)
#=> [%ExAST.Symbol.Definition{kind: :def, qualified_name: "Example.run/1", ...}]

ExAST.Symbols.references(source)
#=> [%ExAST.Symbol.Reference{kind: :remote_call, qualified_name: "Repo.transaction/1", mfa: {Repo, :transaction, 1}}]

ExAST.Symbols.qualified_name({Enum, :map, 2})   #=> "Enum.map/2"
ExAST.Symbols.matches?(ref, "Enum.map/2")        #=> true
ExAST.Symbols.matches?(ref, {Enum, :map, 2})     #=> true

# Terms (lower-level stable index strings)
ExAST.Index.Terms.from_source("Repo.transaction(fn -> :ok end)")
ExAST.Index.Terms.from_ast(ast)
ExAST.Index.Terms.from_pattern("def run(arg) do ... end")

# Comment extraction
ExAST.Comments.extract(source)
#=> [%ExAST.Comment{text: "# TODO", line: 12, column: 3}]
ExAST.Comments.associated(source, range, :before)
```

---

### CLI Reference

```bash
# Search
mix ex_ast.search 'IO.inspect(_)' lib/
mix ex_ast.search 'Repo.get!(_, _)' lib/ --inside 'defp _ do _ end'
mix ex_ast.search 'IO.inspect(_)' lib/ --not-inside 'test _ do _ end'
mix ex_ast.search 'def _ do ... end' lib/ --count
mix ex_ast.search 'def _ do ... end' lib/ --limit 20
mix ex_ast.search 'def _ do ... end' --comment-inside '/TODO|FIXME/' lib/
mix ex_ast.search 'IO.inspect(_)' lib/ --format json

# Replace
mix ex_ast.replace 'dbg(expr)' 'expr' lib/
mix ex_ast.replace 'use Mix.Config' 'import Config' config/ --dry-run
mix ex_ast.replace 'IO.inspect(expr)' 'expr' lib/ --not-inside 'test _ do _ end'
mix ex_ast.replace 'dbg(expr)' 'expr' lib/ --format-output    # runs mix format on changed files
mix ex_ast.replace 'dbg(expr)' 'expr' lib/ --dry-run --json

# Diff
mix ex_ast.diff lib/old.ex lib/new.ex
mix ex_ast.diff lib/old.ex lib/new.ex --summary
mix ex_ast.diff lib/old.ex lib/new.ex --json
mix ex_ast.diff lib/old.ex lib/new.ex --no-moves
```

All `search` relationship flags (`--inside`, `--not-inside`, `--contains`, `--not-contains`, `--parent`, `--follows`, etc.) are also available on `replace`. Comment value flags accept `/.../` regex syntax.

---

### Common Issues

| Problem | Cause | Fix |
|---------|-------|-----|
| Pattern finds nothing despite visible match | Pipes not normalized in your head — pattern needs direct form | Write direct-call form; ex_ast normalizes pipes automatically |
| Replacement output is unformatted | `Macro.to_string/1` doesn't preserve style | Pass `format: true` to `replace/4` or run `mix format` after |
| "broad search" error on `from("_")` | Catch-all pattern refused project-wide | Pass `:limit` or `allow_broad: true` |
| Repeated variable doesn't constrain | Typo — variable names must be identical | Use the exact same atom key at both positions |
| Alias match fails | Alias not in scope at pattern parse time | ExAST IS alias-aware — verify the alias is explicit in the file (not just in the test source) |
| Multi-node pattern misses | Statements are not contiguous | Semi-colon syntax only matches adjacent statements in the same block |
| `~p` sigil compile error | Pattern string not a literal | `~p` only works with compile-time string literals |

---

### DO NOT

1. Invent function names — every name above was verified from source/docs. Modules are `ExAST`, `ExAST.Patcher`, `ExAST.Rewriter`, `ExAST.Query`, `ExAST.Selector`, `ExAST.Index`, `ExAST.Symbols`, `ExAST.Comments`, `ExAST.Sigil`.
2. Rely on index terms as match results — `ExAST.Index.plan/1` output is advisory; always verify candidates with `find_all/3`.
3. Skip `mix format` (or `format: true`) after `replace` — `Macro.to_string/1` drops custom formatting.
4. Use `replace` without `--dry-run` first on unfamiliar patterns — always preview.
5. Pass `allow_broad: true` in production tooling — broad searches over entire project trees are slow; use `contains` predicates to narrow.
6. Expect macro-expanded matches — ExAST works on the source AST; `use GenServer` generated callbacks are invisible (use Reach's BEAM frontend for those).

---

### Dependencies

```elixir
# mix.exs — dev/test only
{:ex_ast, "~> 0.12", only: [:dev, :test], runtime: false}
# Transitive: sourceror ~> 1.7, jason ~> 1.4
```

Required by Reach (`ex_ast ~> 0.12.0` in Reach's own dep spec). No runtime component — safe as `:runtime: false` in all use cases.
