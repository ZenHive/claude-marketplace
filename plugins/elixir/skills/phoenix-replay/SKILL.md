---
name: phoenix-replay
description: phoenix_replay — server-side LiveView session recording and replay. Use when recording and replaying LiveView sessions for debugging, wiring the Recorder hook, choosing File/Ecto storage, sanitizing recordings, or mounting the replay dashboard. Note: it strips :streams and :uploads and misses LiveComponent-private assigns. Covers the Recorder, Store API, Sanitizer behaviour, and dashboard router macro.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/phoenix-replay.md — do not edit manually -->

## PhoenixReplay — Server-Side LiveView Session Recording and Replay

Records LiveView state transitions (assigns, events, navigation) on the server and replays them through a built-in dashboard — no client-side JS recording library, no DOM snapshots.

**Min version: `{:phoenix_replay, "~> 0.2"}`.** Requires `phoenix_live_view ~> 1.0` and `jason ~> 1.0`. Ecto backend additionally needs `ecto_sql` in the host app.

**Recording is assign-delta based:** 30-second active sessions produce ~400 events / ~8 KB (ETF + gzip). Events are appended via direct ETS writes — no GenServer round-trip on the hot path. Recordings auto-finalize when the LiveView process exits.

**Idle sessions are silently discarded:** recordings with no `handle_event` calls and at most one `handle_params` are dropped at finalization — only sessions with real user interaction are persisted.

**Two storage backends:** `PhoenixReplay.Storage.File` (default) and `PhoenixReplay.Storage.Ecto`. Both support `:etf` (fast, type-preserving, default) and `:json` (portable but lossy for atoms, tuples, structs).

**Caveat:** replay reconstructs **root LiveView assigns only**. Stateful `LiveComponent` state, `Phoenix.LiveView.Stream`s, file uploads, client-only JS state, and `push_event`/`JS.push` effects are not captured. Replayed output may differ from what the browser actually rendered. See "HARD LIMITATION" below.

**Does NOT cover:** browser DOM state, JS-driven animations, real-time PubSub subscriptions, or anything managed outside assigns.

### HARD LIMITATION — Root Assigns Only

This is the critical design boundary. `PhoenixReplay.Sanitizer` explicitly strips `:uploads` and `:streams` from assigns before recording (see `@internal_keys` in `sanitizer.ex`). Delta recording also only tracks `socket.assigns.__changed__` — component-private assigns are invisible.

**Impact on tapakly and portfolio_hub:**
- tapakly has 4 upload-heavy LiveViews — upload state, progress assigns, and `allow_upload` configs are stripped; replays of these sessions will be incomplete.
- portfolio_hub has 5 streams across 9 LiveViews — streamed item assigns are not recorded; the replayed view will be empty or partial where streams populate content.

PhoenixReplay is most useful for root-assign-only views (forms, wizards, status dashboards with no streams/uploads) — for complex LiveViews in these apps, it covers only the non-stream, non-upload portion of the session.

### Setup

**1. Add to `mix.exs`:**
```elixir
{:phoenix_replay, "~> 0.2"}
```

**2. Attach to a live_session (preferred):**
```elixir
# router.ex — hooks all LiveViews in the session
live_session :default, on_mount: [PhoenixReplay.Recorder] do
  live "/dashboard", DashboardLive
  live "/settings", SettingsLive
end
```

**3. Or attach manually in mount (per-view opt-in):**
```elixir
def mount(params, session, socket) do
  # pass params + session so they appear in the recording
  {:ok, PhoenixReplay.Recorder.attach(socket, params, session)}
end
```

Recording only runs on connected sockets — `attach/3` is a no-op on the static render.

**4. Mount the dashboard:**
```elixir
# router.ex
import PhoenixReplay.Router

scope "/" do
  pipe_through [:browser, :require_admin]   # always gate behind auth
  phoenix_replay "/replay"
end
```

This mounts:
- `GET /replay/player.js` — bundled replay player JS asset
- `GET /replay/` — recording index (paginated, delete/clear controls)
- `GET /replay/:id` — replay view with scrubber, play/pause, speed controls
- `GET /replay/:id/frame` — isolated replay frame (used by the player)

### Configuration

```elixir
config :phoenix_replay,
  # File backend (default)
  storage: PhoenixReplay.Storage.File,
  storage_opts: [
    path: "priv/replay_recordings",
    format: :etf             # :etf (default) or :json
  ],

  # Hard cap on events per session (default 10_000)
  max_events: 10_000,

  # Custom sanitizer module (see § Sanitizer)
  sanitizer: MyApp.ReplaySanitizer,

  # Retention: drop recordings older than this many milliseconds
  max_recording_age_ms: 7 * 24 * 60 * 60 * 1000,

  # Retention: keep only the N most recent recordings
  max_recordings: 500,

  # Periodic cleanup interval (disabled by default)
  cleanup_interval_ms: 60 * 60 * 1000,

  # Authorization predicate (default: allow all)
  authorize: fn recording -> recording.view in [MyAppWeb.SafeLive] end
```

### Storage Backends

#### File backend (default)

```elixir
config :phoenix_replay,
  storage: PhoenixReplay.Storage.File,
  storage_opts: [path: "priv/replay_recordings", format: :etf]
```

One file per recording, written to `path`. No external deps.

#### Ecto backend

```elixir
config :phoenix_replay,
  storage: PhoenixReplay.Storage.Ecto,
  storage_opts: [repo: MyApp.Repo, format: :etf]
```

Requires `ecto_sql` in the host app. Create the table with:

```elixir
defmodule MyApp.Repo.Migrations.CreatePhoenixReplayRecordings do
  use Ecto.Migration

  def change do
    create table(:phoenix_replay_recordings, primary_key: false) do
      add :id, :string, primary_key: true
      add :view, :string, null: false
      add :connected_at, :bigint, null: false
      add :event_count, :integer, null: false, default: 0
      add :data, :binary, null: false   # gzip-compressed ETF or JSON blob

      timestamps(type: :utc_datetime)
    end
  end
end
```

`list_summaries/1` is implemented natively for the Ecto backend (reads only index columns, not the full blob) — fast listing without deserializing every recording.

| | File | Ecto |
|---|---|---|
| External deps | None | `ecto_sql` in host |
| Listing efficiency | Deserializes all blobs | Index-only query |
| Multi-node safe | No (local disk) | Yes |
| Migration required | No | Yes |

### Programmatic API (`PhoenixReplay.Store`)

```elixir
# List finalized recording summaries (fast — no blob deserialization with Ecto backend)
PhoenixReplay.Store.list_recording_summaries()
# => [%{id:, view:, url:, connected_at:, event_count:, duration_ms:, active?: false}, ...]

# List all finalized recordings (full structs, slow for large datasets)
PhoenixReplay.Store.list_recordings()

# Fetch a single recording by ID
PhoenixReplay.Store.get_recording(id)
# => {:ok, %PhoenixReplay.Recording{}} | :error

# Fetch an in-progress (active) recording snapshot from ETS
PhoenixReplay.Store.get_active(id)
# => {:ok, %PhoenixReplay.Recording{}} | :error

# List in-progress recordings (only those with user events)
PhoenixReplay.Store.list_active()

# Delete one recording
PhoenixReplay.Store.delete_recording(id)

# Nuke everything (useful in test teardown)
PhoenixReplay.Store.clear_all()

# Trigger retention cleanup immediately (else runs on cleanup_interval_ms)
PhoenixReplay.Store.cleanup()

# Finalize an active recording synchronously (normally auto on LV exit)
PhoenixReplay.Store.finalize(id)
```

### Recording Struct

```elixir
%PhoenixReplay.Recording{
  id: "base64-url-encoded-16-bytes",
  view: MyAppWeb.DashboardLive,
  url: "http://localhost:4000/dashboard",
  params: %{},                    # sanitized mount params
  session: %{},                   # sanitized session data
  connected_at: 1_718_000_000_000, # Unix ms
  events: [
    {0, :mount, %{assigns: %{...}}},
    {142, :event, %{name: "save", params: %{...}}},
    {143, :assigns, %{delta: %{form: ...}}},
    {501, :handle_params, %{url: "...", params: %{...}}},
    {600, :info, %{}},
    {601, :assigns, %{snapshot: %{...}}}  # full snapshot after concurrent events
  ]
}
```

**Event types:**

| Type | Payload | When recorded |
|---|---|---|
| `:mount` | `%{assigns: sanitized_assigns}` | Connected socket mount |
| `:event` | `%{name: event, params: map}` | Every `handle_event` call |
| `:handle_params` | `%{url: url, params: map}` | Navigation / `push_patch` |
| `:info` | `%{}` | Every `handle_info` call (no payload) |
| `:assigns` | `%{delta: map}` or `%{snapshot: map}` | After-render; snapshot used when multiple events fired between renders |

**Replaying assigns at a point in time:**

```elixir
# Accumulated assigns map at event index N (pure function, no side effects)
assigns = PhoenixReplay.Recording.accumulated_assigns(recording, index)
```

### Sanitizer

Default `PhoenixReplay.Sanitizer` drops:
- **Internal keys:** `:__changed__`, `:flash`, `:uploads`, `:streams`, `:_replay_id`, `:_replay_t0`
- **Sensitive keys:** `:_csrf_token`, `:csrf_token`, `:password`, `:password_confirmation`, `:user_token`, `:token`, `:secret`, `:current_password` (matched case-insensitively)
- **Ecto struct compaction:** strips `:types`, `:validations`, `:prepare`, `:repo`, `:repo_opts` from `Ecto.Changeset`; drops `:__meta__` from schema structs; strips runtime options from `Phoenix.HTML.Form`.

**Custom sanitizer:**

```elixir
defmodule MyApp.ReplaySanitizer do
  @behaviour PhoenixReplay.Sanitizer

  @impl true
  def sanitize_assigns(assigns) do
    # Call default first, then drop your app's sensitive fields
    assigns
    |> PhoenixReplay.Sanitizer.sanitize_assigns()
    |> Map.drop([:current_user, :subscription_token])
  end

  @impl true
  def sanitize_delta(changed, assigns) do
    PhoenixReplay.Sanitizer.sanitize_delta(changed, assigns)
    |> Map.drop([:current_user])
  end

  # Optional — falls back to sanitize_assigns/1 if not defined
  @impl true
  def sanitize_params(params), do: Map.drop(params, ["password"])
end
```

### Authorization

```elixir
config :phoenix_replay,
  authorize: fn recording ->
    # Return true to allow access, false to hide
    recording.view in [MyAppWeb.PublicDashboardLive]
  end
```

Authorization is checked on every `get_recording/1`, `list_recordings/0`, `list_recording_summaries/0`, and `get_active/1` call. Unauthorized recordings are filtered from list results and return `:error` on direct fetch.

### Testing

```elixir
# Disable cleanup between tests — call in setup
PhoenixReplay.Store.clear_all()

# Verify a recording was created after a live interaction
assert [summary] = PhoenixReplay.Store.list_recording_summaries()
assert summary.view == MyAppWeb.MyLive
assert summary.event_count > 0

# Inspect the recorded event timeline
{:ok, recording} = PhoenixReplay.Store.get_recording(summary.id)
event_types = Enum.map(recording.events, fn {_ms, type, _} -> type end)
assert :event in event_types

# Test accumulated assigns at a specific step
assigns = PhoenixReplay.Recording.accumulated_assigns(recording, 2)
assert assigns.step == :complete
```

Use the File backend in tests (default) with a temp path to avoid cross-test pollution:

```elixir
# config/test.exs
config :phoenix_replay,
  storage: PhoenixReplay.Storage.File,
  storage_opts: [path: "tmp/test_recordings"]
```

### Common Issues

| Problem | Cause | Fix |
|---|---|---|
| Recordings not appearing in dashboard | Idle sessions (no `handle_event`, ≤1 `handle_params`) are silently dropped | Interact with the view before checking |
| Replay looks blank / partial | Streams or upload assigns are stripped by sanitizer | Expected — see HARD LIMITATION |
| `list_summaries` slow | File backend deserializes all blobs for listing | Switch to Ecto backend for large recording sets |
| Sensitive data visible in replay | Custom assigns not covered by default sanitizer | Add custom `sanitizer` module |
| Dashboard accessible to all users | No auth pipeline on `phoenix_replay` scope | Always `pipe_through :require_admin` or equivalent |
| Storage init error at startup | Ecto backend but `ecto_sql` not in host deps | Add `{:ecto_sql, "~> 3.13"}` to `deps` |
| Old recordings never purged | `cleanup_interval_ms` not set | Set `cleanup_interval_ms` + `max_recordings` or `max_recording_age_ms` |

### DO NOT

1. Mount the dashboard without authentication — recordings may contain sanitized-but-still-sensitive assigns.
2. Use `:json` format if assigns contain atoms, tuples, or Ecto structs — JSON serialization is lossy for these types; use `:etf`.
3. Rely on replay accuracy for views with streams or uploads — those assigns are intentionally stripped.
4. Set `max_events` very high on high-traffic LiveViews — each event is an ETS insert; unbounded recording on chatty views will grow memory.
5. Call `Store.clear_all()` in production — it drops every persisted recording from the backend; it exists for tests.
6. Use `get_recording/1` in a tight loop for listing — use `list_recording_summaries/0` instead (avoids deserializing full blobs, especially critical with the File backend).

### Portfolio Fit

**LIMITED** — root-assigns-only replay cannot capture streams or uploads, which is exactly where your complex LiveViews live: tapakly has 4 upload views (upload progress/assigns stripped by the sanitizer) and portfolio_hub streams 5 of 9 LiveViews (stream assigns stripped). PhoenixReplay is useful for the simpler root-assign-only views in these apps (settings pages, wizard flows, non-streaming dashboards) but cannot faithfully replay the high-complexity surfaces.

### Dependencies

```elixir
# mix.exs
{:phoenix_replay, "~> 0.2"}

# Optional — only if using Ecto backend
{:ecto_sql, "~> 3.13"}
```

Runtime deps pulled in: `phoenix_live_view ~> 1.0`, `jason ~> 1.0`. Ecto (~> 3.13) is optional and only activated when `Code.ensure_loaded?(Ecto)` returns true.
