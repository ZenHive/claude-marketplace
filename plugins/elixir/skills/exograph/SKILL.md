---
name: exograph
description: exograph — CodeQL-style structural code search over Elixir. Use when querying a codebase by structural shape, building or searching a code index, indexing Hex packages via mix exograph.index.hex, running call-graph queries, or exploring via the web UI. Heavy stack with DuckDB/QuackDB or Postgres backends. Covers the query DSL, backends, and indexing.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/exograph.md — do not edit manually -->

## Exograph — CodeQL-style structural code search for Elixir

Indexes source code into normalized Ecto tables (DuckDB/QuackDB) and queries them with an Ecto-shaped DSL combining ExAST structural pattern matching, text/regex FTS, Reach-backed source-smell audits, and optional call graphs.

**Min version: `{:exograph, "~> 0.9"}`.** Requires Elixir ~> 1.19. DuckDB/QuackDB is the **only** storage backend as of 0.9.0 (Postgres removed). 18+ deps; heaviest of the elixir-vibe suite.

**Query surface:** structural AST patterns via `Exograph.DSL.matches/2`, text/regex via `Exograph.search_text/3`, symbol/reference filters via relational joins on `Definition` / `Reference` / `CallEdge` schemas, Reach source-smell audits via `Exograph.Reach.SourceSmellAudit.scan/3`.

**Optional Reach integration** (`{:reach, "~> 2.2"}`) unlocks `Exograph.CallEdge` indexing, `search_callers/search_callees` queries, and `Exograph.Reach.SourceSmellAudit` smell scans; omit if call graph and smell analysis aren't needed.

**Caveat:** `matches/2` performs ExAST exact verification after a fast DB candidate pass — patterns must be valid ExAST pattern strings. ExAST 0.12.9 (bundled via exograph 0.9.10) added pipe-equivalent calls, keyword literals, negative integer arguments, and wildcard-safe source terms. The `/api/stats` endpoint exposes `poisoned_structural_names` — a non-zero value means identifier-encoding bugs are silently returning zero matches for common patterns like `Repo.get!(_, _)` (fixed in 0.9.5; check this counter after any major re-index).

**Does NOT cover:** multi-language analysis, hosted/cloud search, LSP/language server protocol, runtime analysis (→ Reach), security scanning (→ Sobelow), or Postgres storage (removed in 0.9.0).

**Portfolio fit:** harness reviewer step — replace opaque `mix credo` output with structural queries (`matches(f, "def _ do ... end")` + reference joins) to locate patterns across packages; descripex cross-package contract checks use `search_callers/search_callees` to verify callback coverage across package versions.

---

### DuckDB Deployment Modes

| | Single-file DuckDB | Sharded DuckDB (`ShardedIndex`) |
|---|---|---|
| **Setup** | One `QuackDB` repo; `migrate?: true` on first index | Multiple `QuackDB` repos, one per shard file; `ShardedIndex.new/1` wraps them |
| **Best for** | Local analysis, single project, CI | Large Hex corpora, parallel shard builds, distributed fan-out |
| **Fan-out** | N/A | `Exograph.ShardedIndex` fans out queries to every shard and merges in memory |
| **Indexing** | `mix exograph.index` / `Exograph.index/2` | `--duckdb-shards N` + `--shard-dir` + `--manifest-path` on `mix exograph.index.hex` |
| **Concurrent writes** | Single writer per shard file | One writer per shard file; shards are independent |
| **Recovery** | N/A | `--manifest-path` enables resume-after-interruption |
| **When to pick** | Default for all single-machine use | Hex.pm corpus indexing at scale |

---

### Installation

```elixir
# mix.exs
def deps do
  [
    {:exograph, "~> 0.9"},                          # pulls quackdb transitively
    {:reach, "~> 2.2", optional: true}              # only if you need call graph or smell audits
  ]
end
```

---

### Indexing (building the index)

```elixir
# In-process — single source tree, DuckDB default
{:ok, index} =
  Exograph.index("lib",
    repo: MyApp.QuackDBRepo,     # Ecto repo module backed by QuackDB
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

# Managed shard directory + recovery mode (0.8.1+)
mix exograph.index.hex --mode latest --duckdb-shards 4 \
  --shard-dir /tmp/hex_shards \
  --duckdb-recovery-mode no_wal_writes \
  --manifest-path hex_index.json
```

Key flags for sharded DuckDB indexing:
- `--shard-dir` — directory for managed DuckDB shard files
- `--duckdb-recovery-mode` — `no_wal_writes` disables WAL for rebuildable/CI indexes
- `--manifest-path` — ETF manifest enabling resume-after-interruption

**Reach source-smell audit** (requires `reach` dep; added 0.9.0):
```bash
mix exograph.reach.audit --prefix myindex
```

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

### Reach Source-Smell Audit (`Exograph.Reach.SourceSmellAudit`)

Added in 0.9.0. Runs configurable structural smell scans across the indexed corpus using Reach pattern modules.

```elixir
# Load pattern metadata from Reach smell modules
patterns = Exograph.Reach.SourceSmellAudit.load_patterns!(MySmells.UnguardedRaise)

# Scan an index (standard or sharded) — opts control concurrency and candidate selection
{:ok, results} =
  Exograph.Reach.SourceSmellAudit.scan(index, [MySmells.UnguardedRaise],
    limit: 100,                   # max findings (default: 100)
    verify_concurrency: 4,        # parallel verification workers (default: min(schedulers, 8))
    candidate_mode: :anchor       # :anchor (default) or :exact
  )

# File-local check modules
{:ok, results} = Exograph.Reach.SourceSmellAudit.scan_file_checks(index, [MyFileCheck])

# Pre-loaded patterns (avoids re-loading per call)
{:ok, results} = Exograph.Reach.SourceSmellAudit.scan_patterns(index, patterns)
```

Mix task equivalent: `mix exograph.reach.audit --prefix myindex`.

Each `Result.t()` carries a list of `Finding.t()` with matched range, matched AST fingerprint, and source location. Findings are deduplicated by matched range or fingerprint (0.9.11) so overlapping expression fragments don't inflate reports.

---

### Web UI

```bash
mix exograph.web --prefix myindex --port 4200
```

- Monaco editor with Elixir syntax highlighting and autocompletion
- Structural, text, and regex search modes; `POST /api/search` accepts structural predicate shorthand (e.g. `contains(f, def handle_event(_, _, _))`) (0.9.0)
- Results grouped by package with code previews and Hex.pm links; URL-persisted pagination
- Live progress dashboard at `/progress` during `mix exograph.index.hex --web`
- Query telemetry with slow-query warnings (0.9.0)

**JSON API** (rate-limited 60 req/min, cursor pagination):
```
GET  /api/health    — release, runtime, and index metadata; deployment readiness (0.9.0)
POST /api/search    — structural / text / regex search
POST /api/query     — DSL query execution
GET  /api/packages  — list indexed packages
GET  /api/stats     — index statistics; includes poisoned_structural_names counter (0.9.5)
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

**Reach source-smell audit across a sharded Hex corpus:**
```elixir
{:ok, results} =
  Exograph.Reach.SourceSmellAudit.scan(sharded_index, [MyApp.Smells.UnsafeAtom],
    limit: 500,
    verify_concurrency: 8
  )

Enum.flat_map(results, & &1.findings)
|> Enum.sort_by(& &1.file)
```

---

### Module Map

| Module | Role |
|--------|------|
| `Exograph` | Primary API: `index/2`, `search/3`, `search_text/3`, `all/3`, `search_callers/3`, `search_callees/3` |
| `Exograph.DSL` | Query builder: `from/2`, `matches/2`, `contains/2`, `prefix_search/2`, `assoc/2` |
| `Exograph.Index` | Runtime handle keeping fragment store + inverted index + tree store together |
| `Exograph.ShardedIndex` | Fan-out wrapper over multiple `Index.t()` shards; same query API |
| `Exograph.Reach.SourceSmellAudit` | Reach-backed smell scanner: `scan/3`, `scan_file_checks/3`, `scan_patterns/3`, `load_patterns!/1` (0.9.0) |
| `Exograph.Fragment` | Searchable code unit (function body, clause, expression) |
| `Exograph.Definition` | Syntactic definition extracted from source |
| `Exograph.Reference` | Syntactic reference extracted from source |
| `Exograph.CallEdge` | Reach-derived call graph edge (requires `reach` dep) |
| `Exograph.GraphNode` | Graph node type for call-graph queries (0.9.0) |
| `Exograph.ShardTelemetry` | Per-shard query telemetry (0.9.0) |
| `Exograph.DuckDB` | Schema helpers for DuckDB backend |

---

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `EXOGRAPH_GENERATED_MIN_MASS` | built-in | Generated-source fragment threshold; increase to skip macro-expanded noise during Hex re-index (0.9.9) |
| `EXOGRAPH_INDEX_TIMEOUT` | built-in | Per-package Broadway job timeout for production release re-indexes (0.9.8) |
| `EXOGRAPH_MAX_INDEX_ERRORS` | `0` | Max package indexing errors before refusing to publish a staged Hex index; `0` = fail-safe (0.9.5) |
| `EXOGRAPH_QUACKDB_RECEIVE_TIMEOUT` | `120s` | QuackDB shard transport receive timeout (0.9.5) |
| `EXOGRAPH_QUACKDB_CONNECT_TIMEOUT` | `120s` | QuackDB shard transport connect timeout (0.9.5) |

---

### Common Issues

| Problem | Cause | Fix |
|---------|-------|-----|
| `matches/2` returns 0 hits on valid code | Pattern syntax error — ExAST is strict | Test the pattern with `ExAST.pattern/1` first; use `_` as wildcard for any subterm |
| `search(index, "Repo.get!(_, _)")` returns no hits on a Hex corpus index | `poisoned_structural_names` bug (pre-0.9.5) — unknown identifiers silently replaced with placeholder atom | Upgrade to 0.9.5+; re-index; confirm `/api/stats` → `poisoned_structural_names == 0` |
| `search_callers/2` returns empty but Reach finds edges | Reach dep not added or `Exograph.Extractor.Reach` not run during index | Add `{:reach, "~> 2.2"}` and re-index with `migrate?: true` |
| Sharded index fanout OOM on very large corpora | All shard results merged in memory | Limit with `opts: [limit: N]` on `Exograph.all/3`; paginate via cursor API |
| DuckDB concurrent write error | Two indexing processes on same shard file | Use separate `--prefix` per indexing run; merge via `ShardedIndex` at query time |
| `fragment_terms` lookups empty on fresh shard | Deferred `fragment_terms` not materialized before publish (pre-0.9.2/0.9.3) | Upgrade to 0.9.3+; re-index with `--manifest-path` and let finalization complete |
| `mix exograph.index.hex` stalls and doesn't resume | Manifest path not set | Pass `--manifest-path hex_index.json` (and `--shard-dir` when using managed shards) |
| Production publish rejected with error count check | `EXOGRAPH_MAX_INDEX_ERRORS` is `0` and some packages failed to index | Investigate failed packages; or set `EXOGRAPH_MAX_INDEX_ERRORS=N` to allow a bounded count |

---

### DO NOT

1. Use `Exograph.search/3` for semantic flow analysis — it's structural only; for taint/data-flow use Reach.
2. Forget `migrate?: true` on first index — the schema tables won't exist and queries will error.
3. Run two concurrent `mix exograph.index.hex` processes against the same DuckDB shard file (single-writer constraint).
4. Use `Exograph.all/3` without a `limit` in the opts on large corpora — result sets can be very large.
5. Invoke the Hex.pm indexer (`--mode all`) without planning storage — every version of every package is large.
6. Treat `search_text/3` regex as structural — it matches source text, not AST shape; a regex matching `def foo` also hits comments and strings.
7. Configure a Postgres-backed Ecto repo for Exograph — Postgres storage was removed in 0.9.0; any attempt will fail at runtime with missing schema errors.
8. Ship a re-indexed Hex corpus without checking `/api/stats` → `poisoned_structural_names == 0`; a poisoned index returns zero results for common patterns without any error.

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
{:exograph, "~> 0.9"},
{:quackdb, "~> 0.5"}          # pulled transitively for DuckDB backend

# Optional: call graph indexing and source-smell audits
{:reach, "~> 2.2", optional: true}
```

Transitive runtime deps (selected): `ex_ast ~> 0.12` (0.12.9 as of exograph 0.9.10), `ex_dna ~> 1.5`, `broadway ~> 1.2`, `ecto_sql ~> 3.13`.
Web UI optional deps (auto-detected): `phoenix ~> 1.8`, `phoenix_live_view ~> 1.1`, `bandit ~> 1.5`, `makeup_elixir ~> 1.0` — only needed if running `mix exograph.web`.
