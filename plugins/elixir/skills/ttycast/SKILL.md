---
name: ttycast
description: ttycast — seekable compressed terminal session recordings for Elixir. Use when recording terminal sessions to a seekable binary format, redacting input, snapshot-seeking, exporting to asciinema, or recovering from crashes. Covers the container format, Writer/Recorder API, input policy, snapshot seeking, and mix tasks.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/ttycast.md — do not edit manually -->

## TTYCast — Seekable Compressed Terminal Recordings for BEAM

Records terminal sessions into `.ttycast` files with independently compressed chunks, Ghostty PTY keyframes, timestamp seeking, and redacted-by-default input — more than a plain log file.

**Min version: `{:ttycast, "~> 0.1.0"}`.** Requires Elixir ~> 1.19 and `{:ghostty, "~> 0.4.9"}` (real PTY capture). Runtime dep: `{:jason, "~> 1.4"}` for asciinema export.

**Input is `:redacted` by default** — `TTYCast.Writer.input/2` records byte counts, not bytes. Opt into `:raw` only for disposable/debug sessions.

**Seekable via independently compressed chunks.** Each chunk embeds a Ghostty keyframe so `snapshot!/2` seeks without decompressing the entire file.

**Recovery-safe.** Writers maintain a `<recording>.live.idx` sidecar; crash-survived files can be re-opened through the sidecar or rebuilt with `mix ttycast.reindex`.

**Caveat:** `TTYCast.Interactive.record/2` (current-terminal recorder) docs are sparse — treat as experimental.

**Does NOT cover:** network streaming, multi-process fan-in recording, or asciinema playback in the browser (export to `.cast` then use asciinema player separately).

---

### Binary Container Format (FORMAT.md)

```text
magic               "TTYCAST\0"
version             u16
header_len          u32
header_etf          ETF map (width, height, codec, input_policy, metadata, chunk thresholds)
chunk*              (see below)
trailer_magic       "TTYCAST_INDEX\0"
trailer_len         u64
trailer_etf         ETF index map
footer_magic        "TTYCAST_FOOTER\0"
trailer_offset      u64          ← one seek from EOF lands here
```

All integers unsigned big-endian; payload is Erlang External Term Format.

**Chunk layout:**
```text
compressed_len      u64
uncompressed_len    u64
start_t_us          u64
end_t_us            u64
event_count         u32
payload_gzip        compressed_len bytes
```

Uncompressed payload is an ETF map:
```elixir
%{
  seq: non_neg_integer(),
  start_t_us: non_neg_integer(),
  end_t_us: non_neg_integer(),
  event_count: non_neg_integer(),
  # nil when chunk has no keyframe
  keyframe: %{format: :ghostty_snapshot, t_us: integer(), plain: binary(), vt: binary()} | nil,
  events: [event]
}
```

**Event types:**
```elixir
{:output,          t_us, bytes}
{:input,           t_us, bytes}           # only when input_policy: :raw
{:input_redacted,  t_us, byte_count}      # default policy
{:resize,          t_us, cols, rows}
{:marker,          t_us, name, metadata}  # name: atom, metadata: map
{:event,           t_us, stream, payload} # app-defined custom stream
```

---

### Writing (scoped lifecycle)

```elixir
# Preferred — writer pid handed to fun, closed on return or exception
TTYCast.write("/tmp/demo.ttycast", [width: 120, height: 40], fn writer ->
  TTYCast.Writer.write(writer, "$ mix test\r\n")           # terminal output bytes
  TTYCast.Writer.marker(writer, :checkpoint, %{label: "suite start"})
  TTYCast.Writer.event(writer, :ci, %{suite: "unit", result: :pass})
  TTYCast.Writer.resize(writer, 200, 50)                   # terminal resize event
end)

# Manual lifecycle
{:ok, writer} = TTYCast.start_writer(
  path: "/tmp/demo.ttycast",
  width: 120, height: 40,
  input_policy: :none   # :redacted (default) | :raw | :none
)
TTYCast.Writer.write(writer, "hello\r\n")
TTYCast.Writer.flush(writer)   # force chunk to disk (normally automatic)
TTYCast.Writer.close(writer)   # flush + write trailer/footer + stop GenServer

# Stream integration — pipe iodata into a recording
TTYCast.write("/tmp/log.ttycast", [width: 120, height: 40], fn writer ->
  File.stream!("app.log") |> Enum.into(TTYCast.into(writer))
end)
```

**Writer.Writer specs:**
| Function | Spec | Notes |
|---|---|---|
| `write/2` | `(pid, IO.chardata) :: :ok` | Terminal output bytes |
| `input/2` | `(pid, IO.chardata) :: :ok` | Respects `input_policy` |
| `input_redacted/2` | `(pid, non_neg_integer) :: :ok` | Explicit byte-count record |
| `output/2` | `(pid, IO.chardata) :: :ok` | Alias for `write/2` |
| `resize/3` | `(pid, cols, rows) :: :ok` | Log dimension change |
| `event/3` | `(pid, atom, term) :: :ok` | Custom stream event |
| `marker/3` | `(pid, atom, map) :: :ok` | Named semantic marker |
| `flush/1` | `(pid) :: :ok` | Force chunk flush |
| `close/1` | `(pid) :: :ok` | Flush + trailer + stop |

---

### Recording Commands (PTY)

```elixir
# Non-interactive — capture command stdout/stderr under PTY
{:ok, %{status: 0, path: "demo.ttycast", bytes: 4321}} =
  TTYCast.record(["mix", "test", "--color"], path: "/tmp/mix-test.ttycast", width: 120, height: 40)

# Three-arg form (cmd + args separately)
TTYCast.record("sh", ["-lc", "echo hello"], path: "/tmp/hello.ttycast")

# Interactive — forward stdin/stdout of current terminal (blocks until child exits)
TTYCast.record_interactive(["bash"], path: "/tmp/shell.ttycast")
```

From the CLI:
```bash
mix ttycast.record --output /tmp/demo.ttycast -- sh -lc 'echo hello'
mix ttycast.rec --output /tmp/shell.ttycast -- bash          # interactive
mix ttycast.rec --output /tmp/shell.ttycast --input raw -- bash  # capture raw input
```

---

### Reading and Seeking

```elixir
cast = TTYCast.open!("/tmp/demo.ttycast")        # raises on error; lazy — no chunk decode
# or
{:ok, cast} = TTYCast.open("/tmp/demo.ttycast")

# Cast struct: %TTYCast.Cast{header: map(), index: map(), path: Path.t()}

TTYCast.info(cast)
# => %{chunks: 3, events: 1420, duration_ms: 12300, width: 120, height: 40, ...}

# Ghostty snapshot at timestamp — reads nearest keyframe chunk + forward deltas only
TTYCast.snapshot!(cast, time_ms: 5_000)   # => %{plain: binary(), vt: binary(), ...}
{:ok, snap} = TTYCast.snapshot(cast, time_ms: 5_000)

# Lazy event stream (chunk-at-a-time decompression)
TTYCast.stream(cast) |> Enum.each(&IO.inspect/1)

# Eager list
TTYCast.events(cast)

# Single chunk by index
{:ok, chunk} = TTYCast.read_chunk(cast, 0)   # => %{seq:, events:, keyframe:, ...}
TTYCast.read_chunk!(cast, 0)                   # raises variant

# Text search across snapshots
TTYCast.find(cast, "error")                   # string match
TTYCast.find(cast, ~r/tests? failed/i)        # regex
```

---

### Export / Import

```elixir
# Export to asciinema v2 JSONL (for browser players, sharing)
TTYCast.export(cast, :asciinema, "/tmp/demo.cast")
TTYCast.export_asciinema(cast, "/tmp/demo.cast")   # direct alias

# Import from asciinema v2 JSONL → .ttycast
TTYCast.import("/tmp/demo.cast", :asciinema, "/tmp/imported.ttycast")
TTYCast.import_asciinema("/tmp/demo.cast", "/tmp/imported.ttycast")
```

From the CLI:
```bash
mix ttycast.snapshot /tmp/demo.ttycast          # print snapshot at end
mix ttycast.snapshot /tmp/demo.ttycast --at 5000  # at 5 000 ms
mix ttycast.find /tmp/demo.ttycast "error"
mix ttycast.info /tmp/demo.ttycast
```

---

### Input Policy

| Policy | `Writer.input/2` behavior | Use when |
|---|---|---|
| `:redacted` (default) | Records `{:input_redacted, t_us, byte_count}` | Always — safe default |
| `:raw` | Records `{:input, t_us, bytes}` | Disposable/debug sessions only |
| `:none` | Drops event entirely | Fully automated pipelines |

Set at writer start — cannot change mid-recording:
```elixir
TTYCast.start_writer(path: p, width: 80, height: 24, input_policy: :raw)
```

---

### Recovery

Writers maintain `<recording>.live.idx` sidecar after each chunk flush. If the process crashes before writing the trailer/footer:

1. `TTYCast.open!/1` falls back to the live index automatically when the sidecar exists.
2. If the sidecar is missing but chunks are intact, rebuild:

```bash
mix ttycast.reindex /tmp/demo.ttycast
```
```elixir
TTYCast.reindex("/tmp/demo.ttycast")   # same, from code
```

---

### Mix Task Reference

| Task | Purpose |
|---|---|
| `mix ttycast.record` | Record non-interactive command under PTY |
| `mix ttycast.rec` | Record interactive command in current terminal |
| `mix ttycast.info` | Print header metadata |
| `mix ttycast.snapshot` | Extract and print terminal snapshot |
| `mix ttycast.find` | Search text across recording snapshots |
| `mix ttycast.reindex` | Rebuild trailer/footer from intact chunks |
| `mix ttycast.bench` | Compare `.ttycast` vs asciinema sizes and timings |

---

### Common Issues

| Problem | Cause | Fix |
|---|---|---|
| `open!/1` raises on crash-survived file | Trailer/footer not written | Run `mix ttycast.reindex` or rely on `.live.idx` sidecar |
| `snapshot!/2` slow on long recordings | Too few keyframes | Decrease `:keyframe_interval_ms` in writer opts |
| Input events missing from stream | Default `:redacted` policy | Start writer with `input_policy: :raw` (disposable sessions only) |
| `TTYCast.record/2` hangs | Command awaits TTY input | Use `TTYCast.record_interactive/2` for interactive commands |
| Export produces empty `.cast` | Input-only recording | `.ttycast` must contain `:output` events; `:input_redacted` events are not exported |

---

### DO NOT

1. Pass `input_policy: :raw` in production — raw input captures passwords and secrets.
2. Use `TTYCast.events/1` on large recordings (loads all chunks eagerly) — prefer `TTYCast.stream/1`.
3. Forget `TTYCast.Writer.close/1` in the manual lifecycle — omitting it skips the trailer/footer (file unreadable without the live index).
4. Share `.ttycast` files recorded with `:raw` policy without scrubbing — they contain raw keystrokes.
5. Depend on chunk index stability across `reindex` runs — indices are internal; use timestamps for seeking.

---

### Recipes

**CI artifact — record a mix task:**
```elixir
# In a CI Mix task or test helper
{:ok, _} = TTYCast.record(
  ["mix", "test", "--color", "--formatter", "ExUnit.CLIFormatter"],
  path: "artifacts/#{DateTime.utc_now() |> DateTime.to_unix()}.ttycast",
  width: 200, height: 50
)
```

**Supervised writer in an application:**
```elixir
defmodule MyApp.SessionRecorder do
  use GenServer

  def start_link(opts) do
    path = Keyword.fetch!(opts, :path)
    {:ok, writer} = TTYCast.start_writer(path: path, width: 120, height: 40)
    GenServer.start_link(__MODULE__, writer, name: __MODULE__)
  end

  def record_output(bytes), do: GenServer.cast(__MODULE__, {:output, bytes})
  def record_marker(name, meta \\ %{}), do: GenServer.cast(__MODULE__, {:marker, name, meta})

  def init(writer), do: {:ok, writer}

  def handle_cast({:output, bytes}, writer) do
    TTYCast.Writer.write(writer, bytes)
    {:noreply, writer}
  end

  def handle_cast({:marker, name, meta}, writer) do
    TTYCast.Writer.marker(writer, name, meta)
    {:noreply, writer}
  end

  def terminate(_reason, writer), do: TTYCast.Writer.close(writer)
end
```

**Seek to a named marker:**
```elixir
cast = TTYCast.open!("demo.ttycast")
marker_t = TTYCast.stream(cast)
  |> Enum.find_value(fn
    {:marker, t_us, :checkpoint, _meta} -> t_us
    _ -> nil
  end)
TTYCast.snapshot!(cast, time_ms: div(marker_t, 1_000))
```

---

**Portfolio fit:** niche but useful for CI artifact generation — recording `mix test` runs or IEx sessions in a supervised app produces seekable `.ttycast` files rather than flat logs, enabling snapshot diffing and timestamp-anchored event correlation.

---

### Dependencies

```elixir
# mix.exs — runtime
{:ttycast, "~> 0.1.0"},
{:jason, "~> 1.4"},        # pulled transitively by ttycast; needed for asciinema export
{:ghostty, "~> 0.4.9"}    # pulled transitively; real PTY recording
```

Runtime deps (`jason`, `ghostty`) are pulled by ttycast itself — add them explicitly only if you pin versions.
