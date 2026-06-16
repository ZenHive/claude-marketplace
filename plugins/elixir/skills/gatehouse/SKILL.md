---
name: gatehouse
description: gatehouse — OTP-native edge proxy with blue-green deploys and ACME/TLS for Elixir. Use when building an in-app reverse proxy, switching traffic blue-green, terminating TLS with automatic ACME certs, or proxying WebSockets. Hex is a placeholder — clone, do not pin. Covers the Config DSL, Control deploy API, Service gen_statem, RouteTable, HealthCheck, and mix gatehouse.phx local HTTPS.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/gatehouse.md — do not edit manually -->

## Gatehouse — OTP-Native Edge Proxy + Blue-Green Switcher

Runs as a stable Erlang node at the edge; deploy tooling (SSH / Erlang distribution) calls in to rotate targets while Gatehouse never restarts.

**CRITICAL: Hex `0.0.1` is a name-reservation placeholder — do NOT pin it. Clone or use a Git dep.**
```elixir
# mix.exs — only way to get working code today
{:gatehouse, github: "elixir-vibe/gatehouse", branch: "master"}
# dev-only (local HTTPS):
{:gatehouse, github: "elixir-vibe/gatehouse", branch: "master", only: :dev, runtime: false}
```
**First real Hex release is blocked on upstream Livery dependency conflicts (hackney pin between `barrel_mcp` and Livery). A Git fork of Livery is used internally — expect churn until resolved.**

**Min version (repo HEAD ~0.1.0 as of 2026-06).** Requires Elixir ≥ 1.19.

**Runtime deps pulled transitively:** `livery` (Git fork), `gun ~> 2.4`, `ex_acme ~> 0.7`, `x509 ~> 0.9`, `telemetry ~> 1.3`, `req ~> 0.5.8`, `safe_rpc ~> 0.1`, `plug ~> 1.18`, `systemdkit ~> 0.1.2`.

**Caveat:** HTTP-01 ACME only (no DNS-01). Pebble integration test is opt-in (`GATEHOUSE_PEBBLE=1`). State persistence is optional ETF — loss on crash before `save/1` is possible unless `persistence_path` is configured.

**Does NOT cover:** load-balanced multi-target runtime routing (roadmap; current active target is single), Hex-pinnable releases, DNS-01 ACME, non-BEAM deploy orchestration.

**Portfolio fit:** this is the layer `servernodes_rpc` + your nginx-for-RPC routing is becoming — Gatehouse replaces the nginx edge with a BEAM process that the RPC mesh can call directly via Erlang distribution.

---

### Configuration DSL (Caddy-like Elixir, no root wrapper)

```elixir
# /etc/gatehouse.exs
import Gatehouse.Config

state "/var/lib/gatehouse/state.etf"   # optional ETF persistence; restored on boot

http  port: 80
https port: 443,
      cert: "/etc/gatehouse/certs/fallback.crt",
      key:  "/etc/gatehouse/certs/fallback.key"

# ACME (HTTP-01 via ex_acme)
acme email: "ops@example.com",
     cert_directory: "/var/lib/gatehouse/certs",
     account_directory: "/var/lib/gatehouse/acme"

service :my_app do
  host "example.com"
  host "www.example.com"
  target :blue,  "http://127.0.0.1:4000", active: true   # currently serving
  target :green, "http://127.0.0.1:4001"                 # staged / next
  balance :round_robin
  health "/up", timeout: 5_000, interval: 1_000
  drain  30_000          # ms to wait for in-flight requests on old target
  tls    :auto           # triggers ACME issuance/renewal for all hosts above
end
```

Point the app at it:
```elixir
# config/runtime.exs
config :gatehouse, config_path: "/etc/gatehouse.exs"
config :gatehouse, persistence_path: "/var/lib/gatehouse/state.etf"
```

---

### Control Plane API (`Gatehouse.Control`)

All functions work locally or via `:rpc.call/4` from a remote deploy process.

```elixir
# Blue-green deploy: health-check new target, drain old, promote atomically
{:ok, state} = Gatehouse.Control.deploy(%{
  service:        "my_app",
  hosts:          ["example.com", "www.example.com"],
  target_id:      "green-20260608-1",           # arbitrary string ID
  target_url:     "http://127.0.0.1:4001",
  health_path:    "/up",
  health_timeout: 5_000,
  drain_timeout:  30_000,
  metadata:       %{version: "20260608-1"}
})

# Remote deploy from a release/deploy script
:rpc.call(:"gatehouse@prod-host", Gatehouse.Control, :deploy, [spec], 60_000)

# Inspect
{:ok, state}  = Gatehouse.Control.get_service("my_app")    # current gen_statem state
routes        = Gatehouse.Control.routes()                  # [{host, service, target_id}]
snap          = Gatehouse.Control.snapshot()                # %{services: [...], routes: [...]}

# Manual target allocation (advanced / testing)
{:ok, target} = Gatehouse.Control.checkout("my_app", :select)   # :select → auto-pick
:ok           = Gatehouse.Control.checkin("my_app", target.id)

# Persistence
:ok = Gatehouse.Control.save("/var/lib/gatehouse/state.etf")
:ok = Gatehouse.Control.restore("/var/lib/gatehouse/state.etf")
:ok = Gatehouse.Control.restore_if_configured()             # reads persistence_path config

# Apply a full config struct (used by config-file loader on startup)
:ok = Gatehouse.Control.apply_config(config)
```

---

### Service State Machine (`Gatehouse.Service` — `:gen_statem`)

One process per logical service. States:

| State | Meaning |
|---|---|
| `:empty` | Registered but no target ever deployed |
| `:serving` | Active target present; requests proxied |

Key transitions:

| Event | Trigger | Effect |
|---|---|---|
| `{:deploy, spec}` | `Control.deploy/1` | Health-checks new target; if `:ok`, promotes it; old target begins drain countdown |
| `{:configure, spec}` | `Control.apply_config/1` | Bulk-configure multiple targets (load-balance scenario) |
| `{:checkout, id}` | Proxy request start | Increments active request counter on target |
| `{:checkin, id}` | Proxy request end | Decrements counter; if draining + counter == 0, removes target |
| `{:drain_timeout, id}` | Timer expiry | Force-removes old target regardless of in-flight count |

---

### Route Table (`Gatehouse.RouteTable` — ETS)

Sub-μs host lookup. Hosts are lowercased + whitespace-trimmed before insert/lookup.

```elixir
Gatehouse.RouteTable.put(host, service_id, target_id)          # store mapping
Gatehouse.RouteTable.put(host, service_id, target_id, data)    # with target data
Gatehouse.RouteTable.lookup(host)         # {:ok, {service_id, target_id}} | :error
Gatehouse.RouteTable.lookup_target(host)  # {:ok, {service_id, target_id, data}} — uses cursor for round-robin
Gatehouse.RouteTable.delete(host)
Gatehouse.RouteTable.all()                # sorted [{host, service_id, target_id}]
```

---

### Health Check (`Gatehouse.HealthCheck`)

Called automatically by `Service` during deploy. Available standalone:

```elixir
:ok = Gatehouse.HealthCheck.check(%URI{} = base_uri, path: "/up", timeout: 5_000)
# Returns :ok for HTTP 200–399; {:error, {:unexpected_status, status}} or {:error, reason} otherwise
```

---

### ACME / TLS (`Gatehouse.ACME.*`)

`tls :auto` in a service block activates automatic certificate management:

- `Gatehouse.ACME.Provider.ExAcme` — HTTP-01 challenge via `ex_acme ~> 0.7`
- `Gatehouse.ACME.ChallengeStore` — Serves `/.well-known/acme-challenge/…` tokens before proxy routing
- `Gatehouse.ACME.RenewalScheduler` — Tracks expiry, schedules renewal jobs, persists account keys for reuse

SNI lookup reads from the same certificate store. Certificates stored at `cert_directory`. Local Pebble testing: `GATEHOUSE_PEBBLE=1 GATEHOUSE_PEBBLE_EXTERNAL=1 bash scripts/pebble_integration_test.sh`.

---

### WebSocket Proxying (`Gatehouse.WebSocketProxy`)

Upgrade path: Livery detects `Upgrade: websocket`, hands off to `WebSocketProxy`, which bridges bidirectionally to a `Gatehouse.Backend.Gun` session. No explicit configuration — automatic when upstream sends WebSocket upgrade.

---

### Local HTTPS Dev (`mix gatehouse.phx`)

Adds HTTPS to Phoenix dev without touching prod config:

```bash
# 1. Add dep (dev only):
#    {:gatehouse, github: "elixir-vibe/gatehouse", branch: "master", only: :dev, runtime: false}

# 2. Trust the dev CA (one-time per machine):
mix gatehouse.trust    # creates ~/.gatehouse/dev_certs CA; prints OS-specific trust instructions

# 3. Run Phoenix behind the proxy:
mix gatehouse.phx      # proxies http://localhost:4000 → https://my-app.localhost:4443

# Options:
mix gatehouse.run --host my-feature.localhost --proxy-port 4444 --open
mix gatehouse.run --no-tls    # HTTP-only passthrough
```

Phoenix endpoint must read `PORT` env var to avoid port conflicts:
```elixir
# config/dev.exs
config :my_app, MyAppWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT") || "4000")],
  check_origin: ["https://my-app.localhost:4443"]
```

Dev certs live at `~/.gatehouse/dev_certs`. `mix gatehouse.trust` does not run `sudo` — follow the printed instructions to add the CA to your OS/browser trust store manually.

---

### Common Issues

| Problem | Cause | Fix |
|---|---|---|
| `{:error, :not_found}` from `get_service/1` | Service not yet started or name typo | Check `Control.routes/0`; service must have been deployed at least once |
| Health check fails on deploy | New target not ready yet | Increase `health_timeout` or add a readiness delay before calling `deploy/1` |
| Old target still receiving traffic after deploy | Drain timer still running | Wait `drain_timeout` ms; or reduce drain in config |
| ACME challenge 404 | Port 80 not routed to gatehouse, or challenge not registered yet | Verify `http port: 80` in config; check `ACME.ChallengeStore` has registered |
| WebSocket disconnects on redeploy | Drain removes old target while WS still open | Increase `drain_timeout` to cover long-lived connections |
| `mix gatehouse.phx` SSL error in browser | Dev CA not trusted | Re-run `mix gatehouse.trust` and follow OS trust instructions |
| Livery dep conflict at compile time | Hackney pin mismatch between `barrel_mcp` and Livery fork | Check upstream issue; may need to override `:hackney` in `mix.exs` |

---

### DO NOT

1. Pin the Hex `0.0.1` package — it is a non-functional placeholder with no runnable code.
2. Call `Control.deploy/1` without a reachable health endpoint — the deploy will fail and no target swap occurs.
3. Set `drain_timeout: 0` for services with long-lived WebSocket connections — active connections are force-killed.
4. Expose `Gatehouse.Control` functions to untrusted callers without `safe_rpc` guards — the module is distribution-aware by design.
5. Assume SNI cert lookup works without `tls :auto` — fallback cert (`https … cert:` / `key:`) is used for hosts without ACME certs.
6. Share `cert_directory` between multiple gatehouse nodes without external locking — concurrent renewal writes are not coordinated.

---

### Dependencies

```elixir
# Runtime (Git dep until first usable Hex release)
{:gatehouse, github: "elixir-vibe/gatehouse", branch: "master"}

# Dev-only (local HTTPS for Phoenix)
{:gatehouse, github: "elixir-vibe/gatehouse", branch: "master", only: :dev, runtime: false}
```

Transitively requires: `livery` (elixir-vibe Git fork), `gun ~> 2.4`, `ex_acme ~> 0.7`, `x509 ~> 0.9`, `plug ~> 1.18`, `telemetry ~> 1.3`, `req ~> 0.5.8`, `safe_rpc ~> 0.1`, `systemdkit ~> 0.1.2`. Elixir ≥ 1.19 required.
