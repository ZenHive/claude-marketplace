---
name: cloud-agent-environments
description: Operational reference for cloud-agent harnesses (Codex Cloud, Cursor Background Agent) — what each can and can't reach (hex.pm, mix tasks, Tidewave, external HTTP), runtime gotchas (Cursor's Erlang/Elixir paths, asdf shim interception, Credo TODO exit-code-2 expected behavior), self-validation expectations (Cursor should run the harness pre-PR; Codex can't), and the AGENTS.md generation workflow that gives both agents the same instruction set Claude Code uses. Loaded into AGENTS.md via @-import. Sibling of the `agent-dispatch` / `agent-pr-review` delegation skills (the dispatcher / reviewer view).
allowed-tools: Read, Grep, Glob, Bash
---

<!-- Auto-synced from ~/.claude/includes/cloud-agent-environments.md — do not edit manually -->

## Cloud Agent Environments

Operational reference for cloud-agent harnesses (Codex Cloud, Cursor Background Agent). Loaded into AGENTS.md via `@`-import so agents read env-specific runtime details, gotchas, and capability scope before doing work.

For the **reviewer / dispatcher** view (push-back-vs-fix calculus, eligibility markers), see `agent-pr-review.md` § "Push-Back-vs-Fix-Locally Matrix by Agent" and `agent-dispatch.md` § "Delegation Eligibility Filter Order". This file is the **agent's own** env reference.

### Codex Cloud

#### 🚨 Code-mutation delegation SUSPENDED (Elixir projects)

**Codex Cloud's Elixir path is broken at the proxy layer, not the runtime layer.**

- `mise` is present in the image, with **Erlang 27.1.2** and **Elixir 1.18.3-otp-27** pre-installed at `/root/.local/share/mise/installs/{erlang,elixir}/...`. Binaries exist but aren't on default PATH — naive `mix ...` fails `command not found`.
- Even when you point at the pre-installed binary directly with explicit PATH + `MIX_HOME`, **`mix local.hex` and `mix deps.get` return `hex.pm` 403 Forbidden through the agent-phase proxy**. The Codex Cloud "Common dependencies" allowlist preset covers crates.io / npmjs.com / pypi.org but not hex.pm.
- Repos that pin a newer toolchain via `mise.toml` (e.g. Erlang 28 / Elixir 1.19.5-otp-28) hit a second wall: `mise install` can't reach the toolchain assets through the proxy either.

Net effect: Codex can't run any `mix` task, ships zero harness evidence. The load-bearing fix is hex.pm allowlisting (and ideally putting the mise-installed Elixir on default PATH), not "install Elixir." Until that lands, **`[CX]` code-mutation delegation is suspended** for any Elixir repo. See `agent-dispatch.md` § "Codex Delegation (`[CX]`)" for the policy lock; route everything to `[CSR]` (Cursor) in the meantime — Cursor's harness has Elixir/OTP on PATH, hex.pm reachable, and runs the full mix toolchain.

Public ask filed with Symphony team: [openai/symphony#70](https://github.com/openai/symphony/discussions/70).

**What's still permitted (no runtime needed):** review-only delegations — see § "Review-only tasks" below. Codex reads PR diffs from the issue body and posts a verdict comment; no `mix` invocation, no compile, no test runner involved. The Codex-Reviews-Cursor pattern (see `agent-dispatch.md` § "Codex Delegation (`[CX]`)") remains usable while the code-mutation suspension is in force, but treat as exception-not-default until the broader env is verified healthy.

#### Constraints (configurable network, no usable mix toolchain)

Even setting aside the suspended-delegation policy above, Codex Cloud's env has structural gaps that scope what it can do at all:

- **Elixir runtime present but unreachable.** `mise` ships with Erlang 27.1.2 + Elixir 1.18.3-otp-27 installed at `/root/.local/share/mise/installs/{erlang,elixir}/...`, but not on default PATH (so naive `mix` fails `command not found`). Even with explicit PATH/`MIX_HOME` pointing at the pre-installed binary, **`hex.pm` returns 403 through the proxy** — `mix local.hex` and `mix deps.get` both fail at the registry layer. Repos pinning a newer toolchain via `mise.toml` also can't fetch toolchain assets via `mise install`. This is the load-bearing reason for the Elixir suspension above; the fix is hex.pm allowlisting, not runtime install.
- **Network access is environment-configurable, not categorically absent.** Per [OpenAI's Codex Cloud docs](https://developers.openai.com/codex/cloud/internet-access), the agent phase defaults to offline, but operators may enable per-environment allowlists. The "Common dependencies" preset reaches **crates.io, npmjs.com, pypi.org, and ~70 dev domains** (source control, vendor docs for the common ecosystems, etc.). **hex.pm is NOT in the common preset** — even with the preset enabled, `mix deps.get` would still fail, which is why this whole section reads "no internet" from the Elixir perspective. For Rust / Python / Node delegations: assume reach to the canonical registry is plausible-but-unverified; try before trusting, and fall back to in-prompt context when blocked. Don't assume RFCs / EIPs / arbitrary vendor docs are reachable unless explicitly allowlisted.
- **No Tidewave.** `mcp__tidewave__project_eval` is not available. Tasks needing live-data diagnosis or runtime-state inspection should not be in scope.
- **HTTP-method restriction (when network IS enabled).** Operators can lock allowlisted domains to `GET` / `HEAD` / `OPTIONS` only; state-changing methods (`POST`, `PUT`, `PATCH`, `DELETE`) are then blocked. Treat any allowlisted endpoint as read-only unless verified otherwise.

#### What to ship in the PR (when delegation is restored)

When the runtime gap is fixed and `[CX]` code-mutation delegation resumes, Codex PRs may still ship without full local test evidence depending on what's been restored — CI runs the harness Codex couldn't, and `audit-review` (deferred, post-merge) does the 5+1-category audit. To hold a PR for pre-merge manual review, add the `[BLOCK-MERGE]` label per `agent-pr-review.md` § "Review Tiering". Make the reviewer's job easier:

- **List acceptance criteria you addressed** in the PR description (one bullet per criterion).
- **Flag uncertainty explicitly** — "I'm assuming `assert_receive/3` here based on training-data recall; please verify against ExUnit's hex docs."
- **Don't fabricate test counts or runtime claims** you can't verify — Codex's env can't execute `mix` tasks. CI is the only honest harness signal; see `agent-pr-review.md` § "CI as the Shared Harness".

#### Review-only tasks (review delegation)

When you (Codex Cloud) are assigned an issue whose body opens with `REVIEW-ONLY task. Do NOT open a PR, commit code, or edit files`, the deliverable is a Linear comment — not a PR.

1. The issue body embeds the full PR diff inline under "## PR Diff". Read it from the issue body; you do NOT need `gh pr diff`.
2. Optionally — if `gh` CLI is available in your sandbox — run read-only commands `gh pr view <N> --json reviews,comments`, `gh api repos/<OWNER>/<REPO>/pulls/<N>/comments`, `gh pr checks <N>` for additional context. If `gh` is unavailable, skip this; the embedded diff is sufficient.
3. Post ONE comment on the delegation issue with: verdict line (APPROVED / BLOCKED / DISCUSS), findings table (`file:line | category | severity (1-10) | description`), one paragraph on acceptance-criteria coverage.
4. Transition the issue to Done.
5. Do **not** open a pull request. Do **not** commit code. Do **not** edit any file. Do **not** post review comments on the GitHub PR — verdict goes on the Linear issue only.

**Pilot status:** the "no PR" instruction's reliability is unverified. If your harness pushes you toward opening a PR for a review-only issue, **stop and post a Linear comment instead**. Stray review-PRs are a known v1 risk.

### Cursor Cloud

#### Runtime

The Cursor Background Agent Linux env ships with Erlang and Elixir at non-asdf paths. Set PATH explicitly before any mix command:

- **Erlang/OTP 27** — installed at `/usr/local/bin/erl` (prebuilt `.deb` from [benoitc/erlang-dist](https://github.com/benoitc/erlang-dist)).
- **Elixir 1.18.4** — installed at `/usr/local/elixir/bin/`. Add to PATH:

  ```bash
  export PATH="/usr/local/elixir/bin:$PATH"
  ```

- **asdf shim gotcha** — if `asdf` shims are present in PATH (often inherited from `~/.bashrc`), they intercept `erl` and fail with `"No version is set for command erl"`. The Cursor environment-setup script removes them; if the error reappears mid-session, check `~/.bashrc` for asdf entries and restart the shell.

#### Capabilities

Cursor cloud has internet + can run mix tasks:

- **hex.pm reachable** — third-party hex-package API signatures can be verified directly. The `assert_received` vs `assert_receive` class of bug should not recur on Cursor PRs.
- **Mix tasks runnable** — `mix deps.get`, `mix compile`, `mix test` (and `mix test.json` if `ex_unit_json` is in deps), `mix credo --strict`, `mix format --check-formatted`, `mix dialyzer` (provided the PLT cache builds — first-run cost on a fresh env).
- **General HTTP likely available** — not yet stress-tested against arbitrary external APIs / RFCs / EIPs. Treat as broadly available pending counter-evidence.
- **Tidewave reachable (with setup).** The Cursor Background Agent VM can run Tidewave on `localhost:<port>/tidewave/mcp`; agents reach it two ways:
  - **Always works:** raw `curl` to the MCP endpoint with a `tools/call` JSON body. No session-start dependency — usable mid-session even if Tidewave wasn't running at startup.
  - **Native via `CallMcpTool`:** requires Tidewave to be **running before the agent session begins**. Cursor's MCP client caches the initial connection result, so a server started mid-session won't be picked up natively — the agent has to fall back to `curl` for that session. `.cursor/mcp.json` configures the client to point at the MCP URL.

  **Pre-start options** (so `CallMcpTool` works natively): leave `mix tidewave` running in a tmux session from a prior agent run (persists across sessions in the same VM), or bake startup into a VM snapshot. The Cursor environment-setup script can't itself launch Tidewave reliably enough to satisfy "running at session start," because the MCP client probes too early.

#### Tidewave on Cursor — Reach details

```bash
# Direct MCP call (always works once Tidewave is running):
curl -s -X POST http://localhost:4002/tidewave/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call",
       "params":{"name":"project_eval","arguments":{"code":"1 + 1"}}}'
```

Tools available on Cursor identical to local: `project_eval`, `get_docs`, `get_source_location`, `get_logs`, `search_package_docs`. Port comes from the project's Tidewave registry entry (`~/.claude/tidewave-ports.md`); the `.cursor/mcp.json` URL must match.

**Implication for delegation:** live-data / runtime-state tasks are NOT a Cursor-eligibility blocker the way they used to be. Push-back-vs-fix matrix updates accordingly — see `agent-pr-review.md` § "Push-Back-vs-Fix-Locally Matrix by Agent".

#### Self-validation expectation

**Cursor MUST run the full harness green before opening the PR.** A PR that opens with any harness check failing is a defect, not a draft for review — the local reviewer's job is the 5-category audit + acceptance-criteria cross-reference, *not* triaging mechanical harness failures the agent could have caught itself. A red harness in a Cursor PR is a push-back finding regardless of severity: stop the audit, post a Linear `@cursor` comment naming the failing check, wait for re-push.

**Mandatory pre-PR checklist** (every check must exit clean — exit 0 for tools that don't have content-aware exit codes; for `mix credo` see the TODO/FIXME exit-2 carve-out below):

```bash
mix format --check-formatted     # MUST be clean — no drift on touched files
mix compile --warnings-as-errors # MUST compile with no warnings
mix credo --strict               # MUST be clean (TODO/FIXME exit-2 is the only acceptable non-zero — see Gotchas)
mix sobelow --exit Low           # MUST be clean — security scanner; project's `.sobelow-skips` baseline applies
mix doctor                       # MUST be clean — every public function has @doc + @spec; honors `.doctor.exs` ignore_paths
mix test.json --quiet            # MUST be green — every test passes
mix test.json --cover --cover-threshold N  # MUST meet repo's coverage tier (≥80 standard, ≥95 critical)
mix dialyzer                     # MUST be clean — first-run PLT cost is on Cursor's clock, subsequent runs are cached
```

**Why MUST not SHOULD:** Cursor's env has the runtime to do this work; if the harness fails post-push, every reviewer/CI cycle that catches it is wasted ceremony. Push-back-on-red-harness is the cheapest enforcement loop — Cursor amends, re-pushes, CI re-runs in parallel with whatever else is in flight. The reviewer's audit attention should land on the diff's *substance* (acceptance criteria coverage, design judgment, edge cases the harness can't catch), not on `mix format` complaints.

**For the issue body's acceptance criteria:** see `agent-dispatch.md` § "Code-Only PRs + Required Acceptance Criteria" — every delegated issue carries an explicit "harness green at PR open" bullet, so a failing harness is a blocking acceptance-criterion miss, not a "soft polish" item.

#### Gotchas

- **Credo TODO/FIXME exit code** — Credo flags `TODO:` / `FIXME:` tags as design suggestions and exits with code 2 even when nothing else is wrong. Per `~/.claude/includes/development-philosophy.md` § "TODO Comment Requirements", surfaced TODOs are _tracked debt working as intended_, not regressions. Don't strip them. Treat exit code 2 with only TODO/FIXME findings as expected, not as a blocker.
- **`mix format --check-formatted` on pre-existing drift** — repos that aren't fully formatted may surface format violations on files outside the diff. Only fix drift on files the PR touches (per `critical-rules.md` § "FIX HOOK-FLAGGED ISSUES ON FILES YOU TOUCH"); leave the rest for the repo owner.

#### Linear handle

Cursor's Background Agent has Linear-displayName `cursor` (id: `b8668f6b-992f-4152-9e59-13b6fe1f599b`). Reviewers push back via Linear comments with `@cursor` mention; Cursor picks up the mention within ~5 min and amends the PR with a fresh commit, posting confirmation comments back on the issue. Linear @-mention preferred over GitHub PR comment — keeps the conversation thread on the issue.

### Local CLI agents (Grok, Antigravity, Pi, Droid)

Unlike Codex Cloud and Cursor Cloud, these four run as **local CLIs** on the developer's own machine — full toolchain, full internet, live project state, no sandbox proxy. They're delegation *targets* in the sense that `rmap delegate --to grok|antigravity|pi|droid` renders a paste-ready prompt for them; this section is the canonical source the rmap delegate footers mirror (rmap's `append_agent_notes` literals are hand-synced from here — see rmap's CLAUDE.md delegate invariant). Grounded in the harness adapter source.

| Agent | Headless CLI | Worktree isolation | Instruction file | Cost |
|---|---|---|---|---|
| **Grok** | `grok -p` / `--single` | OK | AGENTS.md | metered |
| **Antigravity** | `agy -p` | **broken** — see note | AGENTS.md + GEMINI.md | metered |
| **Pi** | `pi` | OK | AGENTS.md (cwd-walk + `~/.pi/agent/AGENTS.md`) | **free** (local LLM, pi.dev) |
| **Droid** | `droid` (Factory) | n/a (no harness adapter) | AGENTS.md (root / nested / `~/.factory/AGENTS.md`) | — |

- **Antigravity worktree caveat:** `agy` resolves its workspace via git-common-dir and ignores the invocation cwd — it can edit the **main checkout even when pointed at a worktree**. Don't rely on cwd-scoped isolation; the harness adapter marks `worktree_isolation: false` for this reason. (Antigravity also reads `GEMINI.md` in addition to AGENTS.md.)
- **Pi:** runs a local LLM in autonomous permission mode — free/unmetered, so the usual "is this worth the spend" calculus doesn't apply.
- **Droid (Factory):** rmap-only — **not** a harness executor yet. The delegate prompt is for the Factory Droid CLI or manual paste; there is no downstream adapter to ingest its output.
- All four auto-discover `AGENTS.md`, so the existing `sync-agents-md.sh` → `AGENTS.md` workflow (below) already covers them. No per-agent pointer file needed beyond the optional `GEMINI.md` one-liner for Antigravity's native channel.

### CI as the Shared Harness

When the target repo has a `harness.yml` (see `elixir-ci-harness` skill in `claude-marketplace`), every PR push runs the full Elixir harness as a GitHub check — visible to user, agent, and PR review tooling. CI doesn't close the Codex hex.pm + PATH gap (a PR with no harness-validated commits is one CI green away from the same uncertainty either way — one reason `[CX]` code-mutation delegation is suspended). For Cursor PRs, CI is the authoritative harness signal regardless of whether the agent ran the harness pre-PR.

The shift this enables:

- **Reviewer reads `gh pr checks <n>`** instead of running the full local harness (was 15+ min per PR via local mix; CI runs in parallel with the agent's work and is done by the time the reviewer looks)
- **Push-back becomes the default for harness drift.** When CI flags a format / credo / dialyzer / coverage issue, the reviewer's job is to point the agent at the failing check — not to fix it locally. The cloud agent (Cursor especially, since it has hex.pm + can run mix) iterates against the same CI signal the reviewer sees
- **Local fix shrinks to the env-constraint exception cases.** Per `agent-pr-review.md` § "Push-Back-vs-Fix-Locally Matrix by Agent", local-fix is reserved for items the agent fundamentally can't verify — hex.pm for Codex, Tidewave for Codex (Cursor reaches it via curl), external specs for Codex. CI handles everything else

GH-native auto-merge requires CI status checks to gate against (per `plugins/review/templates/auto-merge.md` § 1 "Branch protection"). When CI is absent, auto-merge cannot fire — the merge falls back to manual `gh pr merge`. File a `TODO(setup-ci)` rmap follow-up pointing at this skill so the next iteration of the PR has CI; `audit-review` Step 9 will surface the gap if it persists.

**Adoption path for delegation-target repos without CI:** copy `templates/harness.yml` from the `elixir-ci-harness` skill into the target repo's `.github/workflows/`, customize the four marked points (branch, MIX_ENV, coverage threshold, integration tag), commit. The next PR push gets the harness check.

### AGENTS.md Generation

Both Codex and Cursor read `AGENTS.md` at the repo root if present. Generate it from `CLAUDE.md` so agents see the same instruction set Claude Code does — same hooks-equivalent guardrails, same `@`-imported includes.

#### Canonical generator

`scripts/sync-agents-md.sh` in the `claude-marketplace` repo (path: `~/_DATA/code/claude-marketplace/scripts/sync-agents-md.sh`) — a **manual** tool (the old `delegation`-plugin PostToolUse auto-sync hook was retired in the zenhive migration). Run from inside the target repo:

```bash
bash ~/_DATA/code/claude-marketplace/scripts/sync-agents-md.sh
```

The script reads `./CLAUDE.md`, resolves `@`-imports (including `~/`), inlines content with `<!-- @-import: ... -->` markers, and writes `./AGENTS.md`. Marker comment at the top reads `<!-- Auto-generated from CLAUDE.md by ... — do not edit manually -->`.

#### Workflow

1. Edit project `CLAUDE.md` (or any `~/.claude/includes/*.md` it imports).
2. Run `sync-agents-md.sh` to regenerate `AGENTS.md`.
3. Commit both files together — they should never drift.

#### When Cursor auto-generates an AGENTS.md PR

Cursor's setup task can autonomously open a PR scaffolding an `AGENTS.md` for its env. When this happens in a repo that already uses the `sync-agents-md.sh` workflow:

- **Close the auto-generated PR.** The canonical generator is the source of truth.
- **Extract any genuinely useful env-specific bits** (paths, gotchas, runtime quirks) and add them here in this include — so they auto-flow to every repo's AGENTS.md via the standard `@`-import chain.
- Don't merge ad-hoc per-repo `AGENTS.md` content. The whole point of generating from `CLAUDE.md` is single-source consistency across the portfolio.

### Fly Sprite (third target — different shape)

Fly Sprite-hosted Claude Code is a third delegation option that doesn't fit the harness model documented above — it's a raw VM (Ubuntu 25.10 + Fly kernel) with Claude Code 2.1.92 pre-installed in `--dangerously-skip-permissions` mode, full network access, full ext4 persistence backed by JuiceFS + Litestream, and **Elixir/Erlang/Mix pre-installed at `/.sprite/bin/` without an asdf shim layer** — closes the entire class of asdf-PATH gotchas Cursor's env has. Tokens billed against the user's existing Anthropic plan via OAuth (no extra subscription stack). Different shape, different operational concerns (no built-in task ingestion, no completion signal, `claude --print` exit code unreliable). See **`sprite-claude-code.md`** for the CLI surface, auth threading, sleep/wake quirks, and the manual-orchestration loop. Strictly more capable than Codex/Cursor on hex.pm + live-Phoenix-app + dialyzer-memory axes; strictly less polished on auto-task-ingestion + status-loop axes — pick Sprite for env-capability tasks, Cursor for routine self-contained PRs.

### Cross-References

- `agent-pr-review.md` § "Push-Back-vs-Fix-Locally Matrix by Agent" — reviewer-side push-back-vs-fix calculus
- `agent-dispatch.md` § "Cursor Delegation Flow" / "Codex Delegation (`[CX]`)" — issue creation, PR review, merge gate
- `agent-dispatch.md` § "Codex Delegation (`[CX]`)" — eligibility criteria for delegation
- `critical-rules.md` § "FIX HOOK-FLAGGED ISSUES ON FILES YOU TOUCH" — touched-file scope for harness fixes
- `elixir-ci-harness` skill (claude-marketplace) — copy-ready CI workflow that closes the Codex-Cloud-no-hex.pm gap
- `feedback_codex_sandbox_pr_gap.md` — observed Codex env gaps post-allowlist
