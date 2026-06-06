---
name: linear-queue
description: Linear-as-queue issue tracking for solo and multi-repo work. Use when setting up Linear-as-queue, tracking your own (non-delegated) work in Linear, or running the workflow without cloud agents — MCP setup, workspace shape, issue-body-as-prompt template, status transitions, self-authored worktree Linear cadence, cross-repo coordination, and the ROADMAP-fallback for projects without Linear. Standalone — no cloud-agent dependency. The substrate `agent-dispatch` and `agent-pr-review` build on.
allowed-tools: Read, Grep, Glob, Bash
---

<!-- Auto-synced from ~/.claude/includes/linear-queue.md — do not edit manually -->

## Linear-as-Queue — Substrate

Linear-as-queue is cross-repo issue tracking via Linear MCP. This file is the **substrate**: MCP setup, workspace shape, the issue-body-as-prompt template, status-transition automation, the self-authored worktree flow, cross-repo coordination, and the ROADMAP-fallback for projects without Linear.

It is **standalone** — usable on its own for tracking your own (non-delegated) work, with no cloud-agent dependency. The cloud-agent delegation layers build on top of it:

- `agent-dispatch.md` — push self-contained tasks to cloud agents (Codex, Cursor)
- `agent-pr-review.md` — review and land the PRs cloud agents open
- `flow-review.md` — merge-train mode for 2+ open cloud-agent PRs

The shape here is generic — any repo can adopt it. Workspace specifics (team key, project IDs, repo↔project mapping) belong in a separate workspace include or per-repo CLAUDE.md, **not here** (see § "Workspace-Specific Layout").

### When to Adopt

> **Scope note.** Linear's first-party `@Linear` agent (Settings → AI) is a separate system. The cloud-agent delegation layers built on this substrate cover third-party cloud agents (Cursor, Codex, similar) that appear as Linear users assignable via the `delegate` field on issues.

Use Linear-as-queue when:

- **Cloud-agent delegation is in active use.** `[CX]` / `[CSR]` tasks need a queue the agent can poll; ROADMAP.md alone isn't pollable.
- **Work spans 2+ repos.** "Library release → downstream-app bump" deserves linked issues.
- **Issue state must survive across Claude sessions and the IDE.** Linear's UI/Slack/email integrations beat ROADMAP.md for staying top-of-mind.

Don't adopt when a single-repo clean ROADMAP.md is already doing the job, or the work fits in a TodoWrite session.

### MCP Registration

Linear is one workspace per user — register at **user scope**:

```bash
claude mcp add --scope user --transport http linear-server https://mcp.linear.app/mcp
```

| Scope | Behavior |
|---|---|
| `user` (recommended) | Available in every session. Single registration. |
| `local` (per-project) | Only that project sees it. |
| `project` (`.mcp.json`) | Avoid — `.mcp.json` is checked-in and shared with collaborators who may not have Linear access. |

**Tidewave parallel:** Tidewave is per-project (unique port → `.mcp.json`). Linear is one workspace serving all repos → user-scope is right; don't reflexively copy the Tidewave pattern.

Verify with `claude mcp list`. Restart Claude Code after registration if tools don't appear.

### Workspace Shape

Hierarchy: **Workspace → Teams → Projects → Issues** (+ optional Cycles, Milestones, Initiatives).

- **One team per workspace** for personal portfolios. Teams matter when multiple humans need separate workflows.
- **One project per repo.** Clean `project: <repo>` filter on every `save_issue`. Cross-repo work uses `relatedTo` between issues.
- **Workspace-wide labels** — queue selectors that the cloud-agent layers and the agents themselves filter on:
  - `cx-eligible` — Codex-eligible (used by the `agent-dispatch` layer)
  - `cursor-eligible` — Cursor-eligible (broader; hex.pm + mix tasks reachable)
  - Generic: `Bug`, `Feature`, etc.
- **Status flow** (default Linear team workflow): `Backlog` → `Todo` → `In Progress` → `In Review` → `Done` (plus `Canceled`, `Duplicate`).

**Alternative** (one mega-project + repo-tagged labels): only when project-create permissions are restricted. Cross-repo `relatedTo` story is harder; project-level filtering breaks down. Escape hatch only.

For multi-repo workspaces that delegate to cloud agents, the one-time repo-selector label setup lives in `agent-dispatch.md` § "Repo selector for multi-repo workspaces" — it's only needed once cloud-agent delegation is in flight.

### Issue Body = The Prompt

Same rule as `task-writing.md`: the body is for the consumer (a cloud agent, or a local-review session) to read and execute. Recommended sections:

```markdown
## Context
Why this exists, dependencies, what's already in place.

## Task
The thing to do, in prose. WHAT, not HOW.

## Acceptance criteria
- Bullet list a fresh QA session can verify.
- Each item is a concrete observable, not "works correctly."

## Out of scope
What this issue explicitly does NOT do.

## File paths
Anchor file:line references — reviewer's starting points.

## Scoring
[D:X/B:Y/U:Z → Eff:W] — copy the rendered bracket from the task's ROADMAP row (source: `scores = { d, b, u }` in `roadmap/tasks.toml`; `rmap` computes Eff)

## Reviewer note
Anything the local-review session needs — known gotchas, prior context, env caveats.
```

`Acceptance criteria` and `Reviewer note` are what make the issue reviewable. `audit-review`'s Step 9 cross-references the acceptance criteria post-merge and files unmet criteria as rmap follow-ups; without them, the post-merge audit can't verify the work shipped what the issue asked for. For cloud-agent-delegated issues, the plan-shaped extension of this template lives in `agent-dispatch.md` § "Plan-Shaped Linear Task Specs" — canonical path is `rmap delegate <id> --to codex|cursor` (rmap task fields → prompt sections); the hand-written 4-section template (`Files to modify` / `Files to NOT modify` / `Env constraints` / `Success criteria`) remains as the ad-hoc fallback there.

### Status Transitions

Three transitions in the delegated-PR lifecycle. Each has **one** owning mechanism — they're complementary, not overlapping.

| Transition | Mechanism | Notes |
|---|---|---|
| `Todo → In Progress` (agent picks up) | Linear AI Guidance | No GH event to hook — only the agent can drive this |
| `In Progress → In Review` (PR opened non-draft) | Linear AI Guidance | Drafts excluded — see undraft path below |
| `In Review → Done` (PR merged to default) | Native Linear GH workflow rule | Hooked to the GitHub merge event |

**Why two mechanisms.** Agent-driven (Linear AI Guidance) covers transitions that happen before a hookable GitHub event or depend on the agent's own state. GH-integration-driven workflow rules cover transitions hooked to definitive GitHub events (merge is the canonical case).

**Linear AI Guidance setup** (Settings → AI → Guidance, workspace or team scope):

> "When you pick up a Linear issue, transition its status to **In Progress**. When you open a non-draft pull request linked to a Linear issue, transition that issue's status to **In Review**. Do not flip status on PR close or merge — the GitHub integration handles the merge → Done transition."

Cursor (and any other agent reading workspace guidance) picks this up. Codex's behavior here is less verified; treat as best-effort until observed.

**Native GH workflow rule setup** (one-time, workspace admin):

1. Linear → **Workspace settings → Integrations → GitHub** → confirm the org is connected.
2. Linear → **Workspace settings → Workflow** (or Team-scoped) → enable: **PR merged to default branch** on a branch tied to an issue → status `Done`.
3. Verify with a test PR on a branch named `INE-N-…`.

**Drafts.** The "PR opened non-draft → In Review" guidance excludes drafts. If agents open PRs with `gh pr create --draft`, the transition doesn't fire until undrafted. Two complementary fixes:

- Agents stop opening drafts (set in issue body's `## Reviewer note`; `agent-dispatch.md` Cursor Delegation Flow Step 2).
- Optional `auto-undraft.yml` GH Action marks draft PRs ready when the check suite reports success — see `plugins/staged-review/templates/auto-merge.md` § 3.

**Polling as safety net.** Both mechanisms can fail to fire (agent didn't read guidance; GH event arrived during a Linear outage). `agent-pr-review.md` § "Polling for 'Ready for Review'" treats the PR attachment as the authoritative signal — agnostic to status — and is the safety net for both.

### Self-Authored Worktree Flow

Local Claude implementing a Linear-tracked task in a worktree (no cloud-agent dispatch — see `worktree-workflow.md`). Same Linear cadence as the cloud-agent delegation flows, driven by the implementer/reviewer instead of the cloud agent.

| Phase | Trigger | Linear action | Comment shape |
|---|---|---|---|
| 1. Plan-mode → Linear issue | `task-driver` `ExitPlanMode` approval | `save_issue(team, project, status: Todo, title, body: <plan>)` — no `[CX]`/`[CSR]` marker | (initial issue body) |
| 2. Pickup (worktree created) | Fresh implementer session creates worktree | `save_comment(issueId, "Picked up — worktree at ~/_DATA/worktrees/<repo>/<id>/")` + status → `In Progress` | One short line, includes the worktree path |
| 3. PR open | `gh pr create` returns | `save_comment(issueId, "PR #<n> opened: <url>")` + status → `In Review` (or rely on Linear AI Guidance) | One line, includes the PR URL |
| 4. Merge | GH-native auto-merge fires (wired at PR-open via `gh pr merge --auto`) when CI green + no requested-changes + no `[BLOCK-MERGE]` label; or user removes `[BLOCK-MERGE]` to release a held PR | `save_comment(issueId, "Merged at <sha>")` + status → `Done` (or rely on native GH workflow rule) | One line |
| 5. Audit | Next session runs `Skill(audit-review) <range>` off the SessionStart-hook signal (deferred — next session, not chained off merge); skill writes `.audit/<sha>.md` per merge SHA in range; Step 12.5 posts the canonical close-out comment | `save_comment(issueId, "Merged PR #<N>: <title>. audit(<short-sha>) landed. Acceptance criteria: N/N met. Reports: .audit/<short-sha>-<slug>.md.")` (handled by audit-review Step 12.5) | One line (audit-review writes it) |

**Posting permission:** all five rides on `delegation-rules.md` § "POST LINEAR / PR COMMENTS WITHOUT ASKING DURING DELEGATION FLOWS" — DEFAULT-DO during an active delegation flow. No per-comment user gates.

**Status transitions:** Phase 2 (`In Progress`) and Phase 3 (`In Review`) can be driven by either explicit `save_issue(stateId)` calls or Linear's native AI Guidance + GH integration if configured (§ "Status Transitions"). Phase 4 (`Done`) is owned by Linear's native GH workflow rule when configured; explicit `save_issue` only when the rule didn't fire (audit-review Step 12.5 verifies and transitions explicitly if needed).

**ROADMAP-fallback equivalent.** When Linear is absent, the same five transitions land in the worktree session's commits/PR/audit artifacts: ROADMAP row marker `⬜` → `🔄 task-N` (worktree path in row) → ✅ in the post-merge `audit(<sha>): ...` commit. No `save_comment` calls; the audit commit + `.audit/<sha>.md` is the durable trail.

### Cross-Repo Coordination

- Use `relatedTo` on `save_issue` to link issues across projects. Loose coupling — "these are about the same thing."
- Use `blocks` / `blockedBy` for hard ordering — "library release blocks downstream-app bump."
- **Don't** pile cross-repo work into one issue. Each repo owns its own PR; one issue per repo keeps PR review surface aligned with repo boundaries.

If cross-repo coordination becomes regular (3+ linked issues per month), promote to a Linear **Initiative** as a grouping overlay.

### ROADMAP-Fallback Flow (projects without Linear)

**The roadmap is source of truth in all delegation flows; Linear is a queue *view* on top.** With `rmap` the roadmap is `roadmap/tasks.toml` (rendered to `ROADMAP.md`); projects that don't use Linear — or temporarily can't reach the Linear MCP — still run the same delegation pattern via the `cx` / `csr` markers on `[[task]]` entries. New fallback tasks are filed with `rmap new --from-stdin`; the `[CX]` / `[CSR]` / `⬜` / `🔄` row notation below is rmap-rendered, not hand-typed. See `rmap.md`.

**Pickup signal without Linear:** cloud agents pick the next candidate via `rmap next --marker csr` (single best by Eff) or `rmap list --marker csr --status pending --json` (full queue view) — `csr` only while `[CX]` code-mutation is suspended (`agent-dispatch.md` § "Codex Delegation"); swap in `cx|csr` when restored. The agent reads `roadmap/tasks.toml` directly; the rendered `ROADMAP.md` is human-only. Reviewer discovers PRs via `gh pr list --state open` filtered to cloud-agent branch prefixes (`codex/`, `cursor/`). Status transitions go through `rmap status <id> in_progress|done` — executed by the pickup driver or by `audit-review` post-merge — and `rmap render` re-emits `ROADMAP.md`; **never hand-edit `ROADMAP.md` rows**. The post-merge `audit(<sha>): ...` commit on the repo's default branch carries the `rmap status` mutation alongside the re-rendered `ROADMAP.md`.

**Changes vs Linear-backed:** no `mcp__linear-server__*` calls; skip the Linear close-out step (audit-review writes `.audit/<sha>.md` as the durable trail). No Linear `@cursor` / `@codex` push-back channel — push-back goes on the GitHub PR review (line-level findings + scope paragraph in one PR comment), wake-mention discipline adapted to PR-only. No issue body — the `rmap delegate <id> --to codex|cursor` output (per `agent-dispatch.md` § "Plan-Shaped Linear Task Specs") + the project's CLAUDE.md is the agent's full context, which pushes more weight onto well-filled `body` / `acceptance_criteria` / `out_of_scope` / `files_to_modify` fields in `tasks.toml`.

**Identical:** code-only PRs, plan-shaped specs, deferred post-merge `audit(...)` commit on the repo's default branch (next session runs `Skill(audit-review)` over a range off the SessionStart-hook signal), draft-PR handling, GH-native auto-merge wire-up, bot-finding triage in audit-review Step 5d.

Use this fallback when the project hasn't onboarded Linear, when Linear is intentionally out-of-scope, or as a safety net during MCP outages. Linear is an upgrade-path, not a hard dependency.

### Workspace-Specific Layout

Team key, project list, repo↔project mapping, project IDs, worked examples are **workspace-specific** — they belong in:

- A separate `<workspace>-workspace.md` include (imported only by repos in that workspace's family), or
- The project-level `CLAUDE.md` of the repo(s) that need it.

**Not here.** This file documents the *shape* so any repo can adopt it. Workspace specifics rot fast.

### Cross-References

- `agent-dispatch.md` — the cloud-agent delegation layer built on this substrate
- `agent-pr-review.md` — reviewing the PRs cloud agents open
- `flow-review.md` — merge-train mode for 2+ open cloud-agent PRs
- `task-writing.md` — body-as-prompt principle; plan-shape vs roadmap-shape distinction
- `rmap.md` — the roadmap substrate; `roadmap/tasks.toml` is canonical and `ROADMAP.md` is rendered. Fallback-flow task filing uses `rmap new --from-stdin`
- `worktree-workflow.md` — the worktree mechanics the Self-Authored Worktree Flow rides on
- `workflow-philosophy.md` § "Implementer / Reviewer Handoff" — the handoff shape Linear+worktree implements
- `delegation-rules.md` § "POST LINEAR / PR COMMENTS WITHOUT ASKING DURING DELEGATION FLOWS" — comment-posting permission for the self-authored flow
- `staged-review:audit-review` skill — deferred post-merge hygiene + bookkeeping; SessionStart hook surfaces unaudited tails, next session runs `Skill(audit-review) <range>` to batch-clear
