---
name: sprite-claude-code
description: Operational reference for Fly Sprite-hosted Claude Code as a third cloud-delegation target. CLI surface (sprite create / exec / sessions / checkpoint / info / api, the --env / --file / --tty / --http-post flags, the lack of --prompt on create), auth threading (interactive OAuth, CLAUDE_CODE_OAUTH_TOKEN for unattended, ANTHROPIC_API_KEY + claude --bare for pure API billing), reachability profile (full hex.pm, full PATH, Elixir/Erlang/Mix pre-installed at /.sprite/bin without asdf, Tidewave + user's Phoenix app reachable in same VM, public HTTPS URL per sprite), sleep/wake (30s idle, ext4 + JuiceFS + Litestream-backed persistence, filesystem-level conversation state survives, ~0.4s wake-on-exec), cost ceiling (claude --max-budget-usd built-in + checkpoint/restore + sprite destroy), known orchestration gaps (no built-in completion signal, claude --print exit code unreliable, no Linear-poll wrapper yet). Sibling of `cloud-agent-environments` and the cloud-agent delegation skills (`linear-queue`, `agent-dispatch`, `agent-pr-review`, `flow-review`).
allowed-tools: Read, Grep, Glob, Bash
---

<!-- Auto-synced from ~/.claude/includes/sprite-claude-code.md — do not edit manually -->

## Sprite-Hosted Claude Code (third cloud-delegation target)

Operational reference for Fly Sprite-hosted Claude Code as a third delegation option alongside Codex Cloud and Cursor Background. Sibling of `cloud-agent-environments.md` (harness-mode reference for Codex/Cursor) and `agent-dispatch.md` (dispatcher view).

**Different shape from the existing two targets.** Codex Cloud and Cursor Background are polished **harnesses** — task ingestion → branch → PR loop is built in. Sprite is **substrate**: a raw VM (Ubuntu 25.10 + Fly kernel) with Claude Code 2.1.92 pre-installed in `--dangerously-skip-permissions` mode, full network, ext4 + JuiceFS + Litestream-backed persistence. Tokens billed against the user's existing Anthropic Max plan via OAuth; no extra subscription stack. Cost shape ~$0.46 per 4-hour active session (per Simon Willison) plus per-second VM time. The trade is the orchestration glue — not built in.

### CLI surface (rc43)

| Surface | Notes |
|---|---|
| `sprite create [name] [--skip-console] [--label <l>] [--org <o>]` | **No `--prompt` / `--task` / `--exec`** — create is provisioning only. `--skip-console` for headless. `--label` repeatable. |
| `sprite exec -s <n> [--env "K=V,K2=V2"] [--file local:remote] [--dir <p>] [--tty] [--http-post] -- <cmd>` | `--env` is comma-separated. `--file` uploads before exec (repeatable). `--http-post` is a transport toggle (HTTP/1.1 instead of WebSockets, non-TTY only); **NOT** an external orchestration entry point. Always use `--` to terminate sprite flags. |
| `sprite sessions list / attach <id> / kill <id>` | First-class in rc43 — closes the long-standing "no detached background mode" gap. Non-TTY sessions suspend on detach (preserves output); TTY sessions keep running. **Active sessions block auto-sleep.** |
| `sprite attach <command-or-id>` | Smart-match by command name OR session ID. |
| `sprite checkpoint create [--comment] / list / info <id> / delete <id> / restore <id>` | Copy-on-write filesystem snapshots; last 5 at `/.sprite/checkpoints/`. `create` returns in seconds. |
| `sprite info` | Replaces deprecated `sprite url`. Shows public URL, auth setting, labels. |
| `sprite config update --url-auth public\|sprite --label <l>` | URL auth `sprite` (org-only, default) or `public`. **No `--sleep-timeout` flag — sleep policy is fixed.** |
| `sprite proxy <port>` / `sprite proxy -W :<port>` | Local→remote port forwarding; `-W` is stdio-over-port (SSH-style). |
| `sprite use [name]` / `sprite use --unset` | Per-directory `.sprite` file (nvm-style). |
| `sprite api <path> [curl options]` + REST at `https://api.sprites.dev/v1/sprites` | Authenticated curl-via-CLI plus a public REST API. Real orchestration entry point for non-CLI dispatchers. |

**Shell-syntax gotcha:** `sprite exec 'echo a && echo b'` fails — `sprite exec` does NOT interpret shell. Use `-- bash -c 'echo a && echo b'` or upload a script via `--file local.sh:/tmp/run.sh -- bash /tmp/run.sh`. The `--file` upload is the cleanest dispatcher pattern (write task locally, ship + execute atomically).

### Inside the sprite

- **OS:** Ubuntu 25.10 + custom Fly kernel (`6.12.84-fly`).
- **Pre-installed at `/.sprite/bin/`:** `claude` (Claude Code 2.1.92), `gh` (2.79.0), `git`, `node`, `python3`, **`mix`, `elixir`, `erl`** (Erlang/OTP 28, Elixir 1.19.2 — current). **No asdf shim layer needed.** Closes the entire class of asdf-PATH gotchas Cursor's env has.
- **Pre-baked home dir:** `~/.claude/` (with `projects/`, `sessions/`, `skills/`, `hooks/`, `backups/`, `settings.json`), `~/.codex/`, `~/.cursor/`, `~/.gemini/`. OAuth tokens land here after interactive login and persist via the ext4 filesystem across sleep/wake.
- **Network:** hex.pm reachable (HTTP 200, ~285ms), api.github.com reachable (HTTP 200). Strictly greater than Cursor on capability axis; both reach internet.

### Reachability profile (vs `cloud-agent-environments.md` matrix)

| Capability | Codex Cloud | Cursor Cloud | Sprite |
|---|---|---|---|
| hex.pm | ❌ | ✅ | ✅ |
| Elixir runtime | ❌ (suspended) | ✅ via `/usr/local/elixir/bin` (asdf shim risk) | ✅ at `/.sprite/bin` (no asdf layer) |
| Tidewave + live Phoenix in same VM | ❌ | ✅ via `curl` (native `CallMcpTool` needs pre-start) | ✅ first-class |
| Dialyzer memory | n/a (no runtime) | bounded by Cursor cloud cap | bounded by sprite VM size (provisionable) |
| External orchestrator entry | task-ingestion harness | task-ingestion harness | `sprite api` + REST `api.sprites.dev/v1/sprites` |
| Public HTTPS URL | ❌ | ❌ | ✅ `https://<n>-XXX.sprites.app` (auth-gated) |

**Implication:** Sprite is strictly more capable than Codex/Cursor on capability axes (hex.pm, dialyzer-memory, same-VM-Tidewave, OS-package install with full sudo on Ubuntu 25.10). Strictly less polished on auto-task-ingestion + status-loop axes. Pick by which axis the task lives on.

### The dispatcher loop (today, manual)

Three viable entry shapes — pick by task profile:

**(a) One-shot synchronous** — caller blocks until claude finishes:
```bash
# Write task script locally, ship + execute atomically.
sprite exec -s <n> \
  --env "CLAUDE_CODE_OAUTH_TOKEN=$TOKEN,GH_TOKEN=$GH" \
  --file /tmp/task.sh:/tmp/run.sh \
  -- bash /tmp/run.sh
```
Simple; caller pays the wall-clock cost.

**(b) Detached session** — sprite stays alive while session generates output:
```bash
sprite exec -s <n> --tty -- bash -c 'cd repo && claude "<task>"'
# Detach (Ctrl-\), monitor with:
sprite sessions list
sprite attach <session-id>
```
Best for long-running interactive work; active sessions block auto-sleep.

**(c) HTTP-driven via REST API** — cleanest for an external orchestrator that isn't running the CLI:
```bash
curl -X POST https://api.sprites.dev/v1/sprites \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"name":"<n>"}'
# Then sprite api <path> for further calls.
```

Across all three: agent ends by `gh pr create` + `gh pr merge <N> --auto --squash --delete-branch` (GH-native auto-merge wire-up); dispatcher polls `gh pr list --search 'head:<branch>'` for the new PR; GitHub handles the merge gate (CI green + no requested-changes + no `[BLOCK-MERGE]` label); `staged-review:audit-review` picks up post-merge via the deferred SessionStart hook. **No built-in "agent done" signal** — observe the artifact (PR appearance) or grep `claude --print` stdout for a done-marker.

### Anthropic auth (three options)

1. **Interactive OAuth** — `sprite console`, run `claude`, complete `/login` flow once. Token in `~/.claude/`, persists across sleep/wake. **Open question:** does the `/login` flow open a browser on the host, print a device code, or fall back to URL-paste? Untested inside sprite console.
2. **`CLAUDE_CODE_OAUTH_TOKEN` env var** — long-lived OAuth token from `claude setup-token` on a workstation. Pass via `sprite exec --env CLAUDE_CODE_OAUTH_TOKEN=…`. Cleanest for unattended.
3. **`ANTHROPIC_API_KEY` + `claude --bare`** — pure API-key billing. Per `claude --help`: bare-mode "Anthropic auth is strictly ANTHROPIC_API_KEY or apiKeyHelper via --settings (OAuth and keychain are never read)." Use when you don't want plan-OAuth coupling.

**🚨 Footgun:** `claude --print "..."` with no creds prints `Not logged in · Please run /login` and exits with **status 0**. Dispatcher scripts MUST verify the work artifact (PR existence, file contents), not check `$?`.

### GitHub + Linear MCP auth

- **GitHub:** `gh auth login --web` interactive once, OR `GH_TOKEN`/`GITHUB_TOKEN` env var (unattended via `--env`).
- **Linear MCP:** `claude mcp add --scope user --transport http linear-server https://mcp.linear.app/mcp` inside the sprite. **Open question:** does workspace OAuth complete inside `sprite console` without browser access? Untested.

### State and persistence

- **Filesystem fully persists across sleep/wake** (ext4 + JuiceFS object-store + Litestream-backed SQLite metadata).
- `~/.claude/`, `~/.codex/`, `~/.cursor/`, `~/.gemini/` are pre-baked in the base image; OAuth tokens written into them after interactive login persist.
- `~/.bashrc` exports persist.
- **Process state does NOT.** `claude` process dies on sleep. To resume the same conversation: `claude --continue` (resumes most-recent session in cwd) or `claude --resume <session-id>` (specific session). Filesystem-level resume is plausible; **clean cross-sleep resume is unverified** — open question.
- **Wake-on-exec ~0.4s round-trip.**
- **Branch state pushed to GitHub each commit; the sprite is disposable.** Don't store anything important only inside.

### Public URL (capability that doesn't exist on Codex/Cursor)

Every sprite gets a permanent **public HTTPS URL** at `https://<n>-XXX.sprites.app`. Default auth `sprite` (org-only); flip via `sprite config update --url-auth public`. Phoenix / Tidewave running inside the sprite is reachable externally **without keeping `sprite proxy` running** — webhooks, public demos, external orchestrator pulls all work directly.

### Cost ceiling

- **`claude --max-budget-usd <amount>`** — Claude Code 2.1.92 built-in dollar cap; aborts session when reached. First-class spend ceiling.
- **`sprite checkpoint create --comment "…"`** before risky `mix deps.update` / heavy compile; **`sprite restore <id>`** to roll back filesystem state.
- **Hard ceiling:** `sprite destroy <name> --force`. Filesystem + URL gone.
- **Open question:** per-org Fly billing cap (sprite-side) for runaway compute. CLI doesn't expose; check Fly dashboard.

### Per-agent decision matrix (when to pick Sprite)

| Task profile | Pick |
|---|---|
| Live Phoenix app + Tidewave in same VM | **Sprite** > Cursor |
| Heavy dialyzer / OOM-prone analyses | **Sprite** > Cursor (provision more memory) |
| Cost-sensitive throughput on Anthropic Max plan | **Sprite** > Cursor (no extra subscription) |
| Tasks needing OS packages or system-level setup | **Sprite** > Cursor (full sudo on Ubuntu 25.10) |
| Tasks Codex's no-Elixir-runtime env can't run | **Sprite** is the migration path back |
| Routine self-contained PR with auto-task-ingestion + status flips | **Cursor** — Sprite needs hand-rolled glue |
| Polish-sensitive one-shot with built-in PR loop | **Cursor** — Sprite has no built-in loop |

### Known orchestration gaps (today)

- **No Linear-poll wrapper.** A `~/.claude/scripts/sprite-delegate.sh` taking a Linear issue ID and running create + token-inject + `--file` upload + URL-poll loop is the obvious follow-up. Track as ROADMAP candidate; not in this skill's scope.
- **No built-in agent-done signal.** Use the workaround patterns above (PR appearance / done-marker grep).
- **`claude --print` exit code is unreliable** (always 0 even on auth failure). Verify artifacts.

### Open questions

1. Does interactive `claude` `/login` complete cleanly inside `sprite console` — browser on host, device code, or URL-paste?
2. Does `claude --continue` resume cleanly after an actual sleep/wake cycle?
3. Does `claude mcp add … linear-server` complete its workspace OAuth inside a sprite without browser access?
4. What's the per-org Fly billing cap (sprite-side) on runaway compute?

### Cross-references

- `cloud-agent-environments.md` — sibling, harness-mode reference for Codex/Cursor.
- `agent-dispatch.md` — dispatcher view; Sprite delegation flow not yet written (TODO once `sprite-delegate.sh` exists).
- Commit / push / PR-create inside a sprite are allowed by default, same as anywhere else; only the irreversible/outward gates remain (`delegation-rules.md` § "DON'T AUTO-MERGE PRS" / cloud-agent branches).
- Fly Sprites docs: https://docs.sprites.dev/
- Fly Sprites design + implementation blog: https://fly.io/blog/design-and-implementation/
- Fly MCP commentary: https://fly.io/blog/unfortunately-mcp/
