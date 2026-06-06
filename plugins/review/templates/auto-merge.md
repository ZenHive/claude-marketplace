# Pre-Merge Auto-Merge (GitHub-Native)

Replaces `staged-review:commit-review` (deleted v1.5+). Pre-merge phase is **zero-Claude / zero-cloud-agent** — bot ensemble + CI gate the merge; `gh pr merge --auto --squash --delete-branch` set when the PR opens.

## The Mechanism

Agent (or you) opens PR. Same step that runs `gh pr create` also runs:

```bash
gh pr merge <N> --auto --squash --delete-branch
```

GitHub queues the merge for when all required checks pass AND no requested-changes review state is on the PR. The `[BLOCK-MERGE]` label is a manual override (see below) that inverts the gate via branch protection.

Six-phase lifecycle collapses to five:

```
task-driver(1) → worktree(2) → bots(3) → merge(4: GH-native) → audit-review(5: deferred)
```

## Required GitHub Setup (per repo, one-time)

### 1. Branch protection on default branch

Settings → Branches → Add rule for `main` (or your default):

- ✅ Require a pull request before merging
- ✅ Require status checks to pass before merging
  - Required: `harness` (or your equivalent CI job)
  - Required: `block-merge-gate / gate` (see § 2 below)
  - Optional: status-check-reporting bots (CodeRabbit, Copilot — if they register checks)
- ✅ Require branches to be up to date before merging (recommended; `--auto` handles the rebase)
- ❌ Do NOT require human review for cloud-agent flows (they post their own PRs)

### 2. `[BLOCK-MERGE]` label gate

Create `.github/workflows/block-merge-gate.yml`:

```yaml
name: block-merge-gate
on:
  pull_request:
    types: [labeled, unlabeled, opened, synchronize, reopened]
jobs:
  gate:
    runs-on: ubuntu-latest
    steps:
      - name: Block merge if BLOCK-MERGE label present
        if: contains(github.event.pull_request.labels.*.name, 'BLOCK-MERGE')
        run: |
          echo "::error::[BLOCK-MERGE] label is present — manual review required"
          exit 1
```

Add `block-merge-gate / gate` to branch protection's required status checks. Result: presence of `[BLOCK-MERGE]` label fails the gate → auto-merge pauses. Remove the label → gate passes → auto-merge fires (assuming all other checks green).

### 3. Optional: auto-undraft on green CI

Some cloud agents open PRs as draft. Add `.github/workflows/auto-undraft.yml`:

```yaml
name: auto-undraft
on:
  check_suite:
    types: [completed]
jobs:
  undraft:
    if: github.event.check_suite.conclusion == 'success'
    runs-on: ubuntu-latest
    steps:
      - name: Mark draft PRs ready
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          PRS=$(gh pr list --search "is:pr is:open is:draft head:${{ github.event.check_suite.head_sha }}" --json number --jq '.[].number')
          for n in $PRS; do gh pr ready "$n"; done
```

## When Bots Haven't Reviewed Yet

GitHub's `--auto` flag waits for all **required** status checks. Two regimes:

| Bot integration shape          | Behavior under `--auto`                                        |
|--------------------------------|----------------------------------------------------------------|
| Registers status checks        | Make them required → `--auto` waits for bot completion         |
| Posts review comments only     | `--auto` fires on CI green alone → bot comments arrive after merge |

Either is acceptable. Post-merge bot comments get triaged in `audit-review` Step 5d (3-reasoner triage table).

## Manual Hold for Pre-Merge Review

To pause auto-merge on a PR that needs manual eyeballs before shipping:

```bash
gh pr edit <N> --add-label "BLOCK-MERGE"
# ... inspect, push back, fix ...
gh pr edit <N> --remove-label "BLOCK-MERGE"
# Auto-merge fires when all other checks remain green.
```

Use cases: critical-tier diffs, suspected regressions, holding for a coordination batch, late-arriving context. The label is the **only** sanctioned pre-merge gate beyond CI.

## What Replaced commit-review's Other Features

| `commit-review` feature                | Replacement                                                       |
|----------------------------------------|-------------------------------------------------------------------|
| Bot-comment triage                     | `audit-review` Step 5d (post-merge, 3-reasoner triage table)      |
| Linear close-out                       | `audit-review` Step 12.5 (post-merge, batch tail)                 |
| Acceptance-criteria verification       | `audit-review` Step 9 extension (post-merge, unmet → rmap follow-up) |
| Push-back to cloud agent (pre-merge)   | Removed. No active push-back channel post-merge — file rmap follow-ups; next iteration cycle picks them up. Use `[BLOCK-MERGE]` to hold for manual review pre-merge. |
| Auto-undraft on green CI               | Optional `auto-undraft.yml` GH Action (§ 3 above)                 |
| 5-precondition merge gate              | GH branch protection rules (CI green + `[BLOCK-MERGE]` gate)      |
| Commit-Review Header (bracket prefix)  | Removed. No commit-review flow → no header.                       |

## Cross-References

- `staged-review:audit-review` — post-merge audit (deferred, batched, autonomous)
- `~/.claude/includes/delegation-rules.md` § "DON'T AUTO-MERGE PRS" — auto-merge preconditions (now framed GH-native)
- `~/.claude/includes/worktree-workflow.md` § "PR auto-merge" — self-authored worktree flow
- `~/.claude/includes/agent-dispatch.md` § "Cursor Delegation Flow" — cloud-agent task template
