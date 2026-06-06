---
name: agent-dispatch
description: Dispatch self-contained tasks to cloud agents (Codex, Cursor) via Linear or ROADMAP markers. Use when delegating ROADMAP tasks to a cloud agent — Codex/Cursor delegation flows, per-agent eligibility filtering, plan-shaped issue specs, code-only-PR acceptance criteria, batch sizing, pre-flight file-conflict detection, honest-gap discipline. Builds on `linear-queue`; pairs with `agent-pr-review`.
allowed-tools: Read, Grep, Glob, Bash
---

<!-- Auto-synced from ~/.claude/includes/agent-dispatch.md — do not edit manually -->

## Cloud-Agent Dispatch

The **dispatch layer** of the Linear-as-queue workflow — pushing self-contained tasks to cloud agents (Codex, Cursor) for implementation.

It builds on `linear-queue.md` (the substrate: MCP setup, workspace shape, issue-body template, status transitions). Read that first if Linear-as-queue isn't set up yet. The return path — reviewing the PRs cloud agents open — is `agent-pr-review.md`; multi-PR merge orchestration is `flow-review.md`.

> **rmap note.** The `[CX]` / `[CSR]` delegation markers and `⬜` / `🔄` statuses throughout this file are *rendered* `ROADMAP.md` notation — the source is the `cx` / `csr` markers and `pending` / `in_progress` status on `[[task]]` entries in `roadmap/tasks.toml`. Pick delegation candidates with `rmap next --marker cx|csr` or `rmap list --marker csr --status pending --json`. `rmap delegate <id> --to codex|cursor` is the **canonical way to render a task into a cloud-agent prompt** — its output IS the Linear issue body (see § "Plan-Shaped Linear Task Specs"). See `rmap.md`.

### Repo selector for multi-repo workspaces

When one Linear workspace serves multiple cloud-agent-targeted repos, Cursor needs an explicit signal which on-disk repo to clone. Cursor's documented selector priority (cursor.com/docs/integrations/linear):

1. `[repo=owner/repository]` syntax in the issue body or any later comment
2. Issue-scope labels matching `<org>/<repo>` against connected GitHub repos
3. Project-scope labels matching the same pattern
4. Cursor dashboard default repo

**Recommended pattern:** workspace-wide label group `repo` with one child label per repo, attached at issue scope.

- Create a workspace label group named `repo` once (Linear UI → Workspace settings → Labels → New group). Add one child label per connected GitHub repo, named `<org>/<repo>` exactly.
- **Per-repo onboarding** (one-time, before the first delegated issue):
  1. Verify: `mcp__linear-server__list_issue_labels(name: "<org>/<repo>")`.
  2. If missing: `mcp__linear-server__create_issue_label(name: "<org>/<repo>", parent: "repo")`. Omit `teamId` for workspace scope.
  3. Record the returned label id in the workspace-specific include's "Repo Selector Labels" table.
- On every delegated issue, attach `cursor-eligible` (or `cx-eligible`) AND the matching `<org>/<repo>` label.

**Silent-drop failure mode.** If `<org>/<repo>` doesn't exist, `save_issue` accepts the name and silently drops it from the response. Cursor then falls back to its dashboard-default repo (silent miscluster). Recovery: cancel-and-refile after running the onboarding step.

**Known gap:** project-scope label attachment via MCP doesn't currently persist — route via issue-scope labels only; the body-syntax `[repo=owner/repository]` is the documented escape hatch.

### Cloud Agent Environments

For agent envs (hex.pm, mix tasks, Tidewave, external HTTP availability per agent), see `cloud-agent-environments.md`. Eligibility recap: `[CX]` is code-mutation suspended; `[CSR]` covers hex.pm verification, mix-task validation, third-party API correctness, AND Tidewave / live-runtime tasks (Tidewave reachable on Cursor via `curl localhost:<port>/tidewave/mcp`; native `CallMcpTool` requires pre-session start).

### Delegation Eligibility Filter Order

Apply these filters **in order** when picking ROADMAP tasks to delegate. The first filter that excludes a task ends evaluation — don't argue past a hard constraint to backfill a queue (see § "Honest-Gap Discipline").

1. **Codex code-mutation suspended (workspace-wide)** → `[CX]` candidates redirect to `[CSR]`. Marker stays in ROADMAP for traceability; actual delegation goes to Cursor. Single-pass — apply once per session.
2. **Per-agent cloud-env constraints** — consult `cloud-agent-environments.md` (hex.pm, mix tasks, Tidewave, HTTP). Project-specific overrides may further exclude tools. Tasks needing unreachable tools stay LOCAL.
3. **Sibling-repo 🔶 blockers** — tasks blocked on un-released changes in a sibling repo stay 🔶. Re-check on each delegation pass.
4. **Survivors → batch candidates** — feed into § "Batch Sizing and Pacing".

### Codex Delegation (`[CX]`)

> **🚨 Suspended (Elixir projects).** Codex Cloud can't run `mix` tasks — Erlang/Elixir are pre-installed but off-PATH and `hex.pm` returns 403 through the proxy, so no harness evidence is possible. Review-only `[CX]` is also disabled (polling-race failure mode; bot ensemble already covers correctness). Do not create new `[CX]` issues of either flavor — route to `[CSR]` (Cursor). See `cloud-agent-environments.md` § "Codex Cloud → Code-mutation delegation SUSPENDED" for the path back. Criteria below describe what `[CX]` *would* mean if/when delegation resumes.

**When restored:** flow mirrors the Cursor Delegation Flow below — `team` / `project` / `labels: ["cx-eligible", "<org>/<repo>"]` / `delegate: "Codex"` / status `Todo` / body = `rmap delegate <id> --to codex` output (see § "Plan-Shaped Linear Task Specs"). Agent wires GH-native auto-merge at PR-open (`gh pr merge <N> --auto --squash --delete-branch`); GitHub gates the merge against branch protection (CI green + no requested-changes + no `[BLOCK-MERGE]` label — see `delegation-rules.md` § "DON'T AUTO-MERGE PRS"); `audit-review` runs deferred (SessionStart hook flags it).

**Marker semantics.** Mark ROADMAP tasks suitable for Codex delegation with `[CX]`. **Default: tasks meeting all criteria are `[CX]` unless there's a stated reason otherwise.** Claude's bias is to grab work; this default is a counterweight.

**Criteria (all must be true):**

- Self-contained — single module or feature, no orchestration with other in-flight work
- No Tidewave / live-data exploration required (Codex has no internet)
- No hex-docs lookup required for niche or version-pinned APIs (Codex has no hex.pm)
- No dependency changes (`mix.exs`, lockfile)
- No `.mcp.json`, hooks, or CI changes
- Spec is fully captured in the Linear issue body — no live clarifications mid-flight

ROADMAP row examples:

```
| Task 80 `[CX]` | ⬜              | Delegate to Codex                  |
| Task 81 `[CX]` | 🔄 in-review   | Codex PR open, awaiting review     |
```

### Cursor Delegation Flow

Same shape as the Codex flow with **broader eligibility** — Cursor's cloud env reaches hex.pm and runs `mix` tasks (see § "Cloud Agent Environments").

1. **Create issue** with `team`, `project: <repo>`, `labels: ["cursor-eligible", "<org>/<repo>"]` (skip the second label in single-repo workspaces), `delegate: "Cursor"`, **body = `rmap delegate <id> --to cursor` output** (see § "Plan-Shaped Linear Task Specs"; for one-off tasks not worth tracking in `tasks.toml`, fall back to § "Ad-hoc plan-shaped template"), initial status `Todo`.

   `assignee` and `delegate` are independent fields — an issue can have a human assignee AND a cloud-agent delegate simultaneously. Cursor and Codex watch `delegate`; pickup does not require the agent to also be assignee.

2. **Cursor picks it up.** Background Agent transitions `Todo` → `In Progress`, opens a non-draft PR, transitions to `In Review`. Status often stays at `In Progress` (partial-transition failure mode) — don't rely on `In Review` as the readiness signal; PR attachment is authoritative (`agent-pr-review.md` § "Polling for 'Ready for Review'"). **Canonical fix:** `linear-queue.md` § "Status Transitions". **Required:** Cursor's `gh pr create` should NOT use `--draft` — the AI-Guidance "PR opened non-draft → In Review" rule (`linear-queue.md` § "Status Transitions") only fires for non-draft PRs. State this in the issue body's `## Reviewer note`.

   **Same step also wires up auto-merge.** Immediately after `gh pr create`, the agent runs `gh pr merge <N> --auto --squash --delete-branch`. GitHub queues the merge for when all required checks pass + no `[BLOCK-MERGE]` label. Pre-merge phase is zero-Claude / zero-cloud-agent (see `plugins/staged-review/templates/auto-merge.md`). State this in the issue body's `## Reviewer note`.

3. **Cursor self-validates** — `mix test.json --quiet`, `mix credo --strict`, `mix format --check-formatted`, targeted `mix test test/...`. PRs ship harness-green from Cursor's side. CI re-runs the same checks; `audit-review` (deferred, post-merge) does the 5+1-category audit + acceptance-criteria cross-reference. Pre-merge is zero-Claude.

4. **Push back via Linear comment with `@cursor` mention.** Cursor picks up `@cursor` mentions within ~5 min, amends the PR with a fresh commit, posts confirmation, reruns the harness. See `agent-pr-review.md` § "Wake-Mention Discipline" for placement rules.

5. **GH-native auto-merge** (preconditions in `delegation-rules.md` § "DON'T AUTO-MERGE PRS"). `--auto` was wired in step 2; GitHub merges when all required checks pass (CI green + `block-merge-gate / gate` clean) AND no requested-changes review state. Tail ends at branch cleanup; `audit-review` runs deferred (SessionStart hook surfaces unaudited tails; next session batch-clears via `Skill(audit-review) <range>`). To hold a PR for manual review, add the `[BLOCK-MERGE]` label.

### Plan-Shaped Linear Task Specs

**Linear specs handed to cloud agents are plan-shaped, not roadmap-shaped.** Same prompt-vs-plan split as `task-writing.md`: ROADMAP rows are durable cross-instance prompts (vague enough to survive codebase changes); a Linear task delegated to a cloud agent is a single-shot consumer — same shape as a `/plan` file.

Cloud agents do NOT carry context across sessions. Each pickup is a fresh session that reads the issue body once, implements once, and stops. Roadmap-shaped vagueness — "add X to the auth module" — burns round-trips; the agent has to rediscover paths, contracts, and conventions each round.

**Canonical path — `rmap delegate <id> --to codex|cursor`.** Per the rmap mandate, every project's tasks live in `roadmap/tasks.toml`. `rmap delegate` renders a task as a paste-ready cloud-agent prompt with these sections in order:

- `## Context` — target / project / status / phase / bundle (+ milestone, model if set)
- `## Task` — the task `body` verbatim (the WHAT, prose; see `task-writing.md`)
- `## Acceptance criteria` — the `acceptance_criteria` field as a checkbox list
- `## Out of scope` — the `out_of_scope` field (only if set)
- `## Scoring` — `[D:N/B:N/U:N → Eff:N]` bracket + tier glyph
- `## Environment notes` — per-target boilerplate (Codex offline + no-toolchain caveats; Cursor caveats)
- `## Instructions` — repo-inspection, scope-discipline, test/verification expectations

**The flow:** run `rmap delegate <id> --to cursor` (or `--to codex` when restored), then paste the output into the Linear issue body verbatim. No hand-editing — drift between rmap spec and issue body is exactly what this replaces.

**Field encoding — how to make the prompt load-bearing.** The four sections that used to be hand-written (`Files to modify` / `Files to NOT modify` / `Env constraints` / `Success criteria`) become rmap task fields. Set them at `rmap new --from-stdin` time:

> **Note on `files_to_modify`.** `rmap delegate` does not yet render `files_to_modify` as its own `## Files to modify` section — surface the file list inline in `body` for the agent to read. Set the `files_to_modify` field anyway: it's the load-bearing input for § "Pre-Flight Conflict Detection" and for the file-overlap matrix in `flow-review.md`.

| Plan-shaped concern   | rmap task field        | Surfaces in `rmap delegate` output as       |
|-----------------------|------------------------|---------------------------------------------|
| Files to modify       | `files_to_modify`      | not yet rendered — encode in `body`; see note above |
| Files to NOT modify   | `out_of_scope`         | `## Out of scope`                            |
| Env constraints       | (per-target boilerplate auto-emitted; project-specific in `body`) | `## Environment notes` + body context |
| Success criteria      | `acceptance_criteria`  | `## Acceptance criteria` (checkbox list)     |

Skip any of these and the agent fills the gap with assumptions — usually wrong ones that cost a round-trip. The fields are load-bearing for the same reason the hand-written sections were; they just now live in `tasks.toml` instead of an ad-hoc Linear template.

**Pre-flight check.** Before submitting a batch of N≥2 plan-shaped issues, run § "Pre-Flight Conflict Detection" — the `files_to_modify` field across the batch IS the input. For tasks that don't yet have the field set, populate it (or encode the file list in `body` and surface it via `rmap show <id>`) before batching.

#### Ad-hoc plan-shaped template

For one-off cloud-agent dispatches not worth tracking in `tasks.toml` (rare — most work should land as an rmap task first), hand-build the prompt with these sections appended to `## Context` / `## Task` / `## Acceptance criteria` (from `linear-queue.md` § "Issue Body = The Prompt"):

```markdown
## Files to modify
- `lib/foo/bar.ex` — add function `do_thing/2` with spec `(integer(), Keyword.t()) :: {:ok, term()} | {:error, atom()}`
- `test/foo/bar_test.exs` — assert success path + 2 error paths (`:invalid_input`, `:not_found`)

## Files to NOT modify
- `ROADMAP.md`, `CHANGELOG.md`, `README.md` (`audit-review` updates these post-merge in one `audit(...)` commit)
- `.sobelow-skips` (auto-regenerated; `audit-review` applies regen in the same `audit(...)` commit)

## Env constraints
- Codex Cloud: no hex.pm, no Tidewave, no internet. Use stdlib + already-installed deps.
- Cursor Cloud: hex.pm + internet OK; mix tasks OK. Tidewave reachable via `curl localhost:<port>/tidewave/mcp` (always); native `CallMcpTool` only if Tidewave was running before session start (see `cloud-agent-environments.md` § "Tidewave on Cursor").

## Success criteria
- `mix test.json --quiet --failed` returns 0 failures on touched files
- `mix credo --strict` shows 0 issues
- `mix dialyzer` 0 warnings
- Full harness green per § "Code-Only PRs + Required Acceptance Criteria"
- PR title includes `(INE-N)`; PR opened non-draft (see `linear-queue.md` § "Status Transitions")
```

If you find yourself reaching for the ad-hoc template repeatedly, that's a signal the work should be filed as an rmap task instead — `rmap new --from-stdin` covers the same fields and feeds `rmap delegate` on every subsequent dispatch.

### Code-Only PRs + Required Acceptance Criteria

**Cloud-agent PRs touch code + tests only.** They do NOT modify `ROADMAP.md`, `CHANGELOG.md`, `README.md`, or `.sobelow-skips`. These files are owned by `staged-review:audit-review` and updated in a single `audit(...)` commit on the repo's default branch in the deferred audit pass (next session, off the SessionStart-hook signal).

**Why centralize.** Shared-doc edits across parallel PRs hit merge conflicts (`mergeable: CONFLICTING`, `mergeStateStatus: DIRTY`) against earlier merges — every PR adds a rebase round just to resolve doc conflicts. One reviewer-owned commit per audit pass eliminates the conflict class.

**How to apply.** In the issue body's `## Out of scope`, list the files explicitly:

> Out of scope: `ROADMAP.md`, `CHANGELOG.md`, `README.md`, `.sobelow-skips`. Reviewer (`staged-review:audit-review`, deferred post-merge pass) updates these on the repo's default branch.

**Required acceptance-criteria bullet** (every delegated issue's `## Acceptance criteria` MUST include this; do NOT add doc-update bullets):

- **Full harness green at PR open** — `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict` (TODO/FIXME exit-2 carve-out only), `mix sobelow --exit Low`, `mix doctor`, `mix test.json --quiet`, `mix test.json --cover --cover-threshold N` at the repo's coverage tier, `mix dialyzer` all clean. CI runs the same checks. A red harness on PR open is a blocking acceptance-criterion miss.

**Audit-review owns the post-merge commit.** Auto-merge ends at branch cleanup; audit-review runs deferred. The `staged-review` SessionStart hook flags accumulated unaudited commits (≥3 threshold) next session; next session runs `Skill(audit-review) <range>` to batch-audit. The skill runs the 5+1-category audit, dispatches mandatory Codex second-opinion, auto-applies hygiene fixes (ROADMAP row → ✅ preserving `[CX]` / `[CSR]` marker, CHANGELOG entry under `## [Unreleased]`, README/CLAUDE.md drift, in-code `@doc`/`@spec` fixes), and writes one `.audit/<sha>.md` per audited commit. Lands as one `audit(<audit-sha>): N fixes — dual-reviewer pass` commit covering the whole range, on the repo's default branch.

**`.sobelow-skips` exception:** for repos with sobelow line-fingerprint drift, the harness fails-loud-with-diff if drift is detected; audit-review applies the regen when the deferred pass runs, folded into the same `audit(...)` commit. Agent never touches the file.

### Batch Sizing and Pacing

This section is the delegation-specific instance of `workflow-philosophy.md` § "Batched Execution" — the general form covers in-session subagent fan-out too. Vocabulary ("batch") originates here; the canonical rule generalizes the discipline (disjoint work fans out; `⏸ CHECKPOINT` / `/compact` is the inter-batch STOP marker).

How to shape a delegation batch upstream of pre-flight conflict detection. Pre-flight checks file-scope collision; this section answers what should be in the batch.

**2+1+1 splits over single mega-batches.** When in doubt about whether 4-5 issues are too much, prefer two smaller batches. Smaller batches reduce review surface, reduce file-scope collision risk, let the user `/compact` between firings.

**Bundle multiple ROADMAP tasks into one Linear issue ONLY when all three hold:** shared module (single PR diff is the natural unit), same critical-tier gate (≥80% standard or ≥95% critical — don't mix), same fix shape (e.g. "add nil-guard + flunk on unexpected" applied to two functions with the same signature). If structurally different, file standalone.

**Pause for `/compact` between batches.** Each batch (2-5 issues) is the natural compact checkpoint. Surfacing the deployed batch list to the user IS the compact prompt — don't fire a second batch in the same context window.

**Parallelism.** One Cursor agent per repo at a time is fine; 4+ in flight is also fine, **IFF** each issue carries its own branch and the file-scope matrix returns no overlaps. Constraint is file-scope, not agent count.

**How to apply:**

1. Pick candidate ROADMAP tasks (after § "Delegation Eligibility Filter Order").
2. Group by shared-module + same-tier + same-fix-shape.
3. Run pre-flight conflict detection on the proposed batch.
4. If batch ≥ 4 issues, default to splitting. Surface the split shape (e.g. "2+1+1") before firing.
5. After firing, pause for `/compact` before the next batch.

### Pre-Flight Conflict Detection (Batch Delegation)

**The bottleneck.** N parallel cloud-agent PRs touching a shared coordination file (top-level registry, mix.exs, router) make every merge invalidate the others' base SHAs — delegation cost (merge lag, rebase churn) easily exceeds per-task local effort.

**The check.** Before any `mcp__linear-server__save_issue` that creates a delegated issue, scan the existing open queue + candidate set for file-overlap on coordination-tier files (consuming the `## Files to modify` block from § "Plan-Shaped Linear Task Specs"). Triggers: a batch of N≥2 candidate delegated issues being created this session, OR a single new delegated issue when ≥2 open delegated issues already exist in `Todo` / `Backlog`.

**Mechanism:**

```
filter (existing queue):
  project = <current>
  status ∈ { Todo, Backlog }
  delegate ∈ { Codex, Cursor }

then:
  parse `## Files to modify` from each issue body (existing + candidates)
  build a touch matrix: file → [issues touching it]
  classify each shared-file overlap:
    coordination-tier  if file ∈ project's coordination set
    ordinary           otherwise
```

**Coordination-tier signals** (project-overridable):

- `lib/<app>.ex` — top-level public API / registry module
- `mix.exs` — deps, version, aliases
- `config/config.exs`, `config/runtime.exs` — config registry
- `lib/<app>_web/router.ex` — Phoenix route registry
- `lib/<app>/application.ex` — supervisor children list
- Any file appearing in 3+ historical merged PRs (run `flow-stats.sh` — see `agent-pr-review.md` § "Tooling")

**Decision tree on overlap (priority order):**

1. **(a) Isomorphic tasks + shared coordination file** → recommend **bundle into 1 issue** ("annotate all N modules in one PR"). One PR, registry edited once, no fan-out.
2. **(b) Real overlap, non-isomorphic, coordination cost <30% of total task effort** → **extract a serializer issue**. Peer issues touch only their own files; the serializer (final in chain) does the registry edit and is `blockedBy` all peers.
3. **(c) Small per-task effort (<30 min) AND batch ≥4 AND any shared file** → **do locally**. Local sequential beats parallel-cloud-agent under these conditions.
4. **(d) No conflict, OR overlap only on non-coordination files** → proceed with N parallel issues.

**Worth-it heuristic.** Delegation pays when per-task effort ≥ 30 min OR batch local-effort ≥ 90 min AND tasks are independent or restructurable. Local Claude wins under any of: per-task < 30 min AND batch ≥ 4 AND any shared coordination file; OR total batch local-effort < 90 min regardless of overlap (Cursor startup + first-push round is ~10 min, so 60-min batches barely break even).

Output is **always a recommendation + decision request** — workflow surfaces the touch matrix and recommended action; user chooses bundle / serializer / local / proceed-anyway.

### Honest-Gap Discipline (Queue Dry)

**When § "Delegation Eligibility Filter Order" drains the queue to zero, surface the gap explicitly with these four paths and let the user pick. Never silently fabricate a batch from non-eligible tasks just to keep the queue full.**

The four paths:

1. **Wait** — keep the queue empty until ROADMAP gets new candidates or in-flight PRs land (often unblocks dependents).
2. **Pivot LOCAL** — pull the next-highest-Eff ROADMAP task into the local session. Often correct when filter 2 (env constraint) drained the queue.
3. **Cross-repo** — check sibling-repo ROADMAPs for delegatable tasks. The user's queue is broader than one repo.
4. **Review-mode** — inspect in-flight cloud-agent PRs via `gh pr view` / `gh pr diff`; if any warrant a manual hold, add the `[BLOCK-MERGE]` label and review per `agent-pr-review.md` § "Review Tiering". Audit-review picks up the rest post-merge.

Same shape as `critical-rules.md` § "NO EVASION — SIT WITH THE HARD THING": when the easy path violates a constraint, sit with it, name it, ask. The failure mode this prevents: reaching past the eligibility filter to backfill the queue with tasks that violate filter 2 or 3 — e.g. delegating a dialyzer-required task to a cloud agent whose VM OOMs on dialyzer "because nothing else is available."

**How to apply.** After the eligibility filter, if zero tasks survive, STOP. Don't loop back to relax filter 2. Surface the gap with the four paths in one short message (one line per path). Wait for the user's pick. Don't pre-execute one as a "safe default."

### Cross-References

- `workflow-philosophy.md` § "Batched Execution" — the canonical generalization of § "Batch Sizing and Pacing"; covers in-session subagent fan-out batches too
- `linear-queue.md` — the substrate this builds on (MCP setup, workspace shape, issue-body template, status transitions)
- `agent-pr-review.md` — the return path: reviewing the PRs cloud agents open
- `flow-review.md` — merge-train mode for 2+ open cloud-agent PRs
- `cloud-agent-environments.md` — per-agent env reference (hex.pm, mix tasks, Tidewave, HTTP)
- `delegation-rules.md` § "DON'T STEAL CLOUD-AGENT-DELEGATED TASKS", § "DON'T AUTO-MERGE PRS"
- `plugins/staged-review/templates/auto-merge.md` — GH-native auto-merge adoption guide (branch protection, `block-merge-gate.yml`, optional auto-undraft action); the canonical reference for the `gh pr merge --auto` step in the Cursor Delegation Flow
- `task-writing.md` — body-as-prompt; plan-shape vs roadmap-shape distinction
- `task-prioritization.md` § "Ceremony Floor" — review-time cost-benefit gate; § "Pre-Flight Conflict Detection" here is the delegation-time analogue
- `critical-rules.md` § "NO EVASION — SIT WITH THE HARD THING" — the discipline Honest-Gap mirrors
- `rmap.md` — the roadmap substrate; delegation markers and statuses in this file are rendered `roadmap/tasks.toml` notation, and `rmap delegate` formats a task as a cloud-agent prompt
