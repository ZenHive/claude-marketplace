---
name: host-kit
description: host_kit — declarative plan-before-apply Linux host configuration in Elixir. Use when managing host state via a DSL (systemd units, files, INI/YAML/dotenv config, packages, templates, mise), running plan/apply workflows, wiring Caddy or Gatus providers, or building reusable host recipes. Beta API. Covers the DSL, provider model, resource types, Mix tasks, and rollback/run tracking.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/host-kit.md — do not edit manually -->

## HostKit — Declarative Linux Host Management with Plan-Before-Apply

Declare a Linux host in `.exs`, generate an inspectable plan diff, review it, then apply locally or over SSH. No Elixir, Mix, Docker, or runtime required on target machines.

**Min version: `{:host_kit, "~> 0.1.0-beta.5"}`.**  Requires Elixir `~> 1.20`.

**Beta — DSL, provider, and recipe APIs may still change before a stable release.** Core plan/apply workflow is usable and documented.

**Key deps pulled in:** `systemdkit ~> 0.1.4`, `unitctl ~> 0.1.0`, `json_codec ~> 0.1.4`, `jason ~> 1.4`, `yaml_elixir ~> 2.11`, `req ~> 0.5`, `bash ~> 0.5.1`.

**Design axioms:** DSL evaluation never applies changes — it only builds structs. Plans are inspectable JSON artifacts. Mix tasks are wrappers around the runtime API; prefer the API in Elixir callers.

**Caveat:** Repology-based package resolution adds a network call on first plan; use `--repology-cache` in CI. Rollback coverage is resource-type-dependent (files/symlinks yes; directories/packages default to keep).

**Does NOT cover:** runtime config management (Ansible-style variables), container orchestration, multi-host convergence loops, or Windows hosts.

**Portfolio fit:** a generalized form of `servernodes`'s `recipes/base` library — `SystemdService`, `ConfigureReth`, `InstallLighthouse`, `CreateUser`, `MountDisk`, `ConfigureFirewall` all map onto HostKit DSL resources with structured plan diffs instead of imperative shell.

---

### DSL Entry Point

```elixir
# infra/config.exs — evaluated by mix host_kit.* tasks or HostKit.load!/1
use HostKit.DSL, providers: [HostKit.Providers.Caddy]

project :prod do
  roots data: "/srv/apps", config: "/etc/apps"    # named path roots for path(:root, "sub")
  prefixes user: "apps-", unit: "apps-"           # systemd unit and user name prefixes

  host :app, at: "app.example.com" do             # connection endpoint (existing machine)
    ssh do
      user "root"
      identity_file Path.expand("~/.ssh/id_ed25519")
      accept_hosts true                            # auto-accept unknown host keys
      retry attempts: 3, base_delay: 250           # retry transport, not remote commands
    end
  end

  bootstrap do                                     # runs before service resources
    package :ca_certificates
    mise do
      tool :erlang, "29.0.2"
      tool :elixir, "1.20.1"
    end
  end

  service :api do
    account system: true                           # create system user + group
    storage :data, mode: 0o750                     # managed dir under roots[:data]
    storage :config, owner: "root", group: service_user(), mode: 0o750

    env :runtime do
      secret :database_url, env: "DATABASE_URL"   # env-var reference; not stored in plan
    end

    ini path(:config, "app.ini"),                  # structured INI — diffs by key path
      owner: "root", group: service_user(), mode: 0o640 do
      set "APP_NAME", "Example API"
      section "server" do
        set "HTTP_PORT", 4000
        secret "JWT_SECRET", env: :redacted        # modeled but never rendered
      end
    end

    dotenv path(:config, "worker.env"),            # .env file
      owner: "root", group: service_user(), mode: 0o640 do
      set "MIX_ENV", "prod"
      secret "GENERATED_TOKEN", env: :redacted
    end

    yaml path(:config, "health.yaml"),             # structured YAML — keyword list for order
      owner: "root", group: service_user(), mode: 0o640,
      content: [endpoints: [[name: "api", url: "http://127.0.0.1:4000/health"]]]

    daemon :api do
      env :runtime
      exec argv("/opt/api/bin/server",             # argv/2 builds inspectable flag lists
        opts: [config: path(:config, "app.ini"), port: 4000])
      isolate do
        memory_max "512M"
        writable :data                             # ReadWritePaths= in systemd unit
        network :loopback                          # RestrictAddressFamilies= + policy
      end
      listen :http, port: 4000
    end

    caddy_site "api.example.com" do               # requires HostKit.Providers.Caddy
      encode [:zstd, :gzip]
      reverse_proxy :http                          # proxies to daemon's :http listener
    end
  end
end
```

---

### Plan → Review → Apply Workflow

```sh
# 1. Plan: read remote state, diff, write inspectable JSON artifact + package lock
mix host_kit.plan --host app \
  --write-package-lock host_kit.package.lock \
  --out host_kit.plan.json \
  infra/config.exs

# 2. Review the JSON artifact, then apply the exact reviewed plan
mix host_kit.apply --host app \
  --plan host_kit.plan.json \
  --confirm \
  infra/config.exs

# Dry-run without --plan (re-plans inline, no artifact guarantee)
mix host_kit.apply --host app --dry-run infra/config.exs
```

**Execution graph** — append `--show-graph` to `plan` to see dependency layers:

```sh
mix host_kit.plan --host app --show-graph infra/config.exs
# Layer 1: update symlink, update yaml
# Layer 2: update systemd_service (depends on layer 1 paths)
```

---

### Runtime API (prefer over Mix tasks in Elixir callers)

```elixir
# Load + plan + apply — the full pipeline
{:ok, project} = HostKit.load("infra/config.exs")
{:ok, plan}    = HostKit.plan(project, host: :app)
:ok            = HostKit.format_plan(plan) |> IO.puts()   # human-readable diff
{:ok, results} = HostKit.apply(plan, confirm: true)

# Rollback: derive down plan from the up plan
{:ok, down_plan} = HostKit.down(plan)
{:ok, _}         = HostKit.apply(down_plan, confirm: true)

# Partial rollback — only selected resources
{:ok, down_plan} = HostKit.down(plan, only: [{:file, "/etc/app/config.ini"}])

# Read + audit (inspect state without applying)
target = HostKit.Target.local(:prod)
{:ok, current}     = HostKit.Project.read(project, target: target)
{:ok, audit_plan}  = HostKit.Project.audit(project, target: target)
{:ok, facts}       = HostKit.Facts.collect(target, only: [:os, :users, :systemd, :ports])
```

`HostKit.Plan.t` fields: `changes` (list of `HostKit.Change.t`), `diagnostics`, `resources`, `project`, `summary` (map), `opts`.

---

### Resource Types

| Resource | DSL macro | Notes |
|----------|-----------|-------|
| OS package | `package :name` / `packages [:a, :b]` | Repology semantic resolution; lock with `--write-package-lock` |
| File | `file "/path", content: "..."` | Tracks ownership, mode, content |
| Directory | `directory "/path", mode: 0o755` | Rollback: `:keep` by default; opt in with `rollback: :delete_if_created` |
| Symlink | `symlink "/opt/app/current", to: "..."` | Rollback restores prior target |
| Template (EEx) | `template path(:config, "file.conf"), from: "tpl.eex", assigns: %{}` | Assigns may contain `%HostKit.Secret{}` |
| INI config | `ini path, opts do ... end` | Structured diff by key/section; `:redacted` values omit from plans |
| YAML config | `yaml path, content: [...], opts` | Keyword list for stable order; decoded with `yaml_elixir`, rendered with `ymlr` |
| dotenv | `dotenv path, opts do ... end` | `.env` file; secret values are `:redacted`-safe |
| Systemd service | `daemon :name do ... end` | Derives unit name from service prefix; enables `multi-user.target` |
| Systemd timer | `schedule :name do ... end` | Paired with `daemon` for cron-like jobs; typed helpers: `daily`, `weekly`, `monthly`, `jitter`, `repeat_after`, `after_boot` |
| Shell command | `bash :name, "script"` | Use `command/2` with explicit `down:` for reversible ops |
| Git checkout | `source :name, github: "org/repo", ref: "main"` | Source rollback is not inferred; treat as explicit lifecycle |
| Binary release | `release :name` | Emits version-directory + current-symlink resources for binary release layouts |
| User account | `account system: true` | Rollback: `:keep` by default |
| mise runtime | `mise do; tool :erlang, "29.0.2"; end` | Installs BEAM toolchain without system packages |

---

### Providers

Providers contribute DSL macros, resource types, and lifecycle hooks. Core (systemd/unitctl) is not a provider.

```elixir
# Register in use statement
use HostKit.DSL, providers: [HostKit.Providers.Caddy]

# Optional per-project config
project :prod do
  provider :caddy, HostKit.Providers.Caddy do
    set :sites_dir, "/etc/caddy/sites"
  end
  ...
end
```

| Provider | DSL macro | What it emits |
|----------|-----------|---------------|
| `HostKit.Providers.Caddy` | `caddy_site "host" do ... end` | Caddy JSON site config; `reverse_proxy :http` wires to daemon listener |
| `HostKit.Providers.Gatus` | `monitor :http, ...` / `gatus_monitor_endpoints/1` | Provider-neutral HTTP endpoint projection; `gatus_monitor_endpoints/1` renders declared monitors to structured `yaml/2` config (thin helper, not a managed daemon) |

Providers should emit inspectable HostKit structs, not opaque shell calls.

---

### Rollback and Run Tracking

```sh
# Plan + apply with tracking (writes run record under hostkit_runs/)
mix host_kit.apply --host app --track --plan up.plan.json --confirm infra/config.exs

# List tracked runs
mix host_kit.runs --host app infra/config.exs
mix host_kit.runs --host app --latest --verbose infra/config.exs

# Build down plan from a specific tracked run
mix host_kit.down --host app --run 20260614-101148-app-up --out down.plan.json infra/config.exs
mix host_kit.apply --plan down.plan.json --confirm

# Prune run records (keeps newest N)
mix host_kit.runs --host app --prune --keep 20 infra/config.exs
```

Tracked applies copy the up-plan artifact and capture backup payloads for file-like state. `--last` resolves to the most recent tracked run automatically.

---

### Commands with Explicit Rollback

```elixir
# Ecto migrations — down plan calls rollback
command :migrate,
  exec: {"bin/app", ["eval", "App.Release.migrate()"]},
  phase: :before_start,
  down: {"bin/app", ["eval", "App.Release.rollback()"]}

# Irreversible — recorded as warning in down plan, not executed
command :seed, exec: {"bin/app", ["eval", "App.Seeds.run()"]}, down: :irreversible

# Elixir app recipe (Ecto + Phoenix shorthand)
elixir_app :shop do
  source github: "acme/shop", ref: "main"
  phoenix host: "shop.example.com", secret_key_base: secret_env("SECRET_KEY_BASE")
  ecto release: "Shop.Release"   # emits migrate/rollback command pair
end
```

---

### Instance Lifecycle (Incus / ephemeral dev/test)

```elixir
use HostKit.DSL

project :demo do
  instance :demo_vm do
    backend :incus, sudo: true
    image "images:ubuntu/24.04"
    kind :container
    lifecycle :ephemeral
    expose :ssh, host: 2222, guest: 22
    expose :web, host: 18_080, guest: 80

    host :guest, at: "127.0.0.1" do
      ssh do; user "root"; password "hostkit-demo"; port 2222; accept_hosts true; end
    end

    service :web do
      package :caddy
    end
  end
end
```

```sh
mix host_kit.instance ensure demo_vm infra/demo.exs
mix host_kit.instance status demo_vm infra/demo.exs
mix host_kit.instance destroy demo_vm infra/demo.exs
```

---

### argv/2 — Inspectable Flag Builders

```elixir
exec argv("cmd", opts: [foo_bar: "baz"])                 # --foo-bar baz  (default :gnu)
exec argv("cmd", opts: [foo_bar: "baz"], style: :equals) # --foo-bar=baz
exec argv("cmd", opts: [f: "baz", v: true], style: :short) # -f baz -v
exec argv("cmd", opts: [foo_bar: "baz"], style: :underscore) # --foo_bar baz
# bool true → emit flag, false/nil → omit; list values → repeat option
```

---

### Mix Task Reference

| Task | Purpose | Key flags |
|------|---------|-----------|
| `host_kit.plan` | Build plan, print diff | `--host`, `--out`, `--write-package-lock`, `--show-graph`, `--ignore type:name` |
| `host_kit.apply` | Apply a plan | `--plan`, `--confirm` / `--dry-run`, `--track`, `--quiet`, `--verbose` |
| `host_kit.down` | Build rollback plan from artifact | `--plan`, `--last`, `--run RUN_ID`, `--out` |
| `host_kit.audit` | Read state + print drift report | `--host`, `--ignore`, `--package-lock` |
| `host_kit.read` | Read current resource state (no diff) | `--host`, `--format text\|json\|inspect` |
| `host_kit.facts` | Collect host facts | `--only os,users,systemd,ports` |
| `host_kit.instance` | `status\|ensure\|destroy INSTANCE` | `--require` |
| `host_kit.runs` | List/prune tracked run records | `--latest`, `--id`, `--prune --keep N`, `--verbose` |
| `host_kit.render` | Render a single resource to stdout | positional: `type name` |
| `host_kit.dump` | Dump loaded project structs | `--require` |

**Common target flags** (shared across plan/apply/audit/read/facts):
`--host NAME` (declared host, preferred), `--local`, `--remote HOST`, `--user`, `--port`, `--identity-file`, `--password-env VAR`, `--silently-accept-hosts`, `--sudo`.

---

### Common Issues

| Problem | Cause | Fix |
|---------|-------|-----|
| Package name not found | OS name mismatch; Repology resolves semantic names | Use semantic name (`:ca_certificates` not `"ca-certificates"`); check Repology cache path |
| Plan diffs redacted secrets as present/changed | `:redacted` values are never resolved — only the key name is tracked | Expected behavior; use `env:` reference for renderable secrets |
| `daemon` unit name wrong | Missing `prefixes unit: "..."` | Add `prefixes unit: "myapp-"` to project block |
| `mix host_kit.down --last` fails | Apply run not tracked | Pass `--track` to the `apply` invocation |
| SSH host key rejected | New host or key rotation | Add `accept_hosts true` in `ssh do` block or use `--silently-accept-hosts` once, then remove |
| Repology timeout in CI | No cache configured | Add `--repology-cache /tmp/repology_cache` and commit the lock file |
| Directory not removed on rollback | Default rollback policy is `:keep` | Add `rollback: :delete_if_created` to the `directory` call |

---

### DO NOT

1. Apply without reviewing the plan artifact (`--out` → inspect → `--plan`).
2. Use `--password` on the CLI in scripts — use `--password-env VAR` or declared `ssh` config.
3. Hand-write long systemd option strings — use `isolate do ... end` and named profiles (`:web_service`, `:strict_web`, `:strict_app`, `:small`, `:medium`, `:large`).
4. Model reversible commands without an explicit `down:` — HostKit cannot infer the inverse of an arbitrary command.
5. Store secret values in plan artifacts — use `secret_env/1` or `secret key, env: "VAR"`.
6. Skip `--write-package-lock` on first plan in production — package lock ensures deterministic applies.
7. Call Mix tasks from Elixir code — use the runtime API (`HostKit.load!/1`, `HostKit.plan/2`, `HostKit.apply/2`).

---

### Testing Notes

- Integration testing uses Incus containers/VMs (Linux only). The test suite loads `examples/full_host.exs` to prevent DSL drift.
- Unit tests can load `.exs` declarations with `HostKit.load!/1` and assert on returned `HostKit.Project.t` structs without running plan/apply.
- Use `HostKit.Project.resources/1` to assert the resource list from a test fixture `.exs`.
- `HostKit.Plan.build/2` is the programmatic equivalent of `mix host_kit.plan`; pass `target: HostKit.Target.local(:test)` for local-mode unit tests.

---

### Dependencies

```elixir
{:host_kit, "~> 0.1.0-beta.5"}
# Transitive runtime deps pulled in automatically:
# systemdkit ~> 0.1.4, unitctl ~> 0.1.0, json_codec ~> 0.1.4, jason ~> 1.4,
# yaml_elixir ~> 2.11, ymlr ~> 5.1, req ~> 0.5, bash ~> 0.5.1,
# hammer ~> 7.0, dotenvy ~> 1.1, jsonpatch ~> 2.3, telemetry ~> 1.0
```

Source: [github.com/elixir-vibe/host_kit](https://github.com/elixir-vibe/host_kit) | Docs: [host-kit.hexdocs.pm](https://host-kit.hexdocs.pm)
