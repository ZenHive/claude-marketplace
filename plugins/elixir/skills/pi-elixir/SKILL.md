---
name: pi-elixir
description: pi-elixir — agent-to-BEAM bridge giving the pi coding agent stateful eval and AST edits in a running app. Use when connecting pi or a harness Pi adapter to a live BEAM node, doing structural AST search/replace through the agent (ex_ast-backed), running supervised agent sessions, or autodiscovering Tidewave endpoints. Not on Hex — npm plus pi_bridge, exact-version pin required.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/pi-elixir.md — do not edit manually -->

## pi-elixir — BEAM Runtime Bridge for the pi Coding Agent

Connects the pi agent to a running Elixir/OTP system: stateful IEx-style eval, ExAST structural search/rewrite, supervised BEAM sessions, and Tidewave autodiscovery.

**Not on Hex — install from npm + pin the BEAM bridge to match.**
**Min install: `pi install npm:pi-elixir` (npm side) + `{:pi_bridge, "== 0.6.21", only: :dev}` (Mix side).** Exact version pinning is deliberate — the TypeScript extension and BEAM bridge speak a versioned stdio protocol; they must match.
**Two packages ship together:** `packages/extension/` (TypeScript, pi tool registration, transport) and `packages/bridge/` (Elixir, `Pi.*` modules, eval runtime). Clone from `github.com/elixir-vibe/pi-elixir`.
**Requires Elixir `~> 1.16` and OTP 27+** for new projects; Elixir 1.20+ recommended.
**ExAST `~> 0.12` is a hard dep** (pulled automatically via `pi_bridge`); supplies all AST pattern matching.

**Caveat:** docs are split across `packages/bridge/README.md`, `packages/extension/README.md`, `AGENTS.md`, and `packages/bridge/docs/protocol.md` — no single canonical hexdocs page.

**Does NOT cover:** static analysis, architecture gates, smell checks (→ Reach), dependency security (→ Sobelow), clone detection (→ ExDNA), test running (→ ExUnit tools).

**Portfolio fit:** the harness already carries a Pi adapter stub and a Tidewave plug — pi-elixir's `elixir_eval` + `AST.diff(changed: true)` is the natural verification layer after hook-driven edits, and `elixir_ast_replace` closes the loop for AST-level structural rewrites the harness dispatches.

---

### Installation (from source)

```bash
# 1. Add pi-elixir to the pi agent
pi install npm:pi-elixir

# 2. Add the BEAM bridge to your Mix project (dev only)
#    Run this from inside the Mix project, or use the slash command:
/elixir:install
# Adds to mix.exs: {:pi_bridge, "== 0.6.21", only: :dev}

# 3. Local dev / pin-to-clone
git clone https://github.com/elixir-vibe/pi-elixir
cd pi-elixir
pnpm install
cd packages/bridge && mix deps.get && cd ../..
pi install "$PWD"    # installs from local clone instead of npm
```

Version mismatch symptom: `pi_bridge version mismatch` — update the Mix dep to match the npm version.

---

### Connection Model (three tiers, resolved in order)

| Tier | Mechanism | When it fires |
|------|-----------|---------------|
| 1 | `PI_MCP_URL` env var | Manual HTTP MCP endpoint |
| 2 | Discovered HTTP MCP | Probes `localhost:4000–4009`; matches `project_name` against `mix.exs` `app:` — this is the **Tidewave path** |
| 3 | Embedded stdio | Default fallback; spawns a Mix child process |

Status bar shows `⬡ BEAM` when tier 2 connects to an external/Tidewave endpoint. Check with `/elixir:status`; full diagnostics via `/elixir:doctor`.

---

### Three Model-Facing Tools

| Tool | Label in pi | What it does |
|------|------------|--------------|
| `elixir_eval` | `iex` | Stateful trusted eval inside the running app |
| `elixir_ast_search` | `ast grep` | ExAST structural search over source files |
| `elixir_ast_replace` | `ast edit` | ExAST structural rewrite with dry-run diffs |

---

### elixir_eval — Stateful IEx-Style Eval

Bindings, aliases, imports, and requires persist across eval calls (Livebook-style cells). Errors preserve the previous good state. State is snapshotted to sidecar files alongside the pi session JSONL.

```elixir
# iex: first call — alias persists
alias MyApp.Repo; alias MyApp.Billing.Invoice
stale = Repo.all(from i in Invoice, where: i.status == :overdue)
length(stale)
# => 14

# iex: second call — `stale` still bound
stale |> Enum.group_by(& &1.customer_id) |> Enum.map(fn {id, xs} -> {id, length(xs)} end)
# => [{"cust_123", 5}, {"cust_456", 9}]
```

**State management (callable from eval):**

```elixir
Pi.Eval.bindings()       # inspect current bound vars
Pi.Eval.forget(:stale)   # drop one binding
Pi.Eval.reset()          # clear all state
Pi.Eval.sandbox(code)    # untrusted snippet; requires optional {:dune, "~> 0.3"}
```

**Preloaded in eval env:** `Pi.Self`, `Pi.CodeMap`, `Pi.Quack`, `Pi.Quack.Event`.

**Sidecar storage:**
```
<session.jsonl>.pi-elixir/
  eval-state/
    <toolCallId>.term
    <toolCallId>.term.meta.json
```

---

### elixir_ast_search / elixir_ast_replace — ExAST Patterns

Patterns are **plain Elixir syntax** — not regex, not a custom DSL. The ExAST engine matches on AST structure; pipe forms are normalized.

**Pattern language:**

| Syntax | Meaning |
|--------|---------|
| `_` | Match any single expression (wildcard) |
| `name` (bare variable) | Capture any expression into `name` |
| `...` | Capture variable-arity argument sequences |
| `^name` | Match the literal variable `name` |
| `%{key: val}` | Partial map match |
| `%User{role: :admin}` | Struct partial match |
| `{:ok, result}` | Tuple match |
| `def f(_, _) do _ end` | Function definition pattern |

**ast grep** (search):

```bash
ast grep 'IO.inspect(_)' lib/my_app
ast grep 'Repo.get!(_, _)' lib/
ast grep 'def handle_call(msg, _, state) do _ end' lib/
ast grep 'case _ do _ -> _ end' lib/my_app/accounts.ex
```

**ast edit** (replace — always dry-run first):

```bash
# Replace IO.inspect with Logger.debug
ast edit 'IO.inspect(expr, _)' 'Logger.debug(inspect(expr))' lib/ --dry-run
ast edit 'IO.inspect(expr, _)' 'Logger.debug(inspect(expr))' lib/

# Replace Logger.debug with Logger.info across a subtree
ast edit 'Logger.debug(_)' 'Logger.info(_)' lib/my_app --dry-run

# Strip dbg calls
ast edit 'dbg(expr)' 'expr' lib/
```

**Programmatic API (from eval):**

```elixir
# Find all matches in a source string
ExAST.Patcher.find_all(source, "Enum.take(_, -_)")

# Named batch: find multiple patterns at once
ExAST.Patcher.find_many(source,
  get_env: "@_ Application.get_env(_, _)",
  dbg_call: "dbg(expr)"
)

# Preview a rewrite (returns %ExAST.Rewriter.Plan{replacements:, conflicts:})
ExAST.rewrite_plan(source, "dbg(expr)", "expr")

# Query with predicate filter
import ExAST.Query
from("def handle_event(event, _, _) do ... end")
|> where(^event == :click or ^event == :keydown)

# Symbol index helpers
ExAST.Symbols.definitions(source)    # [{module, function, arity, span}, ...]
ExAST.Symbols.references(source)
ExAST.Comments.extract(source)
```

---

### Syntax-Aware Code Review (AST.diff)

Added in v0.6.19. Use after edits to get a semantic diff grouped by module/function:

```elixir
# iex: summarize what changed vs git HEAD
AST.diff(changed: true)

# iex: semantic project map (Reach-backed)
CodeMap.reflect(changed: true)
```

Output groups public API edits separately from private helpers. Preferred over raw `git diff` for agent-driven review steps.

---

### Pi.* Runtime APIs (callable from eval)

```elixir
# Project info
Pi.project()
Pi.logs(tail: 50)

# Docs
Pi.Docs.entries()
Pi.Docs.get(MyApp.Accounts, :register, 2)

# HTTP fetch
Pi.Web.fetch!("https://...")

# LLM bridge (routes through active pi session)
Pi.LLM.complete(messages, opts)
Pi.LLM.stream(messages, opts)
Pi.ReqLLM.install()              # installs as ReqLLM adapter
Pi.ReqLLM.current_model()

# Feature gate (in library code)
require Pi.Features
Pi.Features.gate :llm do
  Pi.LLM.complete(...)
end
```

---

### Sessions and Agents

```elixir
# Supervised BEAM session — server-owned process
{:ok, session} = Pi.Session.start(name: "backfill-check")
Pi.Session.run(session, fn -> ... end)
Pi.Session.run(session, fn -> ... end, stream: true)   # delta events
Pi.Session.subscribe(session)
Pi.Session.state(session)

# Concurrent agent jobs
job = Pi.Agent.start(fn -> ... end, role: :worker, parent_session_id: id)
Pi.Agent.await(job, 30_000)
Pi.Agent.result(job)
Pi.Agent.cancel(job)

Pi.Agent.parallel([fn -> ... end, fn -> ... end])
Pi.Agent.fanout([task_a, task_b])
Pi.Agent.run_many([job1, job2])
```

Sessions serialize as `customType: "elixir-sessions"` widgets in the pi transcript. Status summary format: `2 done · 1 failed · ↑2.0k ↓400 $0.005`.

---

### Plugin System

Plugins run behind isolated `Pi.Plugin.Worker` processes. Discovered from `priv/pi_plugins`, `.pi/plugins`, or `pi_plugins` in the project root.

```elixir
defmodule MyApp.PiPlugin do
  @behaviour Pi.Plugin

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def handle_event(event, state), do: {:ok, state}

  @impl true
  def commands, do: [command name: :my_cmd, description: "Run my thing"]

  @impl true
  def handle_command(:my_cmd, _args, state), do: {:reply, "done", state}

  @impl true
  def tool_call(name, args, state), do: {:ok, state}      # or {:block, reason}

  @impl true
  def tool_result(name, result, state), do: {:ok, state}  # patch content or isError

  @impl true
  def apis, do: []

  @impl true
  def shutdown(state), do: :ok
end

# Dynamic load/unload
Pi.Plugin.Manager.load(MyApp.PiPlugin, [])
Pi.Plugin.Manager.unload(MyApp.PiPlugin)

# Emit events to the TypeScript extension
Pi.Plugin.Event.emit(:my_event, %{data: "..."})
```

---

### Slash Commands

| Command | Purpose |
|---------|---------|
| `/elixir:install` | Add `pi_bridge` dep to `mix.exs` and fetch |
| `/elixir:status` | Concise bridge connection summary |
| `/elixir:doctor` | Full setup diagnostics |
| `/elixir:debug` | Writes snapshot to `~/.pi/agent/pi-elixir-debug.log` |
| `/elixir:sessions.cancel` | Cancel running BEAM sessions |
| `/elixir:sessions.rerun` | Rerun last session |
| `/elixir:restart` | Restart the embedded BEAM bridge |

---

### Feature Flags

| Flag | Default | Effect |
|------|---------|--------|
| `PI_ELIXIR_STATEFUL_EVAL=0` | on | Disable stateful eval (each call is isolated) |
| `PI_ELIXIR_EVAL_SIDECAR=0` | on | Keep eval state in-memory only (no .term files) |
| `PI_ELIXIR_LLM=0` | on | Disable BEAM-initiated LLM requests |
| `PI_ELIXIR_SESSIONS=0` | on | Disable session snapshots and control |
| `PI_ELIXIR_PLUGINS=0` | on | Disable plugins, hooks, UI events, commands |
| `PI_ELIXIR_SKILLS=0` | on | Disable executable Elixir skill discovery |
| `PI_ELIXIR_MIRROR=0` | on | Disable QuackDB/DuckDB event mirror |
| `PI_ELIXIR_COMPACT_EVAL_PREVIEW=1` | off | Force single-line eval previews |

---

### Common Issues

| Problem | Cause | Fix |
|---------|-------|-----|
| `Mix cwd: not found` | pi not started from a Mix project directory | Start pi from inside the project root |
| `Elixir is not installed` | Elixir/Mix not on `PATH` | Install Elixir, verify `mix --version` |
| `pi_bridge dependency: missing` | Bridge not added to `mix.exs` | Run `/elixir:install` |
| Embedded BEAM exited before ready | Mix compile error | Fix the error; run `/elixir:restart` |
| `pi_bridge version mismatch` | npm version ≠ Mix dep version | Update `{:pi_bridge, "== <new>"}` in `mix.exs` |
| `Cannot find module 'dedent'` | Stale npm install (pre-v0.6.20) | `pi install npm:pi-elixir` to upgrade |
| Eval state stale after branch switch | Sidecar from a previous session loaded | `Pi.Eval.reset()` to clear |

---

### DO NOT

1. Pin `pi_bridge` to a version range (`~>`). The bridge and npm extension must be **identical versions** — use `"== <version>"` only.
2. Add `pi_bridge` outside `:dev` only — it starts a stdio server process and has no prod purpose.
3. Call `ExAST.rewrite_plan` and apply changes without dry-running `ast edit ... --dry-run` first — the plan may have conflicts.
4. Mix `elixir_ast_search` patterns with regex syntax — patterns are plain Elixir AST nodes, not regexes.
5. Call `Pi.Eval.reset()` mid-session without capturing the bindings you need — state is lost immediately.
6. Assume eval state survives a bridge restart (`/elixir:restart`) — sidecar snapshots reload, but the live binding map is rebuilt from them.
7. Use `PI_ELIXIR_LLM=0` while relying on `Pi.ReqLLM.install()` — they share the same flag path.

---

### pnpm / JS Build (local dev only)

The `packages/extension/` directory is TypeScript and ships pre-built in the npm package. Only clone and build locally when modifying the extension:

```bash
cd pi-elixir
pnpm install
pnpm run fmt             # format
pnpm run check           # full release-readiness gate (JS + BEAM)
pnpm run check:js        # TypeScript lint + typecheck + tests
pnpm run check:beam      # mix compile / test / credo / dialyzer
pnpm run test:integration
pnpm run pack:check      # validates npm publish artifact
```

---

### Dependencies

```elixir
# mix.exs — exact pin, dev only
{:pi_bridge, "== 0.6.21", only: :dev}
```

`pi_bridge` pulls in: `jason ~> 1.4`, `json_codec ~> 0.1.5`, `ex_ast ~> 0.12`, `req ~> 0.5`, `quackdb ~> 0.5.4`, `ecto_sql ~> 3.13`, `bandit ~> 1.8`, `plug ~> 1.18`.

Optional: `{:req_llm, "~> 1.6"}` for BEAM-side LLM calls; `{:dune, "~> 0.3"}` for sandboxed eval (`Pi.Eval.sandbox/1`).
