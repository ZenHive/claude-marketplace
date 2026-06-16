---
name: systemdkit
description: systemdkit — typed systemd unit-file generation and D-Bus manager control for Elixir. Use when generating .service/.socket/.timer/.mount/.path/.target unit files programmatically, validating or parsing unit files, controlling units over D-Bus (start/stop/restart/enable/mask, transient units, job tracking), or replacing systemctl shell-outs and hand-written unit strings. Covers the typed builders, Systemd.Manager, transient services, and the SYSTEMD_INTEGRATION test gate.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/systemdkit.md — do not edit manually -->

## systemdkit — Typed systemd Unit Generation and D-Bus Control

Pure Elixir interface to systemd: build typed unit files, control the manager, track jobs — no `systemctl` shell-outs, no string templating.

**Min version: `{:systemdkit, "~> 0.1"}`.** Current stable: v0.1.3.
**Hex package is `systemdkit`; all public modules use the `Systemd.*` namespace.**
**Two APIs:** top-level `Systemd.*` for short-lived one-offs; `Systemd.Manager.*` for connection-reuse or job tracking.
**Linux-only at runtime.** Integration tests require Linux + systemd; gate them behind `SYSTEMD_INTEGRATION=1`.
**Portfolio fit:** replaces the `systemctl show` shell-outs + hand-built unit-file strings in `servernodes_agent` (`CommandExecutor`/`Services`) and the hand-written `reth.service`/`lighthouse.service` in `ethnode`.

**Caveat:** read-only D-Bus calls (list, inspect) often work unprivileged; mutating system units typically requires root or polkit rules. The library surfaces D-Bus errors directly — it does not retry through `sudo`. Transient units (`start_transient_unit`) are the escape hatch for ephemeral jobs that shouldn't live on disk.

**Does NOT cover:** socket activation wiring, journal log streaming, cgroup introspection, or multi-host remote SSH execution (generate + copy the file manually for remote hosts).

---

### Unit File Generation (`Systemd.UnitFile`)

Six typed builders — one per unit type. Each takes section keywords and returns `t()`.

```elixir
# Build a hardened service unit (replacing hand-written reth.service / lighthouse.service)
unit_file =
  Systemd.UnitFile.service(
    unit: [
      description: "Reth execution client",
      after: "network.target"
    ],
    service: [
      type: :exec,
      user: "ethereum",
      working_directory: "/opt/reth",
      exec_start: "/usr/local/bin/reth node --chain mainnet --datadir /data/reth",
      restart: "on-failure",
      restart_sec: 5,
      timeout_stop_sec: 30,
      limit_nofile: 1_048_576,
      memory_max: "16G",
      tasks_max: 512,
      no_new_privileges: true,
      protect_system: :strict,
      protect_home: "read-only",
      cpu_accounting: true
    ],
    install: [wanted_by: "multi-user.target"]
  )

:ok = Systemd.UnitFile.validate(unit_file, :service)   # fails fast — call before writing to disk
text = Systemd.UnitFile.to_string(unit_file)            # render to string; write with File.write!/2

# Template units (Xamal-style blue/green, port = instance id)
# %i expands to the instance specifier: my_app@4000.service → %i = "4000"
Systemd.UnitFile.service(
  unit: [description: "my_app (%i)", after: "network.target"],
  service: [
    environment: ["PORT=%i", "RELEASE_NODE=my_app_%i"],
    exec_start: "/opt/my-app/current/bin/my_app start",
    environment_file: "-/opt/my-app/env/app.env",   # leading dash: ignore missing file
    restart: "on-failure"
  ],
  install: [wanted_by: "multi-user.target"]
)

# Timer unit
Systemd.UnitFile.timer(
  unit: [description: "Nightly snapshot"],
  timer: [on_calendar: "daily", persistent: true],
  install: [wanted_by: "timers.target"]
)

# Socket unit
Systemd.UnitFile.socket(
  unit: [description: "API socket"],
  socket: [listen_stream: "/run/myapp.sock", socket_user: "deploy"],
  install: [wanted_by: "sockets.target"]
)
```

**Parsing existing unit files (loss-aware — preserves comments, blanks, duplicate directives, source spans):**

```elixir
{:ok, uf} = Systemd.UnitFile.parse(File.read!("/etc/systemd/system/reth.service"))
uf = Systemd.UnitFile.parse!("[Service]\nExecStart=/bin/reth\n")

# Read all values for a repeated directive (ExecStart can appear multiple times)
values = Systemd.UnitFile.get_all(uf, "Service", "ExecStart")

# Mutate parsed units
uf = Systemd.UnitFile.put(uf, "Service", "MemoryMax", "32G")    # replace all
uf = Systemd.UnitFile.append(uf, "Service", "ExecStart", "/bin/reth --extra")  # add
uf = Systemd.UnitFile.delete(uf, "Service", "MemorySwapMax")    # remove

# Semantic comparison (ignores comments, ordering, blank lines)
Systemd.UnitFile.equivalent?(uf_old, uf_new)
Systemd.UnitFile.normalize(uf)    # returns map of {section, name} → [value]
```

**UnitFile builder reference:**

| Builder | Unit type | Key section keys |
|---------|-----------|-----------------|
| `service/1` | `.service` | `type`, `exec_start`, `restart`, `user`, `memory_max`, `protect_system` |
| `socket/1` | `.socket` | `listen_stream`, `listen_datagram`, `socket_user`, `socket_mode` |
| `timer/1` | `.timer` | `on_calendar`, `on_boot_sec`, `on_active_sec`, `persistent` |
| `mount/1` | `.mount` | `what`, `where`, `type`, `options` |
| `path/1` | `.path` | `path_exists`, `path_exists_glob`, `path_changed`, `path_modified` |
| `target/1` | `.target` | (unit section only; no type-specific section) |

---

### D-Bus Manager Control

**Top-level `Systemd.*` — short-lived (opens + closes connection internally):**

```elixir
# Query (often works unprivileged)
{:ok, units}      = Systemd.list_units()           # → [%Systemd.Unit{}]
{:ok, unit_files} = Systemd.list_unit_files()      # → [%Systemd.UnitFileStatus{}]
{:ok, jobs}       = Systemd.list_jobs()            # → [%Systemd.JobStatus{}]
{:ok, state}      = Systemd.unit_state("reth.service")         # → %Systemd.UnitState{}
{:ok, enabled}    = Systemd.unit_file_state("reth.service")    # → "enabled" | "disabled" | ...

# Mutate (may require polkit/root — check with Error.permission?/1)
:ok = Systemd.reload()
:ok = Systemd.start_unit("reth.service")
:ok = Systemd.stop_unit("reth.service")
:ok = Systemd.restart_unit("reth.service")
:ok = Systemd.reload_unit("reth.service")
:ok = Systemd.reload_or_restart_unit("reth.service")   # reload if supported, else restart
:ok = Systemd.try_restart_unit("reth.service")         # restart only if currently active
:ok = Systemd.reset_failed_unit("reth.service")
:ok = Systemd.kill_unit("reth.service", "all", 15)     # who: "all"|"main"|"control", signal: int

# Enable/disable/mask
{:ok, ops} = Systemd.enable_unit_files(["reth.service"])
{:ok, ops} = Systemd.disable_unit_files(["reth.service"])
{:ok, ops} = Systemd.mask_unit_files(["reth.service"])
{:ok, ops} = Systemd.unmask_unit_files(["reth.service"])
{:ok, ops} = Systemd.link_unit_files(["/etc/systemd/system/reth.service"])

# User session bus (for user units, requires systemd --user running)
Systemd.list_units(bus: :session)
Systemd.restart_unit("myapp.service", bus: :session)
```

**`Systemd.Manager.*` — connection-reuse (multiple calls over one D-Bus connection):**

```elixir
# Pattern: with_connection scopes the connection to the block
Systemd.with_connection([], fn conn ->
  with {:ok, unit} <- Systemd.Manager.get_unit(conn, "reth.service"),
       {:ok, state} <- Systemd.UnitObject.state(conn, unit),
       {:ok, svc}   <- Systemd.UnitObject.service_state(conn, unit) do
    {:ok, %{state: state, service: svc}}
  end
end)

# Manual connect/close
{:ok, conn} = Systemd.Manager.connect()
{:ok, unit} = Systemd.Manager.get_unit(conn, "lighthouse.service")
{:ok, unit_by_pid} = Systemd.Manager.get_unit_by_pid(conn, os_pid)
:ok = Systemd.close(conn)
```

**Job tracking:**

```elixir
# Top-level helpers wait for job completion by default.
# Pass wait: false to get the job reference and track yourself.
{:ok, conn} = Systemd.Manager.connect()
{:ok, job}  = Systemd.Manager.restart_unit(conn, "reth.service")

{:ok, :running} = Systemd.Job.state(conn, job)          # :waiting | :running | :done | :unknown
:ok = Systemd.Job.await_signal(conn, job, timeout: 15_000)   # signal-driven (preferred)
:ok = Systemd.Job.await(conn, job, timeout: 15_000)          # polling fallback
:ok = Systemd.Job.cancel(conn, job)                          # cancel queued job

# Low-level signal handling
{:ok, sub}     = Systemd.Signal.subscribe_manager(conn)
{:ok, removed} = Systemd.Signal.await_job_removed(sub, job.object_path, timeout: 15_000)
# removed → %{id:, job_path:, unit:, result:}
:ok = Systemd.Signal.unsubscribe(sub)
```

**Transient units (ephemeral — run without installing a unit file):**

```elixir
# Build properties list with typed constructors from Systemd.TransientUnit
alias Systemd.TransientUnit, as: TU

props = [
  TU.exec_start("/usr/bin/my-job", ["--arg"], false),   # path, argv, ignore_failure
  TU.string("Description", "One-shot indexer job"),
  TU.memory_max(512 * 1024 * 1024),                     # bytes
  TU.tasks_max(64),
  TU.cpu_quota_per_sec_usec(500_000),                   # 50% of one core = 500ms per sec
  TU.boolean("NoNewPrivileges", true),
  TU.uint64("TimeoutStartUSec", 30_000_000)             # 30 seconds in microseconds
]

{:ok, conn} = Systemd.Manager.connect()
{:ok, job}  = Systemd.Manager.start_transient_unit(conn, "indexer-run.service", props)
:ok = Systemd.Job.await_signal(conn, job, timeout: 60_000)
```

**UnitObject inspection (after `get_unit`):**

```elixir
{:ok, state}  = Systemd.UnitObject.state(conn, unit)          # common unit state
{:ok, svc}    = Systemd.UnitObject.service_state(conn, unit)  # service-specific props
{:ok, sock}   = Systemd.UnitObject.socket_state(conn, unit)   # socket-specific props
{:ok, timer}  = Systemd.UnitObject.timer_state(conn, unit)    # timer-specific props
{:ok, val}    = Systemd.UnitObject.property(conn, unit, "MainPID")  # raw D-Bus property
```

---

### Error Handling

```elixir
case Systemd.start_unit("reth.service") do
  :ok ->
    :ok
  {:error, %Systemd.Error{} = error} ->
    cond do
      Systemd.Error.permission?(error) ->
        # polkit denial or insufficient privileges
        {:error, :permission_denied}
      error.category == :not_found ->
        {:error, :unit_not_found}
      error.category == :timeout ->
        {:error, :dbus_timeout}
      true ->
        {:error, error}
    end
end
```

**Error struct fields and categories:**

| Field | Type | Notes |
|-------|------|-------|
| `message` | `String.t()` | Human-readable summary |
| `category` | atom | See table below |
| `reason` | atom | Fine-grained code |
| `dbus_name` | `String.t() \| nil` | Raw D-Bus error name |
| `source` | atom | `:dbus \| :connection \| :protocol \| :validation` |
| `body` | list | Raw D-Bus message body |

| Category | Meaning |
|----------|---------|
| `:permission` | polkit denial, insufficient privileges |
| `:not_found` | unit or job not found on bus |
| `:timeout` | job/connection timeout |
| `:invalid` | bad request (malformed unit name, etc.) |
| `:unsupported` | systemd version doesn't support operation |
| `:unknown` | uncategorized D-Bus error |

---

### Common Issues

| Problem | Cause | Fix |
|---------|-------|-----|
| `Error.permission?(error) == true` on mutations | Running as unprivileged user without polkit rules | Run as root, add polkit rule, or use `bus: :session` for user units |
| Integration tests skipped | `SYSTEMD_INTEGRATION=1` not set | `SYSTEMD_INTEGRATION=1 mix test` on Linux with systemd |
| `validate/2` returns errors before writing | Section key typo or unsupported value type | Check error list; keys are atoms matching the systemd directive in snake_case |
| `equivalent?/2` false on identical-seeming files | Trailing whitespace or comment-only diff | Use `normalize/1` to inspect the semantic map |
| `start_transient_unit` fails | Unit name already loaded | Use `reset_failed_unit` or `stop_unit` first |
| `await_signal` timeout | Job completed before subscription | Fall back to `Job.await/3` (polls) or shorten timeout; check `Job.state` first |

---

### DO NOT

1. Shell out to `systemctl` when `Systemd.*` covers the operation — that's exactly what this library eliminates.
2. Call `Systemd.Manager.connect/0` inside a hot loop — open one connection with `with_connection` and reuse it.
3. Write unit files without calling `Systemd.UnitFile.validate/2` first — validate catches invalid directives before the file reaches disk.
4. Use `Systemd.UnitFile.to_string/1` output as a format string or interpolation target — it's already complete rendered text, not a template.
5. Assume `start_unit/1` blocks until the service is healthy — it returns `:ok` when the job completes, not when the process is ready. Track health separately.
6. Run integration tests in CI without a Linux + systemd environment — they will error, not skip.

---

### Integration Testing Gate

```elixir
# In test_helper.exs or a test tag
@tag :integration
test "reth.service restarts cleanly" do
  # runs only when SYSTEMD_INTEGRATION=1
end
```

```sh
# Default: integration tests excluded
mix test

# Linux CI job with systemd:
SYSTEMD_INTEGRATION=1 mix test
```

The repo ships `scripts/integration_test.sh` and a Lima helper for maintainers to run a local Linux VM.

---

### Dependencies

```elixir
{:systemdkit, "~> 0.1"}
```

No extra runtime dependencies beyond the BEAM. The D-Bus transport is pure Elixir. Does not depend on `:dbus` system libraries or NIFs.
