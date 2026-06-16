---
name: vibe
description: vibe — BEAM-native coding-agent substrate with a TUI and LiveView console. Use when evaluating or running an in-app coding agent on the BEAM, with subagent OTP processes, an Elixir eval control plane, ReqLLM provider passthrough, and SQLite/Ecto session storage. Escript install. Overlaps the harness — evaluate as a complement.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/vibe.md — do not edit manually -->

## Vibe — BEAM-Native Coding Agent Substrate

Experimental terminal/web coding agent that runs as a supervised OTP application rather than wrapping a shell command loop. Eval is the control plane; sessions, jobs, plugins, and subagents are all OTP processes.

**Min version: `{:vibe, "~> 0.2"}` — install as escript, not a library dep (see below).**
**Experimental, not production-ready:** can take actions and contact external providers; review changes before applying.
**Requires Elixir 1.19+ and Erlang/OTP 27+.**
**Provider passthrough via ReqLLM** — accepts `provider:model` strings; auth via `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, etc., or OAuth (`vibe --login codex`).

**Caveat:** v0.2.4 is the latest (May 2026). APIs are still evolving — confirm signatures in hexdocs before pinning.

**Does NOT cover:** production deployment, multi-node clustering semantics, the full plugin behaviour contract, or the Jido/Jido.AI integration details (separate surface).

**Portfolio fit:** Overlaps your harness/Claude-Code loop. Use this include when evaluating vibe as an alternative or complement to the harness — especially the subagent API, eval aliases, and SQLite-backed session model versus harness's own session substrate.

---

### Installation (escript, not dep)

```bash
# Install globally as escript
mix escript.install hex vibe
export PATH="$HOME/.mix/escripts:$PATH"

# Or from checkout
git clone https://github.com/elixir-vibe/vibe.git
cd vibe && mix deps.get && mix ci
mix vibe              # run from checkout
mix vibe.install      # install local executable
```

Do NOT add `{:vibe, ...}` to your project's `mix.exs` — it is a standalone agent application.

---

### CLI Commands

| Command | Purpose |
|---|---|
| `vibe` | Start/attach TUI (singleton background server) |
| `vibe --web [--port 4321]` | Open Phoenix LiveView web console |
| `vibe -p "prompt"` | Single prompt, then exit |
| `vibe --bg "prompt"` | Start background session, detach |
| `vibe new` / `vibe n` | Create fresh session |
| `vibe sessions` / `vibe ls` | List recent sessions |
| `vibe attach [id]` / `vibe a [id]` | Attach TUI to existing session |
| `vibe subagents jobs` | List subagent jobs |
| `vibe connect [--ssh\|--dist] <target>` | Save remote Vibe node |
| `vibe storage status` | DB location + record counts |
| `vibe search "query" --cwd <dir>` | FTS across sessions/memory |
| `vibe storage import pi path/to/session.jsonl` | Import pi session history |
| `vibe skill list` | List available skills |
| `vibe skill show <name>` | Inspect a skill |
| `vibe skill apis` | Show eval APIs available in sessions |
| `vibe skill from-session <id> <name>` | Promote session snippet to skill |

### TUI Slash Commands

```
/help            built-in documentation
/model           select model + reasoning effort
/sessions        browse sessions
/new             start another session
/goal TASK       set persistent goal (long-running work)
/web             open LiveView console
/effort medium   set reasoning effort (low | medium | high)
```

File attachment: `@path/to/file` Pi-style syntax — text becomes context block, images supported.

---

### Eval Aliases (inside a session)

Vibe exposes convenience aliases inside eval contexts. These are the primary "tools" a session uses:

```elixir
# Cmd — supervised shell commands with persisted output
Cmd.run(["mix", "test"], timeout: 120_000) |> MD.doc()
Cmd.run(["git", "diff", "--stat"])

# MD — Markdown rendering
MD.doc(result)

# Web — provider-neutral search/fetch
Web.search!("ecto sqlite fts", num_results: 5, highlights: true) |> MD.doc()

# Goal — session goal controls
Goal.set("Refactor the storage module")
Goal.clear()

# Context recall from session history + memory
Vibe.Context.recall("sqlite migration", cwd: File.cwd!(), limit: 3)

# Telemetry
Vibe.Telemetry.summary()

# Sessions
Vibe.Session.list()
Vibe.Session.active_count()

# Storage
Vibe.Storage.status()
```

---

### Subagents API (`Vibe.Subagents`)

Child sessions launched with independent lifecycles. Each is a full OTP session process.

```elixir
# Fire and await
{:ok, job} = Vibe.Subagents.start("Review the storage search code")
{:ok, result} = Vibe.Subagents.await(job.id)

# Fire and poll
{:ok, job} = Vibe.Subagents.start("Generate test fixtures", model: "openai_codex:gpt-5.5")
{:ok, status} = Vibe.Subagents.status(job.id)
{:ok, result} = Vibe.Subagents.result(job.id)

# Parallel fan-out
{:ok, results} = Vibe.Subagents.run_many([
  "Audit lib/vibe/storage.ex",
  "Audit lib/vibe/session.ex"
], concurrency: 2)

# Lifecycle control
Vibe.Subagents.cancel(job.id)
Vibe.Subagents.jobs()        # all active
Vibe.Subagents.active()      # running, with metadata

# Scheduling
{:ok, job} = Vibe.Subagents.schedule("nightly summary", cron: "0 3 * * *")
Vibe.Subagents.scheduled()
Vibe.Subagents.unschedule(job.id)
```

**Key difference from harness dispatch:** subagents are BEAM processes supervised by the same OTP tree — not remote cloud calls. No HTTP round-trip; failure supervision is native OTP.

---

### Session API (`Vibe.Session`)

Sessions are GenServers that hold semantic UI state. TUI and LiveView are rendering adapters over the same session process.

```elixir
{:ok, pid} = Vibe.Session.start(model: "anthropic:claude-sonnet-4-6")
{:ok, pid} = Vibe.Session.lookup(session_id)

Vibe.Session.list()                       # [map()] from SQLite
Vibe.Session.active_count()               # non_neg_integer()
Vibe.Session.search("sqlite migration")   # [Search.Result.t()]

# Subscribe to events (PubSub-style)
Vibe.Session.subscribe(pid)               # receives events as messages
Vibe.Session.attach(pid, self())          # attach + get current state
Vibe.Session.detach(pid, self())

# Dispatch commands
Vibe.Session.dispatch(pid, :interrupt)
Vibe.Session.dispatch(pid, {:send_message, %{text: "continue"}})

# Manual event emission
Vibe.Session.emit_event(pid, event)
Vibe.Session.emit_transient_event(pid, event)

# Job locking (used internally by subagents)
Vibe.Session.lock(pid, job_id)
Vibe.Session.unlock(pid, job_id)
```

---

### Storage (`Vibe.Storage`)

SQLite under `~/.vibe`. Ecto + `ecto_sqlite3`. FTS built in. WAL mode.

```elixir
Vibe.Storage.status()         # %{db_path:, sessions:, events:, memory:, ...}
Vibe.Storage.ready?()         # boolean — migrations applied?
Vibe.Storage.ensure!()        # idempotent init with global lock
Vibe.Storage.migrate!()       # run pending migrations
Vibe.Storage.checkpoint!()    # WAL truncation checkpoint
Vibe.Storage.vacuum!()        # VACUUM + checkpoint
```

Stored entities: sessions, eval snapshots, memory, telemetry events, subagent jobs, imported history.

---

### Context Compaction (`Vibe.Context`)

Follows pi's structured checkpoint format — summarize trajectory, preserve critical file paths and errors, append read/modified file lists.

```elixir
# Compact current session (reduces token cost on long sessions)
{:ok, result} = Vibe.Context.compact()
{:ok, result} = Vibe.Context.compact(events, model: "anthropic:claude-haiku-4-5")

# Summarize a trajectory
{:ok, summary} = Vibe.Context.summarize(events, previous_summary, [])

# Recall from session history + FTS
text = Vibe.Context.recall("sqlite migration", cwd: File.cwd!(), limit: 3)

# Serialize events for export
string = Vibe.Context.serialize(events)
```

---

### Provider / Model Abstraction (ReqLLM)

Vibe passes `provider:model` strings through `req_llm ~> 1.11`. No Vibe-specific client needed.

```bash
vibe --model anthropic:claude-sonnet-4-6
/model openai_codex:gpt-5.5:high         # model + reasoning effort inline
/effort medium
```

Supported auth:
- `ANTHROPIC_API_KEY` → Anthropic models
- `OPENAI_API_KEY` → OpenAI models
- `vibe --login codex` → ChatGPT/Codex OAuth

---

### Plugins

Built-in plugins activate automatically. Disable in `~/.vibe/agent-profiles.toml`:

```toml
disabled_plugins = ["notify", "safety"]
```

| Plugin | Behavior |
|---|---|
| `rules` | Loads `~/.vibe/rules/*.md` into system prompt at session start |
| `safety` | Confirmation prompt before risky commands |
| `notify` | Terminal notification on task completion |
| `question` | Model-facing multiple-choice question tool |
| `websearch` | Provider-neutral search/fetch tool exposed to the model |

---

### Skills

Trusted local Elixir files evaluated in session context. Load path (in order):
`priv/skills` → `./skills` → `./.vibe/skills` → `~/.vibe/skills`

Skills are not Mix tasks — they are eval'd into the session namespace and can call any Vibe eval API.

---

### Telemetry (`Vibe.Telemetry`)

Subscribes to Vibe, ReqLLM, Jido, Finch, and WebSockex telemetry events. Persisted to SQLite.

```elixir
Vibe.Telemetry.summary()         # event count, frequency by type, 10 most recent
Vibe.Telemetry.recent(50)        # [event] — last N events
Vibe.Telemetry.all()             # all events from storage
Vibe.Telemetry.clear()           # :ok — wipe telemetry table
Vibe.Telemetry.path()            # SQLite DB path

# Emit / span (delegates to :telemetry)
Vibe.Telemetry.execute([:vibe, :custom], %{count: 1}, %{})
Vibe.Telemetry.span([:vibe, :my_op], %{}, fn -> ... end)
```

---

### Vibe vs Harness — Orientation Table

| | Vibe | Harness |
|---|---|---|
| Runtime | OTP app, always-on BEAM process | Claude Code hook executor |
| Session model | GenServer + SQLite events | Hook-driven, no persistent session |
| Subagents | OTP children, native supervision | Cloud dispatch (remote HTTP) |
| Eval surface | `Cmd`, `Web`, `Goal`, full Elixir | Tidewave `project_eval` |
| UI | TUI + LiveView (same process) | Claude Code CLI + browser |
| Provider | ReqLLM passthrough | Direct Anthropic SDK |
| Storage | `~/.vibe` SQLite, WAL, FTS | Per-repo, no central store |
| Maturity | Experimental (v0.2.4) | Production (harness v0.x) |

Use Vibe when you want a persistent BEAM-native agent process that survives Claude Code sessions. Treat it as a complement, not a replacement — harness hooks and Tidewave operate at a different layer.

---

### Self-Check / Dev Gate

```elixir
# Inside a running Vibe session
report = Vibe.Code.Checks.analyze()
report.ok?
report.failures
Vibe.SelfPatch.deployment_gate()
```

```bash
mix ci   # compile, format, tests, Credo, Dialyzer, ExDNA, Reach — full gate
```

---

### Common Issues

| Problem | Cause | Fix |
|---|---|---|
| `vibe: command not found` | escript dir not on PATH | `export PATH="$HOME/.mix/escripts:$PATH"` |
| Session attach fails | No background server running | Run bare `vibe` first to start server |
| Web console blank | Port conflict | `vibe --web --port 4322` |
| Model auth error | Missing env var | Set `ANTHROPIC_API_KEY` or use `vibe --login codex` |
| `Vibe.Storage.ready?/0` returns false | Migrations not run | `Vibe.Storage.ensure!()` or restart vibe |
| Subagent job stuck | Session lock held | `Vibe.Subagents.cancel(job_id)` |

---

### DO NOT

1. Add `{:vibe, ...}` as a Mix dependency in an app that is not vibe itself — it is an escript.
2. Assume subagents are isolated from the host BEAM — they share the same node, same ETS, same distribution.
3. Store secrets in `~/.vibe/rules/*.md` — these are injected into every session system prompt.
4. Use `Vibe.Storage.vacuum!()` while subagents are running — WAL checkpoint truncates active writers.
5. Confuse vibe skills (eval'd Elixir files) with harness skills (Claude Code plugins) — different mechanism entirely.

---

### Dependencies

Key runtime deps pulled in by vibe (for awareness when auditing dep trees):

```
ecto_sql ~> 3.12, ecto_sqlite3 ~> 0.23   # storage
req ~> 0.5.18, req_llm ~> 1.11            # HTTP + LLM passthrough
phoenix ~> 1.8, phoenix_live_view ~> 1.1  # web console
volt ~> 0.12                              # UI primitives
jido ~> 2.2, jido_ai ~> 2.1              # agent primitives
ex_ast ~> 0.12, reach ~> 2.6.1           # code analysis (dev gate)
boxart ~> 0.3.3                          # terminal graph rendering
```
