---
name: dev-lifecycle
description: Use when explaining or orienting around the development lifecycle — answers "which phase am I in?", "which skill owns this?", "what's the handoff between phases?". Canonical reference for the five-phase chain (task-driver → worktree → bots → merge → audit-review; Phase 4 merge is GitHub-native `gh pr merge --auto`) that composes the task-driver, staged-review, and cloud-delegation plugins. Pure documentation — no actions taken.
allowed-tools: Read, Grep, Glob, Bash
---

<!-- Auto-synced from ~/.claude/includes/dev-lifecycle.md — do not edit manually -->

# Five-Phase Development Lifecycle

The `task-driver` + `staged-review` + `cloud-delegation` plugins compose into a five-phase lifecycle from task plan to merged-and-audited code. Same 5+1 category catalog across the two Claude-driven review layers (`code-review` pre-commit + `audit-review` post-merge); each phase has a single owning skill / actor:

```
task-driver(1) → worktree(2) → bots(3) → merge(4: GH-native gh pr merge --auto) → audit-review(5)
```

| Phase | Skill / Actor | When | Linear status on exit |
|---|---|---|---|
| 1. Plan-and-File | `task-driver` (Plan-and-File mode — plan → `ExitPlanMode` → `save_issue`) | User asks to plan new work | `Todo` |
| 2. Implement | implementer session in a worktree (per `worktree-workflow.md`) — pre-commit triage by `code-review` (sub-phase, `git diff --staged`) | Fresh session picks up the issue / task | `In Progress` (pickup) → `In Review` (PR open) |
| 3. Bots | external (CodeRabbit, Copilot, Codex's GitHub bot) | Async on PR open | (no transition) |
| 4. Merge | GitHub-native `gh pr merge <N> --auto --squash --delete-branch` — set when PR opens; fires on all required checks green + no requested-changes + no `[BLOCK-MERGE]` label. Zero-Claude / zero-cloud-agent pre-merge. | All required CI checks pass + no requested-changes + no `[BLOCK-MERGE]` label | `Done` if Linear's native GH workflow rule is configured and fires; otherwise audit-review (Phase 5) confirms via `get_issue` and transitions explicitly |
| 5. Post-merge audit | `audit-review` — full 5+1 categories, mandatory parallel Codex, Claude+Codex dialogue on `discuss-design`, bot-comment triage (Step 5d), acceptance-criteria cross-reference (Step 9), Linear close-out (Step 12.5), auto-applies hygiene fixes, writes `.audit/<sha>.md`, commits as `audit(...)` | Deferred — `staged-review` SessionStart hook surfaces unaudited tails (≥3 commits); next session reads the surfaced tail and runs `Skill(audit-review) <range>` to batch-clear (`/staged-review:audit-status` is the read-only snapshot path the user can run if they want a peek) | `Done` (confirmed) |

**Reviewer cost-shape: dual-reviewer at the audit layer only; pre-merge is zero-Claude.** The expensive parts of the review (parallel Codex dispatch with full tool-inventory payload, Claude+Codex dialogue resolution on judgment-call items) live exclusively in Phase 5 (`audit-review`). Phase 2 sub-phase (`code-review`) stays fast and single-reviewer. Phase 4 (merge) is GH-native — no Claude or cloud-agent invocation. Every merged commit reaches the dual-reviewer pass via Phase 5 when next session's audit pass runs — batched over a range, the dual-reviewer cost amortizes across N merges instead of paying it N times.

**Linear is optional.** Projects without Linear use the ROADMAP-fallback flow: Phase 1 files an `rmap` task (`rmap new --from-stdin` into `roadmap/tasks.toml`) + `.thoughts/plans/<id>.md`; Phase 2–5 carry on identically; Linear-status columns above are skipped. The roadmap is rmap-backed in both modes — `roadmap/tasks.toml` canonical, `ROADMAP.md` rendered (see `rmap.md`). See `linear-queue.md` § "ROADMAP-Fallback Flow".

**Language-agnostic by design.** Every phase composes skills from the three already-language-agnostic plugins (`task-driver`, `staged-review`, `cloud-delegation`) plus the `worktree-workflow.md` include. No mix/cargo/npm-specific commands appear in the chain. Elixir-specific gates (`mix test.json`, `mix dialyzer.json`, pre-commit hooks) live in the `elixir` plugin and run alongside but are not part of the lifecycle itself.

## End-to-end flow for a typical feature task

1. **Phase 1** — User asks to plan something. `task-driver` enters Plan-and-File mode: research → draft plan → `EnterPlanMode` → on `ExitPlanMode` approval, `save_issue(status: Todo)` (or `rmap new` task if no Linear). Returns issue URL / rmap task id. **Stops.**
2. **Phase 2** — Fresh implementer session picks up the issue. Creates worktree under `~/_DATA/worktrees/<repo>/<id>/`. Implements. Stages with `git add`. **Pre-commit triage** (sub-phase): `code-review` reviews `git diff --staged` against all 5+1 categories — single-reviewer triage. On approval, commits. Pushes. Opens PR with `gh pr create`. **Same step also runs `gh pr merge <N> --auto --squash --delete-branch`** to wire up GH-native auto-merge. (All git ops auto-allowed inside the tracked worktree per `worktree-workflow.md`.)
3. **Phase 3** — Bots (CodeRabbit, Copilot, Codex's GitHub bot) run async on PR open. No skill action; their findings are triaged post-merge in Phase 5 Step 5d.
4. **Phase 4** — **GitHub-native auto-merge.** GitHub holds the merge until all required checks pass (CI green + `block-merge-gate / gate` clean — i.e. no `[BLOCK-MERGE]` label) AND no requested-changes review state. Zero Claude / zero cloud-agent invocation pre-merge. To hold a PR for manual review, add the `[BLOCK-MERGE]` label; remove to release. Applies to all feature-branch PRs (worktree branches, `cursor/*`, `codex/*`). Full adoption guide: `plugins/staged-review/templates/auto-merge.md`.
5. **Phase 5** — `audit-review` runs deferred. The `staged-review` SessionStart hook surfaces unaudited tails (≥3 commits past the last `audit(...)` ancestor); next session reads the surfaced tail and runs `Skill(audit-review) <range>` to batch-audit (`/staged-review:audit-status` is the read-only snapshot path if the user wants a peek). Full 5+1, mandatory Codex, auto-resolves `discuss-design` via Claude+Codex dialogue. New steps: Step 4.5 resolves each commit's source PR + fetches PR / Linear comments; Step 5d triages bot findings (3-reasoner table: Claude / Codex / bots); Step 9 cross-references Linear acceptance criteria; Step 12.5 closes out Linear issues at the batch tail. Writes one `.audit/<sha>.md` per commit. Commits as `audit(...)` on the default branch. Linear status confirms `Done`.

**Implementer / reviewer separation** is preserved across the chain: `task-driver` files plans but doesn't implement (handoff to fresh-session implementer), the implementer stages but `code-review` commits (handoff to fresh-session reviewer), `code-review` commits but GitHub ships (handoff to GH-native auto-merge — no agent self-grades the merge gate), and `audit-review` bookkeeps post-merge in the next session's audit pass. Each phase is a different session (or, for Phase 4, no session) — no agent grades its own work.

## Where each phase lives

| Phase | Skill / Actor |
|---|---|
| 1 — Plan-and-File | `task-driver:task-driver` (Plan-and-File mode) |
| 2 — Implement | implementer session + `staged-review:code-review` (pre-commit sub-phase) |
| 3 — Bots | external (CodeRabbit, Copilot, Codex's GitHub bot) |
| 4 — Merge | GitHub-native `gh pr merge --auto --squash --delete-branch` (set when PR opens; fires on required checks green + no requested-changes + no `[BLOCK-MERGE]` label) OR user manual `gh pr merge` |
| 5 — Post-merge audit | `staged-review:audit-review` |

Worktree mechanics + git auto-allow scoping: `worktree-workflow.md`. Push-back posting matrix: `agent-pr-review.md` § "Push-Back-vs-Fix-Locally Matrix by Agent". Linear-status transitions: `linear-queue.md` § "Status Transitions". Auto-merge precondition rules: `delegation-rules.md` § "DON'T AUTO-MERGE PRS". GH-native auto-merge adoption guide: `plugins/staged-review/templates/auto-merge.md`.
