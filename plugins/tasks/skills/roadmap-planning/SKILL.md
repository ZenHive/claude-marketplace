---
name: roadmap-planning
description: Create prioritized roadmaps and task lists with D/B/U (Difficulty/Benefit/Usefulness) scoring. Use when planning features, organizing refactors, prioritizing backlogs, or structuring any multi-task work. Provides ROI-based ordering, phase organization, dependency tracking, and the status/marker vocabulary — the framework rmap executes (roadmap/tasks.toml canonical, ROADMAP.md rendered). See the rmap skill for the CLI.
allowed-tools: Read, Write
---

<!-- Auto-synced from ~/.claude/includes/task-prioritization.md — do not edit manually -->

## Task Prioritization Framework

### Scope

D/B/U scoring, status, and the `parallel` marker apply to **`roadmap/tasks.toml`** — the typed roadmap source `rmap` renders into `ROADMAP.md`. They are **not for `/plan` files** (single-task session blueprints). See `rmap.md` for the tool surface and `task-writing.md` for how to write a task's prompt body.

### Scoring Format

Each `[[task]]` in `roadmap/tasks.toml` carries `scores = { d, b, u }`. `rmap` computes `Eff = (B + U) / (2 × D)` at read time and renders `[D:X/B:Y/U:Z → Eff:W]` into `ROADMAP.md` — you set the three numbers, you never hand-format the bracket. Scales are 1–10.

| Eff | Tier |
|-----|------|
| ≥ 2.0 | 🎯 Exceptional ROI — do immediately |
| 1.5–<2.0 | 🚀 High ROI — do soon |
| 1.0–<1.5 | 📋 Good ROI — plan carefully |
| < 1.0 | ⚠️ Poor ROI — reconsider or defer |

`rmap` applies these exact tier thresholds; a `scored_at` older than 30 days renders an `Eff:W?` decay suffix.

### Scale (D / B / U)

| Value | Difficulty | Benefit | Usefulness |
|-------|------------|---------|------------|
| 1 | < 1hr, trivial | Minimal impact | Pure hygiene, invisible |
| 3 | Few hours | Minor/cosmetic | Infrastructure only |
| 5 | 1–2 days | Nice to have | Moderate unlock |
| 7 | 2–5 days | Significant QoL | Common question OR unblocks 2+ tasks |
| 9 | 1–2 weeks | Major improvement | Daily question AND unblocks 3+ tasks |
| 10 | Weeks, architectural | Transforms system | — |

**U vs B:** U captures unlock leverage, query frequency, and gap visibility. B captures impact magnitude. Infrastructure-only tasks score high D/B but low U — U prevents them from crowding out user-facing features.

### Exclusions (don't score)

🐛 bugs, 🔒 security, 📝 docs of completed work, ✅ in-progress tasks — always highest priority. In `tasks.toml`, bug and security work carry the `bug` / `security` markers.

### Status

rmap status vocabulary — transition via `rmap status <id> <state>`, never by hand-editing `ROADMAP.md`:

- `pending` — not started
- `in_progress` — being worked; record the `branch` in `tasks.toml`
- `blocked` — paused; requires a `blocked_reason`
- `done` — complete
- `superseded` — obsoleted by another task or a design change

`rmap render` turns these into glyphs in `ROADMAP.md` — the glyphs are output, not something you type.

### Pre-Implementation Gate

Before starting a code-mutating task on an existing module, confirm the module's coverage is at tier:

- ≥80% for standard business logic
- ≥95% for critical business logic (signing, money handling, cryptographic ops, low-level encoders)

If below, raising coverage is **part of this task** — not a follow-up to defer. See `critical-rules.md` § "RAISE COVERAGE BEFORE MUTATING" for scope guards (trivial doc/format/rename mutations are exempt) and the `mix test.json --cover` workflow.

### Parallel Work (`parallel` marker)

Mark independent tasks with the `parallel` marker (`rmap mark <id> +parallel`, or `markers = ["parallel"]` in `tasks.toml`). `rmap next --marker parallel` surfaces them. Before starting one: `rmap status <id> in_progress`, commit any pending work on the main checkout, then create a worktree at `~/_DATA/worktrees/<repo>/task-<id>/` (use the task id as the worktree ID). See `worktree-workflow.md` for the full convention.

### Ceremony Floor — When NOT to Open a Task

**Scope:** applies to **review-surface findings** (`staged-review:code-review` pre-commit; `staged-review:audit-review` post-merge). Discoveries during `/research`, `/plan`, or implementation follow the discovery-capture rules (file via `rmap new`) — not this floor.

Findings during code review or PR review have a ceremony floor below which they are NEVER tracked as `rmap` tasks. The roadmap-as-queue earns its overhead only when work spans sessions; an inline `defp` extraction does not.

| Finding shape                                         | Action                                              |
|-------------------------------------------------------|-----------------------------------------------------|
| ≤ 5 LOC, cosmetic / abstraction / nit                 | Push back inline OR drop — never track              |
| ≤ 5 LOC, **bug or correctness gap**                   | Push back inline — **never drop, never silently track** |
| > 5 LOC, cosmetic / abstraction / nit                 | Push back if cheap, else drop                       |
| > 5 LOC, **bug or correctness gap**                   | Push back inline                                    |
| Cross-session coordination cost (any size)            | rmap task candidate (`rmap new`) (e.g. public-API rename, schema migration, deprecation downstream repos must track) |
| Scope-affecting / architectural / breaks acceptance criteria | Surface for judgment (`discuss`-tier)        |

**Hard rules:**
- Bugs and correctness gaps are NEVER silently dropped, regardless of size or score. They are always pushed back inline.
- Cosmetic / abstraction findings ≤ 5 LOC are NEVER rmap task candidates unless they have cross-session coordination cost.
- "Drop" is permitted ONLY when the diff is genuinely better-as-is AND pushback would generate noise without value (e.g., a stylistic preference the implementing agent's choice is also defensible). When in doubt between drop and push-back, push back.
- Questions like "File a new rmap task for X (under Phase Y, scored [D:N/B:N/U:N])?" are forbidden for findings that fit the current PR — that prompt format implies the floor is broken.

**Why "correctness × size" not "D/B/U × LOC":** D/B/U scores prioritize tracked work; they don't decide whether work should be tracked. A D:1 finding can still be a real bug (3-line missing nil-check) — dropping it because the score is low is exactly the failure mode "iterate fast but error-free" forbids. Correctness vs cosmetic is the load-bearing axis; LOC is just a tiebreaker for tracking-vs-inline.

**Cross-references (delegation flows only — applies if `delegation.md` is imported):** push-back-vs-fix-locally calculus is in `agent-pr-review.md` § "Push-Back-vs-Fix-Locally Matrix by Agent". Hard rule against pushing to cloud-agent branches is in `delegation-rules.md` § "NEVER PUSH TO A CLOUD-AGENT'S BRANCH".

### Refine, Merge, Don't Duplicate — Before `rmap new`

Two `rmap new` failure modes: (1) new task when existing pending task should absorb the new info; (2) two adjacent tasks when one covers both because they ship in one session.

**Required check before every `rmap new`:** scan pending tasks in same bundle (`rmap list --status pending`, or grep `roadmap/tasks.toml`). Same-surface match → edit existing (`body` / `acceptance_criteria` / `out_of_scope` / `scores`). One-session match → merge into one task. New task ONLY when work ships as independent PR alongside the existing one.

**Heuristic:**

| Signal                                                                            | Action                       |
|-----------------------------------------------------------------------------------|------------------------------|
| Same bundle, same outcome, sharper requirements                                   | Edit existing                |
| Same bundle, same outcome, adds edge case / constraint                            | Edit existing (`acceptance_criteria`) |
| Same bundle, ships as separable follow-up PR                                      | New task, `depends_on`       |
| Different bundle or different user-visible outcome                                | New task                     |
| Bug against **pending** task's surface (unclaimed)                                | Edit existing (`acceptance_criteria`) — not a new bug task |
| Bug against **claimed / in-flight** task's surface                                | Push back to agent (`agent-pr-review`) or follow-up task |
| Two adjacent pending tasks ship in **one Claude session / one PR / one branch**   | Merge into one task          |

In doubt → edit or merge.

**One-session test (merge rule).** Before writing the second task in a sequence, ask: predicted PR count for this + adjacent task = 1? Yes → one task with combined `acceptance_criteria`. Each split doubles ceremony (status × 2, branch × 2, PR × 2, audit × 2) for zero work-isolation gain. Always-merge patterns: install-X + use-X; define-resource + CRUD-LiveView-for-resource; adjacent sibling features in same bundle with no dependency split.

Full pre-creation gate (5 questions, this is #3): `task-writing.md` § Pre-Creation Gate.

### Task Descriptions as Prompts

A task's `body` field should be a prompt for Claude Code (WHAT to accomplish), not an implementation spec (HOW). Let Claude research the codebase. Avoid code examples (they rot). Capture success criteria as `acceptance_criteria`. See `task-writing.md` for detail.

### Example

A task in `roadmap/tasks.toml`:

```toml
[[task]]
id = 42
phase = 2
bundle = "realtime"
status = "pending"
title = "Add WebSocket reconnection"
scores = { d = 3, b = 9, u = 9 }   # rmap computes Eff 3.0 → 🎯
markers = ["parallel"]
body = "Implement automatic reconnection with exponential backoff. Include connection state tracking."
acceptance_criteria = ["Reconnects after a transient drop", "Backoff caps at a configured ceiling"]
```

`rmap render` turns that into the scored, tiered row in `ROADMAP.md`. You author the TOML (or `rmap new --from-stdin`) — you never hand-write `[D:3/B:9/U:9 → Eff:3.0] 🎯`.

### Roadmap Maintenance

`roadmap/tasks.toml` is the source of truth; `ROADMAP.md` is rendered by `rmap render`. **Never hand-edit task tables in `ROADMAP.md`** — edit `tasks.toml` or use `rmap status` / `rmap mark` / `rmap new`, then let rmap render.

**When completing a task:**

1. `rmap status <id> done` — rmap re-renders `ROADMAP.md` + `data.json`. Record `shipped_in` (PR/commit) in `tasks.toml` if tracked.
2. **CLAUDE.md** — if repo structure / architecture / conventions changed.
3. **README.md** — if user-facing features or setup changed.
4. **CHANGELOG.md** — *only* a curated human release-notes entry under `## [Unreleased]`, if the change is release-worthy.

A task without updated docs is incomplete.

**Done tasks stay in `tasks.toml`.** rmap keeps `done` / `superseded` tasks as the durable per-task record (`body`, `done_at`, `shipped_in` all persist); `rmap list --status done` and `rmap diff` are the queries. When a phase is fully complete, set `[phases.N].status = "done"` and rmap collapses its rendered table to a one-line summary — no manual archiving, no strikethrough, no copying detail into CHANGELOG.

**CHANGELOG.md is release notes, not a task archive.** Version-grouped human-readable prose, written only when a change is release-worthy. No per-task entries, no D/B/U scores, no counts or stats — numbers rot and burn tokens, and `tasks.toml` already holds the per-task history. Describe *what* shipped and *why*.

The `ROADMAP.md` marker-pair contract (`<!-- TASKS:BEGIN -->` etc.) lives in `rmap.md`.
