---
name: fsst
description: fsst — Fast Static Symbol Table string compression for Elixir via a Rustler NIF. Use when compressing many short strings with a trained symbol table, loading pre-built tables, or choosing between the Rust NIF and the pure-Elixir fallback. Covers train/compress/decompress, FSST.Table.from_symbols/1, backend selection, and error types.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/fsst.md — do not edit manually -->

## FSST — Fast Static Symbol Table String Compression

Shared-dictionary string compression optimized for database-style workloads: many short strings compressed with a single trained symbol table. Pure Elixir always available; optional Rustler NIF (`fsst-rs`) auto-selected when precompiled.

**Min version: `{:fsst, "~> 0.1"}`.** Pinning `"~> 0.1.2"` is safe; current release is **0.1.2** (May 26, 2026, MIT © Danila Poyarkov).
**Three-step lifecycle:** train table once on representative samples → compress many strings with that table → decompress with the same table.
**Wire format:** one-byte symbol codes; code `255` escapes raw bytes. Tables hold ≤ 255 symbols, each 1–8 bytes.
**Backend resolution:** `:auto` prefers `FSST.Rust` when the NIF loads; falls back to `FSST.Pure` silently. Always pure if Rustler is absent at compile time.

**Caveat:** compression ratio is workload-dependent — training samples must be representative of production data. Tables are not serializable across library versions without `FSST.Table.from_symbols/1`.

**Does NOT cover:** streaming compression, cross-table compatibility, general-purpose binary compression (use `:zlib` for that).

**Portfolio fit:** candidate for `ex_trader`'s `ethereum_logs` pipeline (42-char hex addresses repeat across thousands of log entries) or `quantex` JSONL keys — but only worthwhile at volume; measure with `mix run bench/fsst_bench.exs` before wiring in.

### Core API (`FSST`)

```elixir
# Happy path — bang variants raise ArgumentError on failure
table = FSST.train!(samples)                     # samples: [binary()]
compressed = FSST.compress!(table, input)        # input: binary()
original = FSST.decompress!(table, compressed)   # returns binary()

# Safe variants — use when input is untrusted or samples may be empty
with {:ok, table}      <- FSST.train(samples),
     {:ok, compressed} <- FSST.compress(table, input),
     {:ok, original}   <- FSST.decompress(table, compressed) do
  {:ok, original, compressed}
end
```

All six functions share the same optional `opts` keyword list (see Training Options).

### Training Options (pure backend only)

```elixir
FSST.train!(samples,
  backend: :pure,          # :auto (default) | :pure | :rust | module()
  max_symbol_size: 8,      # candidate symbol length ceiling (1–8, default 8)
  sample_bytes: 65_536     # bytes fed to trainer; :infinity = all provided bytes
)
```

`:sample_bytes` default is 65 536. For large corpora, the trainer uses `:counters` for bigram frequency (atomic, concurrent-write-safe); smaller corpora use a plain Map. Trainer emits ≤ 255 symbols sorted by gain `(symbol_length - 1) * frequency`.

### Backend Selection

```elixir
FSST.backend()                   # returns FSST.Pure or FSST.Rust per runtime state
FSST.backend(backend: :pure)     # force pure Elixir
FSST.backend(backend: :rust)     # force Rust — errors if NIF unavailable

# Pass backend: opt through to train/compress/decompress
table = FSST.train!(samples, backend: :pure)
# compress/decompress respect the table's stored backend unless overridden:
FSST.compress!(table, input, backend: :rust)   # override for this call only
```

| | `FSST.Pure` | `FSST.Rust` |
|---|---|---|
| Always available | yes | only when NIF loads |
| Training options (`:max_symbol_size`, `:sample_bytes`) | yes | ignored (uses `fsst-rs` defaults) |
| `table.native` | nil | opaque NIF resource |
| `available?/0` | always `true` | `Code.ensure_loaded?(FSST.Native)` probe |

### Rustler NIF — Installation

`{:rustler_precompiled, "~> 0.8"}` is a hard dep (always in mix.exs). `{:rustler, "~> 0.38"}` is **optional** — add it only if you want to compile from source.

```elixir
# mix.exs — precompiled path (no Rust toolchain needed)
{:fsst, "~> 0.1"}
# Rustler is pulled transitively via rustler_precompiled.
# NIF auto-loads from the precompiled checksum file (checksum-Elixir.FSST.Native.exs).

# Force source compilation (Rust toolchain required):
{:fsst, "~> 0.1"},
{:rustler, "~> 0.38", optional: true}
```

To disable the NIF entirely and always run pure Elixir, pass `backend: :pure` at every call site or set it as a default in your application config.

### FSST.Table — Pre-Built Tables

Use when the table is stored separately from the payload (e.g. columnar formats that ship the FSST dictionary once per column chunk):

```elixir
# Symbols provided in code order; code 255 is always the escape byte (not listed)
table = FSST.Table.from_symbols!(["hello", " world", "!"])
# <<0, 1, 2>> → "hello world!"
FSST.decompress!(table, <<0, 1, 255, ?!>>)   # 255 escapes raw byte '!'
# → "hello world!"

# Safe variant
{:ok, table} = FSST.Table.from_symbols(symbols)
```

Constraints enforced: each symbol 1–8 bytes; ≤ 255 symbols total. Returns `{:error, :too_many_symbols}` or `{:error, :invalid_symbol}` on violation.

`FSST.Table.from_symbols/1` always creates a **pure** backend table (`:backend` field = `FSST.Pure`) regardless of the Rust NIF state.

### Error Reference

| Reason | When | Recoverable? |
|---|---|---|
| `:invalid_sample` | `samples` contains a non-binary | yes — filter before training |
| `:invalid_input` | `input` is not a binary, or table struct is wrong type | yes — check types |
| `:invalid_symbol` | symbol in `from_symbols/1` is 0 bytes or > 8 bytes | yes — trim symbol list |
| `:too_many_symbols` | `from_symbols/1` given > 255 symbols | yes — slice to ≤ 255 |
| `:truncated_escape` | compressed payload ends with bare `255` byte | fatal — data corruption |
| `{:unknown_code, code}` | code in payload not in current table | fatal — table mismatch |
| `:backend_unavailable` | `:rust` forced but NIF not loaded | yes — fall back to `:pure` |

### Common Issues

| Problem | Cause | Fix |
|---|---|---|
| Poor compression ratio | Training samples don't match production strings | Use a random sample of actual data; increase `:sample_bytes` |
| Decompression returns `{:error, {:unknown_code, _}}` | Table used for decompression differs from compression | Persist and reload the exact same table; use `from_symbols/1` for wire format |
| `FSST.Rust` always falls back to Pure | Precompiled NIF checksum mismatch or arch not precompiled | Check `checksum-Elixir.FSST.Native.exs`; add `{:rustler, "~> 0.38"}` to compile from source |
| `ArgumentError` on `train!` with empty list | `[]` is valid Elixir but yields a zero-symbol table | Guard with `samples != []` before calling |
| Training slow on large corpus | `:sample_bytes` default 65 536 is low for high-cardinality keys | Pass `sample_bytes: :infinity` or a larger value |

### DO NOT

1. Reuse a pure-backend table with the Rust backend or vice versa — the compressed byte sequences are not interchangeable.
2. Deserialize a table by storing the `%FSST.Table{}` struct directly (via `:erlang.term_to_binary`) across library versions — the struct shape may change; use `from_symbols/1` with the symbol list instead.
3. Pass `backend: :rust` in production code without a fallback — if the NIF fails to load at deploy time, every call returns `{:error, :backend_unavailable}`.
4. Train on a single short string — the trainer needs repeated substrings to build a useful symbol table; a single sample produces near-zero compression.
5. Use FSST for general binary data (images, already-compressed payloads) — it is designed for human-readable or structured text strings.

### Recipes

**Compress a column of Ethereum addresses:**
```elixir
# Train once on a representative batch
table = FSST.train!(address_sample, sample_bytes: :infinity)

# Compress each address; ratio depends on address diversity
compressed_addrs = Enum.map(all_addresses, &FSST.compress!(table, &1))

# Decompress on retrieval
original = FSST.decompress!(table, compressed_addr)
```

**Benchmark before committing:**
```bash
mix run bench/fsst_bench.exs   # ships in the repo; requires :benchee in dev deps
```

**Detect NIF at runtime:**
```elixir
if FSST.Rust.available?() do
  Logger.info("FSST Rust NIF active")
end
```

**Handle a pre-trained FSST dictionary from an external source:**
```elixir
# External format ships symbols as a list of binaries in code order
{:ok, table} = FSST.Table.from_symbols(external_symbol_list)
Enum.map(compressed_payloads, &FSST.decompress!(table, &1))
```

### Testing Notes

- Use `backend: :pure` in tests to avoid NIF dependency in CI — pure backend is deterministic and always available.
- The Rust backend may produce different symbol selections than Pure for the same samples; don't assert on the compressed bytes themselves, only on round-trip correctness.
- For table round-trip tests, extract symbols via `Tuple.to_list(table.symbols)` (or `table.symbols |> Tuple.to_list()`) and reconstruct with `from_symbols/1`.

### Dependencies

```elixir
# Runtime (always)
{:fsst, "~> 0.1"},
# rustler_precompiled is a transitive dep — no explicit declaration needed

# Optional: force NIF compilation from source (requires Rust toolchain)
{:rustler, "~> 0.38", optional: true}
```

Elixir `~> 1.19` required (declared in `mix.exs`). No OTP GenServers, supervisors, or runtime processes — fully stateless library.
