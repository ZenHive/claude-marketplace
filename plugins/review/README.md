# Code Review Plugin

Universal code review workflow. Language-agnostic — works with Elixir, Rust, Go, or any language.

Two sibling skills covering pre-commit and post-merge. Pre-merge is GitHub-native (`gh pr merge <N> --auto --squash --delete-branch` wired at PR-open; branch protection + `[BLOCK-MERGE]` label gate the merge — zero Claude/cloud-agent tokens). Adoption guide: [`templates/auto-merge.md`](./templates/auto-merge.md).

- **`code-review`** — pre-commit single-reviewer triage on `git diff --staged`
- **`audit-review`** — post-commit / post-merge audit on committed code, fully autonomous, mandatory parallel Codex + Claude+Codex dialogue, absorbs bot-comment triage + Linear close-out + acceptance-criteria verification, writes `.audit/<sha>.md` reports + `audit(...)` commit

## Two-Tier Review Chain

| Skill | When | Categories | Reviewer | Auto-mode? |
|---|---|---|---|---|
| `code-review` | Pre-commit (`git diff --staged`) | 5 + Cat 6 (full doc hygiene) | Single (Claude) | Plan-mode-with-auto-apply (one user gate: exit-plan-to-apply) |
| _none — GH-native_ | Pre-merge (PR open → merge) | n/a — CI checks + bots + `[BLOCK-MERGE]` label gate | n/a — humans + bots via `[BLOCK-MERGE]` hold | `gh pr merge --auto --squash --delete-branch` wired at PR-open; GitHub fires merge on green CI + no `requested-changes` + no `[BLOCK-MERGE]` label |
| `audit-review` | Post-commit / post-merge | 5 + Cat 6 (full doc hygiene) + bot-finding triage + Linear close-out + acceptance-criteria verification | Dual (Claude + mandatory Codex) + bots as 3rd reasoner, with Claude+Codex dialogue on `discuss-design` | Fully autonomous — zero user gates |

Same 5+1 category catalog across both skills. Categories shift between layers: pre-commit is single-reviewer triage with auto-apply; pre-merge is GH-native (no Claude); post-merge is the dual-reviewer audit pass with mandatory Codex second-opinion + dialogue + bot-finding triage.

**Why pre-merge is GH-native, not a skill:** the harness ceremony (`mix deps.get`, compile, test, fetch comments, dispatch Codex, draft push-back) cost ~100k Claude tokens per PR for marginal signal over CodeRabbit + Copilot + Codex GH bot + CI. Cloud-agent wake-up loops just relocate the bill (sandbox spin-up + their harness). Both shapes were unjustifiable. Bot-comment triage, Linear close-out, and acceptance-criteria verification absorb into `audit-review` (post-merge, deferred, batched).

## `code-review` — Staged Files (Single-Reviewer Pre-Commit Triage)

Reviews `git diff --staged` against 5 categories:

1. **Bugs & Logic Errors** — runtime crashes, type confusion, silent failures
2. **Missing Extractions** — code AND data that should be separated out
3. **Missing TODO Markers** — temporary code without `TODO:` for static analysis
4. **Abstraction Opportunities** — 3+ similar patterns that could be unified
5. **Actionable TODOs** — TODOs resolvable now, fixed directly

Plus **Category 6: Documentation Gaps** (ROADMAP, CHANGELOG, CLAUDE.md, README, in-code `@doc`/`@spec` drift). Single-reviewer pass — no Codex dispatch at this layer (the dual-reviewer pass runs in `audit-review` deferred post-merge).

Each finding is rated 1-10 priority. Actionable items are fixed directly, not just flagged. `discuss-design` items escalate to the user, who can also defer them to `audit-review`'s Claude+Codex dialogue.

## Pre-Merge — GitHub-Native Auto-Merge

No skill. Wire at PR-open time:

```bash
gh pr create --title "..." --body "..."
gh pr merge <N> --auto --squash --delete-branch
```

GitHub holds the merge until all four preconditions hold:

1. CI green (required status check, e.g. `harness`)
2. No `requested-changes` review state from a human reviewer
3. Feature branch (PR head is NOT the default branch — `gh` rejects same-branch merges)
4. No `[BLOCK-MERGE]` label — enforced via branch protection on the `block-merge-gate / gate` required status check

`[BLOCK-MERGE]` is the manual escape hatch: `gh pr edit <N> --add-label "BLOCK-MERGE"` to hold for manual review; `gh pr edit <N> --remove-label "BLOCK-MERGE"` to release. CodeRabbit / Copilot / Codex's GH bot review the PR async — their findings get triaged post-merge in `audit-review` Step 5d (3-reasoner merge: Claude / Codex / bots).

See [`templates/auto-merge.md`](./templates/auto-merge.md) for full setup (branch protection config, `block-merge-gate.yml` GH Action, optional `auto-undraft.yml` for cloud-agent draft PRs).

## `audit-review` — Post-Commit / Post-Merge Audit

Fully autonomous post-commit pass. Deferred — runs on user invocation, not chained off any merge or PR-create:

1. **SessionStart hook** (`check-unaudited-commits.sh`, ≥3 threshold) surfaces unaudited tails next session via `additionalContext` recommending `/review:audit-status` or `Skill(audit-review) <range>`
2. **Manual** via `/review:audit-review [<sha>|<range>]` for catch-up audits, batch passes, or compliance asks

Workflow:

1. Resolve commit range (default: tail since last `audit(...)` commit)
2. Tiny-commit fast path (≤100 LOC + no `lib/`) — skip Codex dispatch, write `verdict: clean — fast-path` report
3. Apply 5 + Cat 6 categories per non-tiny commit
4. Mandatory parallel Codex dispatch via `codex:codex-rescue`
5. Auto-apply rated 3-10 + actionable + `discuss-trivial`
6. Auto-resolve `discuss-design` via Claude+Codex dialogue with ROADMAP scope: convergence applies, divergence drops to ROADMAP candidate (no user escalation)
7. Write `.audit/<sha>.md` per audited commit
8. Auto-commit one `audit(...)` covering the batch

The `audit(...)` commit lands on the repo's default branch without asking (commits are allowed by default per `critical-rules.md` § "Git Commit / Push / PR-Create — Allowed by Default") — it IS the post-merge bookkeeping commit.

## `/audit-status` — Read-Only Drift Snapshot

Quick "is this repo current?" check without running an audit:

```
/review:audit-status              # current repo
/review:audit-status --all        # walk ~/_DATA/code/*, aggregate
```

Prints a table: branch / unaudited-count / last-audit-sha / last-audit-date / range. No mutations, no `git fetch`, no audit triggered. Reuses the same `git log --grep '^audit('` ancestor walk that `audit-review` uses.

## SessionStart Hook — Unaudited-Tail Detection

A `SessionStart` hook (`scripts/check-unaudited-commits.sh`) fires when ≥3 commits sit past the last `audit(...)` ancestor on the current branch. Emits a one-line `additionalContext` recommendation pointing at `/review:audit-status` (for the snapshot) or `Skill(audit-review)` (to actually audit). Silent below the threshold, silent outside a git repo. This is the primary trigger for the deferred audit model — covers interrupted sessions, manual `git commit` outside any flow, branch switches, and the steady-state merge tail.

## Usage

```
/review:code-review              # pre-commit review
/review:audit-review             # post-commit / post-merge audit (manual)
/review:audit-review HEAD~3..HEAD  # explicit range
/review:audit-review --full <sha>  # suppress tiny-commit fast-path
/review:audit-status             # read-only drift snapshot
/review:audit-status --all       # portfolio-wide aggregate
```

For pre-merge, use `gh pr merge <N> --auto --squash --delete-branch` at PR-open time — see [`templates/auto-merge.md`](./templates/auto-merge.md).

## Relationship to Language Commands

This plugin provides the **workflow** (what to check, in what order, with what output). For deep-dive language-specific checklists, use:

- `/elixir-code-review` — comprehensive Elixir/Phoenix checklist
- `/rust-code-review` — comprehensive Rust checklist

## Installation

```bash
/plugin marketplace add ZenHive/claude-marketplace-elixir
/plugin install staged-review@deltahedge
```
