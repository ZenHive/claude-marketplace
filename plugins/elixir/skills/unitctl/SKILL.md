---
name: unitctl
description: unitctl — Docker-like process control on top of systemd for Elixir. Use when starting/stopping/restarting/inspecting transient services with resource limits, sandboxing, and cgroup stats via a container-like API. API preview only and depends on systemdkit. Covers start/stop/restart/inspect/stats, Spec options, and Instance/Stats structs.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/unitctl.md — do not edit manually -->

## unitctl — Docker-like Process Control via systemd

Opinionated runtime layer above `systemdkit`: starts and controls transient systemd services over D-Bus without Docker and without shelling out to `systemctl`.

**Min version: `{:unitctl, "~> 0.1.0-pre"}`.** Depends on `{:systemdkit, "~> 0.1.1"}`.

**API-preview only.** The README states: *"This package is intentionally early. It exists to claim the shape of the API."* Function signatures and option keys may change before a stable release. Use `"~> 0.1.0-pre"` (pre-release pin), not `"~> 0.1"`.

**Linux + systemd only.** Integration tests require a live systemd bus (`SYSTEMD_INTEGRATION=1 mix test`). macOS developers use `scripts/integration_test.sh` (Lima-backed). No test coverage possible in CI without Linux.

**Four public functions:** `Unitctl.start/1`, `stop/2`, `restart/2`, `inspect/2`, `stats/2`. Lifecycle operations accept either a `%Unitctl.Instance{}` or a bare unit name string.

**Caveat:** Stats fields (`memory_current`, `cpu_usage_nsec`, etc.) return `nil` when the host systemd version doesn't expose the property or when cgroup accounting is disabled for the unit. Plan for nil in all stats fields.

**Does NOT cover:** OCI/Docker image lifecycle, `systemctl` CLI wrappers, multi-node orchestration, journald log tailing (planned), secrets/credentials management (planned), or any non-Linux platform.

**Portfolio fit:** Useful for bare-metal node process isolation in Xamal-style deployments — run BEAM releases as cgroup-constrained transient units instead of reaching for Docker per node process.

---

### Spec Options (`Unitctl.start/1`)

Pass a keyword list or map; `Unitctl.Spec.new/1` validates and normalizes it internally.

| Key | Type | Required | Notes |
|-----|------|----------|-------|
| `name` | `String.t()` | Yes | Service identifier; unit becomes `<name>.service` |
| `command` | `[String.t()]` | Yes | Executable + argv list — first element must be an absolute path |
| `description` | `String.t()` | No | Appears in `systemctl status` |
| `environment` | `%{String.t() => String.t()}` | No | Env vars injected into the unit |
| `working_directory` | `String.t()` | No | Process working path |
| `user` | `String.t()` | No | Run as this OS user |
| `group` | `String.t()` | No | Run as this OS group |
| `restart` | `String.t()` | No | systemd `Restart=` value (e.g. `"on-failure"`) |
| `timeout_stop_usec` | `non_neg_integer()` | No | Stop timeout in microseconds |
| `bus` | `:system \| :session` | No | Default `:system` |
| `wait` | `boolean()` | No | Default `true` — await job completion signal |
| `wait_timeout` | `non_neg_integer()` | No | Default `30_000` ms |
| `resources` | `map` | No | cgroup limits — see below |
| `sandbox` | `map` | No | Security presets — see below |

#### `resources` keys

| Key | Type | Notes |
|-----|------|-------|
| `memory_max` | `non_neg_integer()` | Bytes; maps to `MemoryMax=` |
| `tasks_max` | `non_neg_integer()` | Thread cap; maps to `TasksMax=` |
| `cpu_quota` | `non_neg_integer()` | Microseconds per second of CPU time |

#### `sandbox` keys

| Key | Type | Notes |
|-----|------|-------|
| `dynamic_user` | `boolean()` | Allocate a transient UID/GID |
| `no_new_privileges` | `boolean()` | Block privilege escalation via execve |
| `private_tmp` | `boolean()` | Isolated `/tmp` |
| `private_devices` | `boolean()` | No raw device access |
| `protect_system` | `String.t()` | `"strict"` \| `"full"` \| `"yes"` |
| `protect_home` | `String.t()` | `"true"` \| `"read-only"` \| `"tmpfs"` |

---

### Core API

```elixir
# Start a transient service (keyword list or map)
{:ok, instance} =
  Unitctl.start(
    name: "demo-worker",                       # required
    command: ["/usr/bin/env", "sleep", "60"],  # required — full path as first element
    description: "Demo worker",
    environment: %{"MIX_ENV" => "prod"},
    working_directory: "/srv/demo",
    resources: %{
      memory_max: 256 * 1024 * 1024,           # 256 MiB
      tasks_max: 64,
      cpu_quota: 500_000                        # 0.5 CPU seconds per second
    },
    sandbox: %{
      no_new_privileges: true,
      private_tmp: true,
      protect_system: "strict"
    }
  )

# instance is %Unitctl.Instance{name: "demo-worker", unit: "demo-worker.service", ...}

# Read systemd state (returns %Systemd.UnitState{})
{:ok, state} = Unitctl.inspect(instance)
{:ok, state} = Unitctl.inspect("demo-worker.service")  # bare unit name also works

# Read cgroup/D-Bus runtime metrics (returns %Unitctl.Stats{})
{:ok, stats} = Unitctl.stats(instance)

# Restart (keeps the unit name, re-runs command)
:ok = Unitctl.restart(instance)

# Stop
:ok = Unitctl.stop(instance)
```

---

### `%Unitctl.Stats{}` Fields

All cgroup metrics may be `nil` — see caveat above.

| Field | Unit | Notes |
|-------|------|-------|
| `unit` | string | Canonical unit name (`demo-worker.service`) |
| `active_state` | string | `"active"` \| `"inactive"` \| `"failed"` \| ... |
| `sub_state` | string | e.g. `"running"`, `"exited"` |
| `main_pid` | integer \| nil | Main process PID |
| `control_group` | string \| nil | cgroup path |
| `memory_current` | bytes \| nil | Current RSS |
| `memory_peak` | bytes \| nil | Peak RSS since unit start |
| `tasks_current` | integer \| nil | Current thread count |
| `cpu_usage_nsec` | nanoseconds \| nil | Cumulative CPU time |
| `ip_ingress_bytes` | bytes \| nil | Requires `IPAccounting=yes` |
| `ip_egress_bytes` | bytes \| nil | Requires `IPAccounting=yes` |
| `io_read_bytes` | bytes \| nil | Requires `IOAccounting=yes` |
| `io_write_bytes` | bytes \| nil | Requires `IOAccounting=yes` |

---

### `Unitctl.Spec` (direct use)

`Unitctl.start/1` calls `Spec.new/1` internally. Use the struct directly when you want to validate or inspect the spec before starting.

```elixir
{:ok, spec} = Unitctl.Spec.new(name: "worker", command: ["/usr/bin/worker"])
spec = Unitctl.Spec.new!(name: "worker", command: ["/usr/bin/worker"])  # raises on invalid

Unitctl.Spec.unit_name(spec)     # "worker.service"
Unitctl.Spec.to_properties(spec) # [%Systemd.TransientUnit.Property{}, ...]
```

Validation errors: `{:error, {:name, :required}}` or `{:error, {:command, :required}}`.

---

### Return Types

| Call | Success | Error |
|------|---------|-------|
| `Unitctl.start/1` | `{:ok, %Unitctl.Instance{}}` | `{:error, term()}` |
| `Unitctl.stop/2` | `:ok` or `{:ok, %Systemd.Job{}}` | `{:error, term()}` |
| `Unitctl.restart/2` | `:ok` or `{:ok, %Systemd.Job{}}` | `{:error, term()}` |
| `Unitctl.inspect/2` | `{:ok, %Systemd.UnitState{}}` | `{:error, term()}` |
| `Unitctl.stats/2` | `{:ok, %Unitctl.Stats{}}` | `{:error, term()}` |

---

### Common Issues

| Problem | Cause | Fix |
|---------|-------|-----|
| `{:error, :connection_refused}` or bus error on start | No systemd session bus / not on Linux | Run integration tests on Linux only; mock for unit tests |
| `{:error, {:name, :required}}` | `name:` key missing or empty string | Always pass `name:` as a non-empty binary |
| `{:error, {:command, :required}}` | `command:` list empty or first element not a binary | First element must be an absolute path string |
| `stats/2` returns all-nil fields | cgroup accounting not enabled for unit | Enable `MemoryAccounting`, `CPUAccounting` in systemd or use `resources:` on start |
| `wait: true` (default) times out on slow host | `wait_timeout` default is 30 s | Pass `wait_timeout: <ms>` or `wait: false` to skip job-done signal |
| Stats counter shows `nil` instead of `0` | `18_446_744_073_709_551_615` sentinel → normalized to `nil` | Treat `nil` as "unavailable", not "zero" |

---

### DO NOT

1. Shell out to `systemctl` alongside unitctl — use the API; mixing them races on job state.
2. Pass a relative path as the first `command:` element — systemd requires an absolute executable path.
3. Pin `{:unitctl, "~> 0.1"}` (stable range) — there is no `0.1` stable release; use `"~> 0.1.0-pre"`.
4. Run integration tests in CI without a real systemd bus — they will error, not skip.
5. Expect `stop/2` return to always be `:ok` — it may return `{:ok, %Systemd.Job{}}` when the job is asynchronous; pattern-match both.
6. Assume non-nil stats fields are always populated — even on Linux, accounting must be explicitly enabled.

---

### Testing Notes

- Unit tests that call `Unitctl.start/1` will fail without a live systemd bus. Use the guard env var pattern:

  ```elixir
  @moduletag :integration
  # mix test --only integration  (on Linux with SYSTEMD_INTEGRATION=1)
  ```

- macOS: use `scripts/integration_test.sh` (Lima VM) — sets up the bus automatically.
- Mock `Unitctl.start/1` at the boundary for pure unit tests; the `Unitctl.Spec` struct is constructable without a bus.

---

### Planned (not yet implemented)

Per the README and CHANGELOG, these are scoped for future releases: journald log streaming/follow, filesystem isolation beyond `PrivateTmp`, secrets/credentials injection, deployment-runtime primitives (Xamal-style). Do not rely on any of these existing yet.

---

### Dependencies

```elixir
{:unitctl, "~> 0.1.0-pre"},
{:systemdkit, "~> 0.1.1"}   # pulled in transitively; pin if you use it directly
```

Requires Elixir `~> 1.18`. No runtime deps beyond `systemdkit` and the BEAM.
