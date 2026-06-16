---
name: exograph
description: exograph — CodeQL-style structural code search over Elixir. Use when querying a codebase by structural shape, building or searching a code index, indexing Hex packages via mix exograph.index.hex, running call-graph queries, or exploring via the web UI. Heavy stack with DuckDB/QuackDB or Postgres backends. Covers the query DSL, backends, and indexing.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/exograph.md — do not edit manually -->

## Exograph — CodeQL-style structural code search for Elixir

Indexes source code into normalized Ecto tables (DuckDB/QuackDB or Postgres) and queries them with an Ecto-shaped DSL combining ExAST structural pattern matching, text/regex FTS, and optional Reach-backed call graphs.

**Min version: `{:exograph, "~> 0.8"}`.** Requires Elixir ~> 1.19. 18 deps; heaviest of the elixir-vibe suite.

**Query surface:** structural AST patterns via `Exograph.DSL.matches/2`, text/regex via `Exograph.search_text/3`, symbol/reference filters via relational joins on `Definition` / `Reference` / `CallEdge` schemas.

**Two backends:** DuckDB/QuackDB (default, embedded, shard-friendly) or Postgres (multi-user, optional ParadeDB BM25). See decision table below.

**Optional Reach integration** (`{:reach, "~> 2.2"}`) unlocks `Exograph.CallEdge` indexing and `search_callers/search_callees` queries; omit if call graph analysis isn't needed.

**Caveat:** `matches/2` performs ExAST exact verification after a fast DB candidate pass — patterns must be valid ExAST pattern strings. Regex search uses DuckDB FTS or Postgres BM25 depending on backend; BM25 ranking differs between the two.

**Does NOT cover:** multi-language analysis, hosted/cloud search, LSP/language server protocol, runtime analysis (→ Reach), or security scanning (→ Sobelow).

**Portfolio fit:** harness reviewer step — replace opaque `mix credo` output with structural queries (`matches(f, "def _ do ... end")` + reference joins) to locate patterns across packages; descripex cross-package contract checks use `search_callers/search_callees` to verify callback coverage across package versions.

---

### Backend Decision Table (DuckDB vs Postgres)

| | DuckDB / QuackDB | Postgres (+ ParadeDB) |
|---|---|---|
| **Setup** | `{:quackdb, "~> 0.5.13"}` in deps; no server | Running Postgres instance + optional `pg_search` extension |
| **Best for** | Local analysis, CI, large Hex corpora, parallel sharding | Multi-user, persistent shared index, org-wide search |
| **Sharding** | `%Exograph.ShardedIndex{}` — independent shard files, fan-out merge in memory | Not sharded; single schema |
| **Text search** | DuckDB FTS + BM25 out of the box | BM25 via ParadeDB `pg_search` (opt-in), standard PG `ILIKE` without it |
| **Manifest persistence** | `--manifest-path` flag on `mix exograph.index.hex` | N/A |
| **Concurrent writes** | Single writer per shard file | PG standard concurrency |
| **When to pick** | Default; fine for all single-machine use | Need shared persistent index or already running PG stack |

---

### Installation

```elixir
# mix.exs
def deps do
  [
    {:exograph, "~> 0.8"},                          # core — pulls quackdb by default
    {:reach, "~> 2.2", optional: true}              # only if you need call-graph indexing
  ]
end
```

For Postgres backend, add `{:postgrex, "~> 0.22"}` and configure a standard Ecto repo pointed at your DB.

---

### Indexing (building the index)

```elixir
# In-process — single source tree, DuckDB default
{:ok, index} =
  Exograph.index("lib",
    repo: MyApp.QuackDBRepo,     # Ecto repo module backed by QuackDB or Postgres
    migrate?: true               # run schema migrations on first run
  )

# Multiple paths
{:ok, index} = Exograph.index(["lib", "test"], repo: MyApp.QuackDBRepo, migrate?: true)
```

**Sharded index** (large corpora — e.g. top Hex packages):

```elixir
# Each shard is an independent DuckDB file
{:ok, shard_a} = Exograph.index("lib/core", repo: MyApp.ShardARepo, migrate?: true)
{:ok, shard_b} = Exograph.index("lib/web",  repo: MyApp.ShardBRepo, migrate?: true)

sharded = Exograph.ShardedIndex.new([shard_a, shard_b])
# Query APIs fan out to every shard and merge in memory — no merged DB needed
{:ok, hits} = Exograph.search(sharded, "Repo.get!(_, _)")
```

---

### CLI Mix Tasks

**Index local source:**
```bash
mix exograph.index "lib" --repo MyApp.QuackDBRepo
```

**Index Hex.pm packages** (`mix exograph.index.hex`):
```bash
# One version per package (most common)
mix exograph.index.hex --mode latest --duckdb-shards 4 --prefix hex

# Top N by downloads
mix exograph.index.hex --mode top --limit 5000 --prefix hex

# Every published version (large)
mix exograph.index.hex --mode all --prefix hex

# Use a Hex mirror
mix exograph.index.hex --mode latest --mirror https://hex.elixir.toys --prefix hex

# With live progress dashboard at /progress
mix exograph.index.hex --mode latest --web --port 4200
```

Indexing resumes automatically after interruption (manifest tracks progress).

**Web UI:**
```bash
mix exograph.web --prefix myindex --port 4200
```

**CLI search:**
```bash
mix exograph.search "Repo.transaction(_)" --repo MyApp.QuackDBRepo
```

---

### Query DSL (`Exograph.DSL`)

The DSL is Ecto-shaped. Import `Exograph.DSL` and compose queries using `from/2`, `where`, `matches/2`, `contains/2`, `prefix_search/2`, and `assoc/2`.

**Schema bindings available in queries:** `Fragment`, `Definition`, `Reference`, `CallEdge`, `Comment`, `File`, `Package`, `PackageVersion`.

```elixir
import Exograph.DSL

# Structural: find all function definitions containing a Repo.transaction call
query =
  from(f in Fragment,
    where: matches(f, "def _ do ... end"),     # ExAST structural pattern
    where: contains(f, "Repo.transaction(_)")  # fast DB pre-filter
  )

{:ok, hits} = Exograph.all(index, query)

# Relational: find fragments that reference a specific qualified name
query =
  from(f in Fragment,
    join: r in assoc(f, :references),
    where: r.qualified_name == "Repo.transaction/1",
    where: matches(f, "def _ do ... end")
  )

{:ok, hits} = Exograph.all(index, query)

# Definition lookup
query =
  from(d in Definition,
    where: prefix_search(d, "MyApp.Accounts"),
    join: f in assoc(d, :fragment)
  )

{:ok, hits} = Exograph.all(index, query)
```

---

### Search API (`Exograph` module)

```elixir
# Structural search — ExAST pattern string
{:ok, hits} = Exograph.search(index, "Repo.get!(_, _)")
{:ok, hits} = Exograph.search(index, "case _ do {:ok, _} -> _; {:error, _} -> _ end")

# Text / regex search
{:ok, hits} = Exograph.search_text(index, "transaction")           # literal
{:ok, hits} = Exograph.search_text(index, ~r/def handle_\w+/)     # regex

# DSL query (most flexible)
{:ok, hits} = Exograph.all(index, query)

# Call graph (requires Reach integration)
{:ok, edges} = Exograph.search_callers(index, "Repo.transaction/1")
{:ok, edges} = Exograph.search_callees(index, "MyApp.Accounts.update_user/2")
```

Return types: `Exograph.Hit.t()` (base), or the specific subtype — `DefinitionHit`, `ReferenceHit`, `TextHit`, `CommentHit`, `CallEdgeHit`.

---

### Web UI

```bash
mix exograph.web --prefix myindex --port 4200
```

- Monaco editor with Elixir syntax highlighting and autocompletion
- Structural, text, and regex search modes with IDE-style error diagnostics
- Results grouped by package with code previews and Hex.pm links
- Live progress dashboard at `/progress` during `mix exograph.index.hex --web`

**JSON API** (rate-limited 60 req/min, cursor pagination):
```
POST /api/search    — structural / text / regex search
POST /api/query     — DSL query execution
GET  /api/packages  — list indexed packages
GET  /api/stats     — index statistics
```

---

### Recipes

**Find all private functions calling a specific module:**
```elixir
import Exograph.DSL

from(f in Fragment,
  join: r in assoc(f, :references),
  where: r.qualified_name == "SomeModule.sensitive_fn/1",
  where: matches(f, "defp _ do ... end")
)
|> then(&Exograph.all(index, &1))
```

**Cross-package: who calls `Ecto.Repo.transaction/1` across indexed Hex packages:**
```elixir
{:ok, edges} = Exograph.search_callers(index, "Ecto.Repo.transaction/1")
Enum.map(edges, & &1.caller_qualified_name)
```

**Find every `GenServer.call` with a pattern match on result:**
```elixir
{:ok, hits} = Exograph.search(index, "case GenServer.call(_, _) do _ -> _ end")
```

**Text search then structural verification:**
```elixir
# Fast candidate pass
{:ok, text_hits} = Exograph.search_text(index, "broadway")

# Follow up with structural match on candidates
import Exograph.DSL
from(f in Fragment,
  join: r in assoc(f, :references),
  where: r.qualified_name == "Broadway.start_link/2",
  where: matches(f, "def start_link(_) do ... end")
)
|> then(&Exograph.all(index, &1))
```

---

### Module Map

| Module | Role |
|--------|------|
| `Exograph` | Primary API: `index/2`, `search/3`, `search_text/3`, `all/3`, `search_callers/3`, `search_callees/3` |
| `Exograph.DSL` | Query builder: `from/2`, `matches/2`, `contains/2`, `prefix_search/2`, `assoc/2` |
| `Exograph.Index` | Runtime handle keeping fragment store + inverted index + tree store together |
| `Exograph.ShardedIndex` | Fan-out wrapper over multiple `Index.t()` shards; same query API |
| `Exograph.Fragment` | Searchable code unit (function body, clause, expression) |
| `Exograph.Definition` | Syntactic definition extracted from source |
| `Exograph.Reference` | Syntactic reference extracted from source |
| `Exograph.CallEdge` | Reach-derived call graph edge (requires `reach` dep) |
| `Exograph.DuckDB` | Schema helpers for DuckDB backend |
| `Exograph.Postgres` | Schema helpers for Postgres backend |

---

### Common Issues

| Problem | Cause | Fix |
|---------|-------|-----|
| `matches/2` returns 0 hits on valid code | Pattern syntax error — ExAST is strict | Test the pattern with `ExAST.pattern/1` first; use `_` as wildcard for any subterm |
| `search_callers/2` returns empty but Reach finds edges | Reach dep not added or `Exograph.Extractor.Reach` not run during index | Add `{:reach, "~> 2.2"}` and re-index with `migrate?: true` |
| Sharded index fanout OOM on very large corpora | All shard results merged in memory | Limit with `opts: [limit: N]` on `Exograph.all/3`; paginate via cursor API |
| DuckDB concurrent write error | Two indexing processes on same shard file | Use separate `--prefix` per indexing run; merge via `ShardedIndex` at query time |
| FTS ranking differs between backends | DuckDB FTS vs Postgres BM25 (ParadeDB) use different scoring | Normalise on `fragment_id` rather than score rank when comparing backends |
| `mix exograph.index.hex` stalls and doesn't resume | Manifest path not set | Pass `--manifest-path hex_index.json`; indexing then resumes from last checkpoint |

---

### DO NOT

1. Use `Exograph.search/3` for semantic flow analysis — it's structural only; for taint/data-flow use Reach.
2. Forget `migrate?: true` on first index — the schema tables won't exist and queries will error.
3. Run two concurrent `mix exograph.index.hex` processes against the same DuckDB shard file (single-writer constraint).
4. Use `Exograph.all/3` without a `limit` in the opts on large corpora — result sets can be very large.
5. Invoke the Hex.pm indexer (`--mode all`) without planning storage — every version of every package is large.
6. Treat `search_text/3` regex as structural — it matches source text, not AST shape; a regex matching `def foo` also hits comments and strings.

---

### Testing Notes

Exograph ships with `pi_bridge` (dev/test only) for fixture-based index snapshots. In unit tests, index a small fixture directory rather than the full project:

```elixir
# test/support/exograph_case.ex
defmodule MyApp.ExographCase do
  use ExUnit.CaseTemplate
  setup do
    {:ok, index} = Exograph.index("test/fixtures/code", repo: MyApp.TestRepo, migrate?: true)
    %{index: index}
  end
end
```

Avoid indexing `lib/` in unit tests — startup cost is O(file count × parse time). Use a fixture subtree.

---

### Dependencies

```elixir
# Required
{:exograph, "~> 0.8"},
{:quackdb, "~> 0.5.13"}   # pulled transitively for DuckDB backend

# Optional: call graph indexing
{:reach, "~> 2.2", optional: true}

# Optional: Postgres backend (instead of DuckDB)
{:postgrex, "~> 0.22"}
```

Transitive runtime deps (selected): `ex_ast ~> 0.11`, `ex_dna ~> 1.5`, `broadway ~> 1.2`, `ecto_sql ~> 3.13`.
Web UI optional deps (auto-detected): `phoenix ~> 1.8`, `phoenix_live_view ~> 1.1`, `bandit ~> 1.5`, `makeup_elixir ~> 1.0` — only needed if running `mix exograph.web`.
