---
name: quackdb
description: quackdb — DuckDB DBConnection client and Ecto adapter for Elixir. Use when querying DuckDB from Elixir, running OLAP/analytics queries, doing native appends, writing Explorer dataframes, spatial/geo queries, or query profiling. Covers the DBConnection client, Ecto adapter plus analytics DSL, native append, and profiling.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/quackdb.md — do not edit manually -->

## QuackDB — DuckDB DBConnection + Ecto adapter for Elixir

OTP-supervised DuckDB via the Quack protocol: DBConnection client, Ecto adapter, native append APIs, Explorer dataframe writes, Geo/WKB spatial, and query profiling.

**Min version: `{:quackdb, "~> 0.5"}`.** Requires DuckDB 1.5.5+ with the `quack` extension. Managed binary auto-downloads on Linux/macOS; Windows support is incomplete.

**Experimental protocol.** QuackDB targets DuckDB's Quack protocol, which DuckDB itself marks experimental. Public APIs, result shapes, Ecto adapter behavior, and protocol coverage may change between releases.

**Optional integrations activate when packages are present:** `{:ecto_sql, "~> 3.13"}`, `{:explorer, "~> 0.11"}`, `{:geo, "~> 4.1"}`.

**Hex-published at v0.5.19.** Use `{:quackdb, "~> 0.5"}` — do NOT pin to 0.3.x (older readme snapshots show that).

**Caveat:** Unsupported vector/logical types raise at runtime. Ecto coverage is analytics-first; edge cases in OLTP-style operations are not guaranteed. QuackDB does not stage local files to remote servers.

**Does NOT cover:** PostgreSQL (use Ecto + postgrex), Ecto changesets or validations (Ecto side, unchanged), streaming from remote to local file storage, or Windows-managed binaries.

**Portfolio fit:** PARKED — no tick/candle OLAP pipeline exists yet (`market_maker` denormalizes aggregates into Postgres). Revisit if backtesting or time-series OLAP lands; QuackDB's `quantile_cont`, `series/1`, and Parquet/S3 scan are exactly the right tools for that surface.

---

### Supervised Setup (Managed Binary)

`QuackDB.Server.child_specs/1` generates both server and client child specs, auto-downloads the DuckDB binary with checksum verification, and injects a shared random token — nothing to wire manually.

As of v0.5.15, the server writes default boot SQL (including the generated token) to a temporary init file rather than embedding it in process arguments, so tokens no longer appear in `ps` output.

As of v0.5.14, `INSTALL quack` runs idempotently before `LOAD quack` — the extension installs itself on first boot even when using a stock DuckDB binary.

As of v0.5.18, the managed binary tracks DuckDB 1.5.4 (upgraded from 1.5.3).

As of v0.5.19, the managed binary tracks DuckDB 1.5.5 (upgraded from 1.5.4); Mint is bumped to 1.9.3, fixing an HTTP/1 response-smuggling issue via sign-tolerant chunk-size parsing.

```elixir
# application.ex
children =
  QuackDB.Server.child_specs(
    server: [
      name: MyApp.DuckDB,       # GenServer name for the managed process
      duckdb: :managed,          # download official binary; or path string
      endpoint: "quack:localhost:9494",
      database: "/data/analytics.duckdb",  # omit for :memory:
      boot_sql: ["LOAD spatial;"]          # extensions to load on start
    ],
    client: [
      name: MyApp.QuackDB,
      pool_size: System.schedulers_online()
    ]
  )

Supervisor.start_link(children, strategy: :one_for_one)
```

Server options of note: `:duckdb_options` (keyword args for DuckDB), `:settings` (per-session), `:global_settings` (global DuckDB params), `:attach_as` (attach a secondary DB as atom/string), `:recovery_mode` (`:no_wal_writes` or path), `:boot_sql` (startup SQL list).

Remote-only (no managed server):
```elixir
{:ok, conn} = QuackDB.start_link(
  uri: "http://[::1]:9494",
  token: "super_secret",
  receive_timeout: 30_000
)
```

---

### Querying

```elixir
# Parameterized query — positional ?
{:ok, result} = QuackDB.query(conn, "SELECT ? AS name, ? AS n", ["duck", 42])
result.rows      # [["duck", 42]]
result.columns   # ["name", "n"]
result.num_rows  # 1
result.command   # :select

# Bang variant raises on error
result = QuackDB.query!(conn, "SELECT current_date")

# Row maps
QuackDB.maps(conn, "SELECT 1 AS x, 2 AS y")
# {:ok, [%{"x" => 1, "y" => 2}]}

# Column-oriented — returns QuackDB.Columns (preserves order + metadata)
{:ok, %QuackDB.Columns{} = cols} = QuackDB.columnar(conn, "SELECT ...")

# Column-oriented — returns plain maps keyed by column name
{:ok, col_maps} = QuackDB.columns(conn, "SELECT ...")

# Streaming — lazy, backpressure-safe
QuackDB.stream(conn, "SELECT * FROM huge_table", [])
|> Stream.each(&process/1)
|> Stream.run()

# Column batches returning QuackDB.Columns structs (with metadata)
QuackDB.columnar_batches(conn, "SELECT ...", [])
|> Enum.each(&process_batch/1)

# Column batches returning plain maps (no metadata)
QuackDB.column_batches(conn, "SELECT ...", [])
|> Enum.each(&process_batch/1)
```

Result struct fields: `columns`, `rows`, `num_rows`, `command`, `connection_id`, `messages`, `metadata`. Results implement `Table.Reader` for Livebook.

---

### Prepared Statements

```elixir
# Prepare once, execute many
{:ok, stmt} = QuackDB.prepare(conn, "SELECT * FROM events WHERE category = ?")

# Prepare and execute in one call
{:ok, result} = QuackDB.prepare_execute(conn, "SELECT ? AS n", [42])

# Health check
:ok = QuackDB.ping(conn)
```

---

### Native Append (fast bulk inserts)

Bypasses SQL INSERT generation — use for bulk loads.

```elixir
# Row-oriented (list of keyword lists or maps)
QuackDB.insert_rows!(conn, "events", [
  [id: 1, name: "duck", tags: ["bird", "wetland"]],
  [id: 2, name: "goose", tags: ["bird", "loud"]]
])

# Column-oriented (parallel lists, same length required)
QuackDB.insert_columns!(conn, "measurements", [
  id: [1, 2, 3],
  temperature: [12.5, 13.0, 12.8]
])

# Streaming enumerable — batched internally
QuackDB.insert_stream(conn, "events", my_stream)

# Table.Reader compatible (e.g. CSV.decode!/2 result)
QuackDB.insert_table(conn, "staging", tabular_value)
```

Pass `:columns` option with explicit type specs for empty/nil-only columns where DuckDB can't infer the type.

---

### List Helpers (v0.5.17+)

`QuackDB.List` and `QuackDB.Ecto.List` provide helpers for working with DuckDB's native list type.

```elixir
# Pure list builders
QuackDB.List.append(list, element)   # appends element to a DuckDB list value
QuackDB.List.prepend(list, element)  # prepends element to a DuckDB list value

# Ecto query expressions (import QuackDB.Ecto.List)
import QuackDB.Ecto.List

from t in "tags",
  select: %{
    extended: append(t.values, "new_tag"),
    prefixed: prepend(t.values, "first_tag")
  }
```

---

### Explorer Dataframe Writes

Activated when `{:explorer, "~> 0.11"}` is in deps. Module is `QuackDB.Explorer`.

```elixir
alias Explorer.DataFrame

frame = DataFrame.new(id: [1, 2], name: ["duck", "goose"])
QuackDB.Explorer.insert_dataframe!(conn, "events", frame)   # columnar, efficient
```

---

### Ecto Adapter

```elixir
# config/config.exs
config :my_app, MyApp.AnalyticsRepo,
  adapter: Ecto.Adapters.QuackDB,
  uri: "http://localhost:9494",
  token: "secret"

defmodule MyApp.AnalyticsRepo do
  use Ecto.Repo, otp_app: :my_app, adapter: Ecto.Adapters.QuackDB
end
```

Supported Ecto operations: raw `Repo.query/3`, schema selects, `Repo.get!/2`, joins, filters, grouping, windows, CTEs, `Repo.insert/2`, `Repo.insert_all/3`, `RETURNING`, `ON CONFLICT DO NOTHING`, common `DO UPDATE` upserts. Migrations: create/drop/alter tables, columns, references, indexes, PKs, check constraints, renames.

As of v0.5.16, `{:array, :map}` columns (`JSON[]` in DuckDB) are supported with full round-trip dump/load through both the SQL and native append paths.

As of v0.5.19, adding a `null: false` column via `alter table` migrations no longer fails: the adapter splits DuckDB's unsupported inline `NOT NULL` constraint into a separate `ADD COLUMN` followed by `ALTER COLUMN ... SET NOT NULL`.

Import helpers:
```elixir
import QuackDB.Ecto           # pulls in all sub-modules below
```

Or selectively:
```elixir
import QuackDB.Ecto.Analytics   # quantile_cont, median, fsum, mode, ...
import QuackDB.Ecto.Series      # series/1 for date/timestamp generation
import QuackDB.Ecto.WindowFrames
import QuackDB.Ecto.Spatial     # ST_* wrappers (requires :geo)
import QuackDB.Ecto.FTS         # full-text search helpers
import QuackDB.Ecto.List        # append/2, prepend/2 (v0.5.17+)
```

#### Analytical Queries

```elixir
# Aggregate functions not in Ecto stdlib
from event in "events",
  group_by: event.category,
  select: %{
    category: event.category,
    p95: quantile_cont(event.duration_ms, 0.95),  # QuackDB.Ecto.Analytics
    median_dur: median(event.duration_ms),
    events: count()
  }

# Window function
from t in "trades",
  select: %{
    id: t.id,
    rolling_vol: over(stddev(t.price), partition_by: t.symbol,
                      order_by: t.ts, rows: {-20, 0})
  }
```

#### Date/Timestamp Series (gap-fill pattern)

```elixir
from day in series(Date.range(~D[2024-01-01], ~D[2024-01-31])),
  left_join: event in "events",
  on: event.occurred_on == day.value,
  group_by: day.value,
  select: %{day: day.value, events: count(event.id)}
```

#### Remote Source Scanning (no upload)

```elixir
alias QuackDB.Source

# Parquet from S3
source = Source.parquet("s3://bucket/events/*.parquet", hive_partitioning: true)

from event in source,
  where: event.category == "click",
  group_by: event.category,
  select: %{events: count()}

# Other formats
Source.csv("s3://bucket/data.csv", header: true)
Source.json("/data/events.json")
Source.xlsx("/data/report.xlsx")
Source.delta("s3://bucket/delta-table")
Source.iceberg("s3://bucket/iceberg-table")
Source.sample(source, percent: 10)     # USING SAMPLE subquery
```

---

### Spatial / Geo Queries

Requires `{:geo, "~> 4.1"}` and `LOAD spatial;` in `:boot_sql` (or `Repo.query!(repo, "LOAD spatial")`).

```elixir
import QuackDB.Ecto.Spatial

point = %Geo.Point{coordinates: {13.405, 52.52}, srid: nil}

from place in "places",
  where: intersects(place.geom, ^point) and distance(place.geom, ^point) < 1_000,
  select: %{id: place.id, name: place.name, wkt: as_text(place.geom)}
```

Spatial functions: `intersects/2`, `contains/2`, `distance/2`, `point/2`, `envelope/4`, `geom_from_wkb/1`, `geom_from_text/1`, `as_wkb/1`, `as_hex_wkb/1`, `as_text/1`, `as_geojson/1`.

---

### Query Profiling

```elixir
profile = QuackDB.Profile.analyze!(conn, "SELECT ...", [])
# Returns QuackDB.Profile struct with execution metrics (latency, CPU time, cardinality, memory)

QuackDB.Profile.slowest(profile, 5)     # top-5 operators by operator_timing
QuackDB.Profile.flatten(profile)        # operator rows list for tooling
QuackDB.Profile.report(profile)         # compact human text

QuackDB.Profile.explain!(conn, "SELECT ...")  # plan only, no execution
```

---

### Storage / Observability

```elixir
QuackDB.Storage.database_size!(conn)          # DB file size info
QuackDB.Storage.compression!(conn, "events")  # compression metrics by column
QuackDB.Storage.info!(conn, "events")         # storage segment details
QuackDB.Storage.checkpoint!(conn)             # flush WAL
QuackDB.Storage.force_checkpoint!(conn)       # wait for lock + flush
```

Telemetry events emitted: `[:quackdb, :query, :start | :stop]`, `[:quackdb, :append, :start | :stop]`, `[:quackdb, :fetch, :start | :stop]`.

---

### Error Handling

| Scenario | Return | Notes |
|----------|--------|-------|
| SQL error | `{:error, %QuackDB.Error{}}` | Recoverable — inspect message |
| Transaction conflict | `{:error, %QuackDB.Error{reason: :transaction_conflict}}` | Retriable as of v0.5.16 |
| Unsupported type | raises at encode/decode | Fatal per query; avoid the type |
| Connection timeout | `{:error, exception}` | Check `:receive_timeout` option |
| Managed binary download fail | startup crash | Check DuckDB version / checksum |
| Spatial query, extension not loaded | DuckDB error | Add `LOAD spatial` to `:boot_sql` |

### Common Issues

| Problem | Cause | Fix |
|---------|-------|-----|
| `quack extension not found` | DuckDB binary missing the extension | Upgrade to v0.5.14+ (auto-installs via `INSTALL quack`) or use `duckdb: :managed` |
| Type encode error on nil column | DuckDB can't infer type from nil list | Pass `:columns` type specs in `insert_columns/4` |
| Spatial functions undefined | `spatial` extension not loaded | Add `"LOAD spatial;"` to `:boot_sql` |
| Windows managed binary fails | Windows not yet supported | Provide DuckDB binary path explicitly |
| Ecto migration errors | Adapter is analytics-first | Stick to supported DDL; avoid OLTP edge cases |
| `Table.Reader` not available | Explorer not in deps | `{:explorer, "~> 0.11"}` for Livebook integration |
| Token visible in `ps` output | Older server version | Upgrade to v0.5.15+ (boot SQL written to temp init file) |
| JSON map array (`{:array, :map}`) dumps incorrectly | Bug in pre-0.5.16 versions | Upgrade to v0.5.16+ |
| `ALTER TABLE ... ADD COLUMN ... NOT NULL` fails | Pre-0.5.19: DuckDB doesn't support the inline constraint | Upgrade to v0.5.19+ (adapter splits into `ADD COLUMN` + `SET NOT NULL`) |

---

### DO NOT

1. Use QuackDB as a drop-in production Postgres replacement — the Quack protocol is experimental.
2. Pin to `"~> 0.3"` — the README snapshots on mirror sites are stale; 0.5.19 is current.
3. Call `LOAD spatial` inside queries at runtime without connection pooling awareness — load it in `:boot_sql`.
4. Expect Windows managed-binary support — provide the DuckDB path explicitly on Windows.
5. Use `insert_rows!` for very wide schemas with nil-only columns without `:columns` type specs — DuckDB cannot infer the type.
6. Treat `QuackDB.Profile.slowest/2` output as wall-clock — operator timings are engine-internal metrics.

---

### Dependencies

```elixir
# mix.exs
{:quackdb, "~> 0.5"},
# Optional — enable when packages are present:
{:ecto_sql, "~> 3.13"},    # Ecto adapter + migrations
{:explorer, "~> 0.11"},    # QuackDB.Explorer.insert_dataframe!/3
{:geo, "~> 4.1"}           # Geo struct encoding + QuackDB.Ecto.Spatial
```

DuckDB binary: `duckdb: :managed` downloads and verifies the official binary automatically (Linux/macOS). For custom installs set `duckdb: "/path/to/duckdb"`.
