---
name: linear-workflow
description: Index for the Linear-as-queue + cloud-agent delegation workflow, split into four composable skills — `linear-queue` (standalone substrate), `agent-dispatch`, `agent-pr-review`, `flow-review`. Use to find which skill owns a concern, then invoke the specific skill for content. Invoke `linear-queue` alone if you track work in Linear without cloud agents.
allowed-tools: Read, Grep, Glob, Bash
---

<!-- Auto-synced from ~/.claude/includes/linear-workflow.md — do not edit manually -->

## Linear-as-Queue + Cloud-Agent Delegation — Skill Index

The Linear-as-queue + cloud-agent delegation workflow is split into four **composable** skills. This file is the index — invoke the specific skill for content.

**`linear-queue`** — the substrate. Linear MCP setup, workspace shape, the issue-body-as-prompt template, status-transition automation, the self-authored worktree flow, cross-repo coordination, and the ROADMAP-fallback for projects without Linear. **Standalone:** invoke it alone if you track your own work in Linear and don't use cloud agents at all.

**`agent-dispatch`** — the dispatch layer. Push self-contained tasks to cloud agents (Codex, Cursor): delegation flows, per-agent eligibility filtering, plan-shaped issue specs, code-only-PR acceptance criteria, batch sizing, pre-flight conflict detection, honest-gap discipline. Builds on `linear-queue`.

**`agent-pr-review`** — the review layer. Review and land the PRs cloud agents open: polling for ready PRs, fetching existing bot/human comments, review tiering, the push-back-vs-fix-locally matrix, wake-mention discipline, the bundled-code-revisions variant. Builds on `agent-dispatch`.

**`flow-review`** — merge-train mode. Batch orchestration for 2+ open cloud-agent PRs: dependency-sort, rebase cascade, per-PR auto-merge. Composes `agent-pr-review`.

### Which skill owns what

| Concern | Skill |
|---|---|
| Linear MCP setup, workspace / team / project / label shape | `linear-queue` |
| Issue-body-as-prompt template, status-transition automation | `linear-queue` |
| Tracking your own (non-delegated) work in Linear | `linear-queue` |
| Self-authored worktree Linear cadence; cross-repo coordination | `linear-queue` |
| Projects without Linear (ROADMAP-fallback) | `linear-queue` |
| Delegating a task to Codex / Cursor | `agent-dispatch` |
| Repo-selector labels, per-agent eligibility filtering | `agent-dispatch` |
| Plan-shaped issue specs, code-only-PR acceptance criteria | `agent-dispatch` |
| Batch sizing, pre-flight conflict detection, honest-gap discipline | `agent-dispatch` |
| Reviewing a delegated PR, push-back-vs-fix decisions | `agent-pr-review` |
| Polling for ready PRs, wake-mention discipline, fetch-comments | `agent-pr-review` |
| Review tiering, bundled-code-revisions variant, `flow-stats.sh` | `agent-pr-review` |
| 2+ open delegated PRs — merge-train, rebase cascade | `flow-review` |

### Cross-References

- `delegation-rules.md` — the hard rules (no-steal, no-auto-merge, comment-posting permission, force-push scope)
- `cloud-agent-environments.md` — per-agent env reference (hex.pm, mix tasks, Tidewave, external HTTP)
- `dev-lifecycle.md` — the five-phase development lifecycle this workflow composes into
- `worktree-workflow.md` — worktree mechanics the self-authored flow rides on
