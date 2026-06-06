---
name: flow-review
description: Merge-train mode for 2+ open cloud-agent PRs. Use when multiple delegated PRs are queued and per-PR rebase round-trips exceed review time — polls open cloud-agent PRs, classifies by tier and mergeability, dependency-sorts by file-overlap, runs the rebase cascade between merges. Invoked by 'run flow-review'. Composes `agent-pr-review` for per-PR Tier-2 handoff.
allowed-tools: Read, Grep, Glob, Bash
---

<!-- Auto-synced from ~/.claude/includes/flow-review.md — do not edit manually -->

## flow-review — Merge-Train Mode

`flow-review` is **merge-train mode** — batch orchestration for 2+ open cloud-agent PRs.

It composes `agent-pr-review.md` (per-PR manual-hold review, the polling shape, the tier matrix) on top of `linear-queue.md` (the substrate) and `agent-dispatch.md` (how the PRs in the train got delegated).

### Invocation

Workflow-only — no CLI, no skill wrapper beyond this one. Triggered by user request ("run flow-review") or in-session decision once 2+ cloud-agent PRs are open in the current repo. The bottleneck it solves: each merge advances the default branch and invalidates every other PR's base SHA, so per-PR rebase round-trips surface phantom conflicts in untouched files. With 3+ PRs queued, rebase tax exceeds review time.

### What `flow-review` does

1. **Polls** all open cloud-agent PRs in the current repo (filter from `agent-pr-review.md` § "Polling for 'Ready for Review'", scoped to current repo + extended to include `mergeStateStatus`).
2. **Classifies** each PR by tier (per `agent-pr-review.md` § "Review Tiering: When to Hold for Manual Review") and mergeability (CI green | red | conflicting | bot-flagged).
3. **Dependency-sorts** the queue from a directed graph built on file-overlap (parsed from `## Files to modify` of each PR's source issue) + Linear `blockedBy` / `relatedTo`. PRs touching only their own files merge first; coordination-file PRs last. Sort by PR age within each layer.
4. **Surfaces** the ordered queue with per-PR action recommendations.
5. **Executes** the rebase cascade between merges. User owns merges; reviewer owns rebases.

### Tier-based action matrix

| Tier | CI | Bots | Conflicts | Action |
|---|---|---|---|---|
| Ceremony | green | clean | none | GH-native auto-merge (wired at PR-open via `gh pr merge --auto`) fires; audit-review is deferred (runs once at end of train) |
| Standard | green | clean | none | Same as ceremony, plus optional 5-min skim if any bot finding |
| Critical | green | clean | none | Add `[BLOCK-MERGE]` label to hold; manually review per `agent-pr-review.md` § "Review Tiering" (four-role framing); push back inline; remove label when ready to ship |
| Any | red | — | — | Surface for human triage; skip in current pass |
| Any | — | — | conflicting/behind | Trigger rebase cascade (below) |
| Any | — | flagged | — | Surface bot finding for triage (push-back vs. defer) |

### Rebase cascade

After the user runs `gh pr merge` on PR #N:

```
for each remaining PR in dependency order:
  if PR.mergeStateStatus ∈ { BEHIND, DIRTY }:
    git fetch && git checkout <agent-branch>
    git rebase origin/<default-branch>
    if conflicts:
      attempt mechanical resolution (see invariants)
      if mechanical resolution succeeds:
        git push --force-with-lease
      else:
        git rebase --abort
        post Linear @cursor / @codex comment with conflict context
        skip this PR (agent picks up the rebase)
    else:
      git push --force-with-lease
    wait for CI re-run; loop
```

**Rebase-only carve-out invariants.** This carve-out is one of the two authorized exceptions to `delegation-rules.md` § "NEVER PUSH TO A CLOUD-AGENT'S BRANCH"; the invariants below are the canonical statement of it. Strict; do not relax.

- **Allowed:** `git rebase origin/<default>` + `git push --force-with-lease` to the cloud-agent branch.
- **Mechanical-resolution test:** post-rebase diff vs. pre-rebase diff (against the new merge base) MUST be byte-identical except inside conflict regions. Verify with `git diff <pre-rebase-tip>..HEAD -- <files-not-in-conflict>` returning empty.
- **Mechanical resolutions allowed:** alphabetical/sorted re-merge of registry append-only edits (`@descripex_modules`, plug-pipeline lists, supervisor children), test-file additions with no overlap, doc append-only blocks. Deterministic from source.
- **Forbidden:** semantic conflict resolution, any logic edit, function-body changes during rebase, any push without `--force-with-lease`, any push to a non-cloud-agent branch under this carve-out.
- **Abort path:** if mechanical resolution doesn't apply cleanly, `git rebase --abort` and post a Linear `@cursor` / `@codex` comment with conflict context. Agent picks up the rebase.

**GH-native auto-merge per PR (preconditions hold).** `delegation-rules.md` § "DON'T AUTO-MERGE PRS" — each PR in the train already has `gh pr merge --auto` wired at PR-open time; GitHub fires the merge when CI is green + no requested-changes + no `[BLOCK-MERGE]` label. Merge-train's job is rebasing each remaining PR onto the new default-branch tip after each merge fires; GitHub handles the merge itself. `audit-review` is NOT chained per merge; one batched `Skill(audit-review) <train-base>..<default-branch-HEAD>` runs at the end of the cascade (same session) covering every merge SHA in a single pass. This is the end-of-cascade variant of the deferred model — solo-PR sessions defer to next-session via the SessionStart hook; merge-trains batch within-session at cascade end. PRs with `[BLOCK-MERGE]` labels stay held until manually reviewed and released.

### When to use

| Situation | Use |
|---|---|
| 1 PR, critical tier | Add `[BLOCK-MERGE]` label, review manually per `agent-pr-review.md` § "Review Tiering"; release the label when ready |
| 1 PR, standard or ceremony | Let GH-native auto-merge fire; merge-train is overhead-equivalent at N=1 |
| 2+ PRs, mixed tiers | **Merge-train.** Cascades, sorts; critical-tier PRs get `[BLOCK-MERGE]` inline for manual review |
| 2+ PRs, all ceremony/standard | **Merge-train.** Maximum gain — GH-native auto-merge fires per PR, reviewer rebases between merges |

### `/batch` → flow-review handoff

`/batch` (per `workflow-philosophy.md` § "Batched Execution" Rule 1) fans a uniform mechanical batch out to worktree-isolated subagents and opens one PR per item. When the batch's PR count crosses 2, the resulting queue is exactly what `flow-review` orchestrates — pick up from here as the merge-train substrate. The dependency sort (§ "What `flow-review` does" step 3) consumes the same `## Files to modify` blocks `/batch` writes into each PR's source issue.

**`/batch` does not bypass the merge gate.** Each `/batch`-produced PR routes through the same GH-native auto-merge gate as any other cloud-agent PR — `--auto` wired at PR-open, branch protection enforcing CI green + no requested-changes + no `[BLOCK-MERGE]` label (`delegation-rules.md` § "DON'T AUTO-MERGE PRS"). `/batch` shortens the *implementation* loop, not the *review* loop.

### Bookkeeping commits

Post-merge ROADMAP/CHANGELOG/README updates land in a single deferred `audit-review` `audit(<sha>): ...` commit on the repo's default branch (`main` / `master` / `development`) covering the whole train. Run `Skill(audit-review) <train-base>..<default-branch-HEAD>` once after the cascade completes. Reviewer rebases each remaining PR onto the new default tip in parallel during the cascade, force-with-leases, CI re-runs. The audit commit IS the bookkeeping; no separate `Update docs for PR #N` commit per merge.

### Cross-References

- `workflow-philosophy.md` § "Batched Execution" — canonical rule under which `/batch` produces the 2+ PRs that feed merge-train (§ "`/batch` → flow-review handoff")
- `agent-pr-review.md` — the per-PR review layer this composes; § "Polling for 'Ready for Review'", § "Review Tiering: When to Hold for Manual Review"
- `agent-dispatch.md` — how the PRs in the train got delegated
- `linear-queue.md` — the Linear-as-queue substrate
- `delegation-rules.md` § "NEVER PUSH TO A CLOUD-AGENT'S BRANCH" — the base rule this carve-out is an authorized exception to; § "DON'T AUTO-MERGE PRS" — the GH-native auto-merge gate
- `plugins/staged-review/templates/auto-merge.md` — GH-native auto-merge wire-up; `[BLOCK-MERGE]` label is the manual-hold path for critical-tier PRs in the train
- `staged-review:audit-review` skill — deferred; invoke once over `<train-base>..<default-branch-HEAD>` after the cascade completes
