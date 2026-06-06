---
name: phoenix-setup
description: Phoenix project setup and authentication configuration. This skill should be used when creating a Phoenix project, generating authentication with phx.gen.auth (CRITICAL --live flag), adding Sobelow or LiveDebugger, configuring .formatter.exs with HTMLFormatter, or setting up Tidewave endpoint plug. Use after elixir-setup for Phoenix-specific additions.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/phoenix-setup.md — do not edit manually -->

## Phoenix Project Setup

### 🚨 ALWAYS `--live` for Authentication

```bash
mix phx.gen.auth Accounts User users --live    # ✅
mix phx.gen.auth Accounts User users           # ❌ missing LiveView scoping
```

Without `--live`, `config/config.exs` scope configuration is incomplete. Subsequent `mix phx.gen.live` won't scope to current user — generated code won't filter by `user_id`, creating a **major security vulnerability** where users can see/edit each other's data. Forgetting requires complete redo of auth + re-cherry-picking subsequent work.

With `--live`: context functions auto-accept `%Scope{}`, queries auto-filter by `user_id`, security by default.

### Phoenix-Specific Deps

For base Elixir tooling (Styler, Credo, Dialyxir, Doctor, Tidewave), see `elixir-setup.md`. Add:

```elixir
{:sobelow, "~> 0.14", only: [:dev, :test], runtime: false},     # security: SQL/XSS/CSRF
{:live_debugger, "~> 0.7", only: :dev}                          # UI at localhost:4007
```

Phoenix projects do NOT need `{:bandit, ...}` — Phoenix already has an HTTP server.

### Tidewave for Phoenix

Add to `lib/my_app_web/endpoint.ex` **ABOVE** the `if code_reloading?` block:

```elixir
if Code.ensure_loaded?(Tidewave) do
  plug Tidewave
end

if code_reloading? do
  ...
end
```

### LiveDebugger

Add to `lib/my_app_web/components/layouts/root.html.heex`:

```heex
<head>
  <%= Application.get_env(:live_debugger, :live_debugger_tags) %>
  ...
</head>
```

Runs at `http://localhost:4007`. Docs: https://hexdocs.pm/live_debugger/welcome.html

**0.6+/0.7+ knobs** (in `config/dev.exs` under `:live_debugger`):
- `:auto_port` — pick free port if 4007 taken
- `:ignore_startup_errors` — don't crash on init failure
- Settings defaults via config (was UI-only)
- "Open in editor" buttons, user-event sending API

**⚠️ `web` command limitation:** separate browser session — LiveViews hit via `web http://localhost:4000` won't appear in LiveDebugger's Active LiveViews list. Open `http://localhost:4007` in the same browser as `:4000`, or use `browser_eval` for same-session inspection.
