---
name: workflow-philosophy
description: Language-agnostic multi-session development workflow principles. Use when structuring multi-phase work — session-per-phase with file-artifact handoffs, evaluator separation (the agent doing the work must not grade it), the staged-but-uncommitted implementer/reviewer handoff, batched execution with /compact STOP checkpoints between disjoint-work batches, writing verifiable acceptance criteria, model-assumption tagging, and verification-before-completion.
allowed-tools: Read, Grep, Glob, Bash
---

<!-- Auto-synced from ~/.claude/includes/workflow-philosophy.md — do not edit manually -->

## Workflow Philosophy

Language-agnostic principles for multi-session development. Derived from Anthropic's [Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps).

### Session-Per-Phase

Each phase runs in a fresh session. The human orchestrates; file artifacts are the handoffs. Fresh sessions avoid context-anxiety-driven early wrap-up and force explicit state capture.

```
brainstorm/interview → .thoughts/
plan                 → reads context, writes plan to .thoughts/
implement            → reads plan, writes code, updates ROADMAP
code-review          → reviews staged changes (pre-commit)
QA                   → validates against acceptance criteria
```

Durable handoffs: ROADMAP.md (cross-session), `.thoughts/` (within-workflow). Oneshot commands (`/elixir-oneshot`) are for small-medium scope only — large features use separate sessions.

### Acceptance Criteria

Plans produce testable criteria a fresh QA session can check without ambiguity.

**Good:** "Hook returns deny JSON with permissionDecision when .py file is edited"
**Bad:** "Works correctly" / "Handles edge cases"

### Evaluator Separation

**The agent doing the work must not grade its own output** — the single strongest lever from the harness research.

- **Hooks** — real-time (post-edit compile, format)
- **`staged-review:code-review`** — pre-commit (staged changes)
- **`/elixir-qa`** — post-implementation (against the plan)

Implementer and evaluator are always different sessions. Even with the same model, separation beats self-evaluation. For high-stakes code (auth, crypto, money, migrations), a second reviewer catches what self-review misses.

### Implementer / Reviewer Handoff

The done-signal between sessions is **staged-but-uncommitted**, not a commit. The implementer session stages the finished change set (`git add`) and stops; a fresh session runs `staged-review:code-review` against `git diff --cached`, then commits only after approval. This is the only handoff shape that lets the reviewer see exactly what shipped *and* kept evaluator separation — if the implementer commits, they've self-graded by declaring the work mergeable.

- **Implementer:** when tests pass and docs are updated, `git add` the final set and summarise what's staged. Do **not** `git commit`, even if the task "feels done" — that's the temptation the rule exists to stop.
- **Reviewer (fresh session):** read the staged diff, run the review, stage no new code (the set being reviewed must be frozen); either approve + commit, or push back and let the original author amend the staged set in a follow-up.
- **Exception:** the user explicitly says "commit it" in the implementer session. Global CLAUDE.md's "never commit without being asked" still governs — staging is the default handoff, not a permission to commit later.

**Hand over a ready commit message.** Whenever you stop and a commit is the next step — the staged-but-uncommitted handoff above, a `⏸ CHECKPOINT`, or simply "the user will commit this" — include a ready one-line commit message in your closing summary. The user (or the next session) should never have to replay chat history to reconstruct what the commit should say. One line, imperative mood, matching the repo's existing log style.

### Batched Execution

**A sequenced plan executes as successive *batches* of disjoint work, with `/compact` rendered as explicit STOP checkpoints between batches — first-class markers, not prose.** This generalizes what `agent-dispatch` already does for delegation batches: the same disjoint-work + `/compact`-between pattern, lifted from the delegation-specific context into a general execution rule.

**When this applies (threshold-gated).** Batched structure is for genuine multi-batch work: a plan with ≥3 batches, or a multi-file migration / phased feature whose file count would blow the context window run start-to-finish. A 2-step plan needs neither fan-out nor checkpoints — the ceremony costs more than it saves. Below the threshold, plan and execute in the main session normally.

**What a batch is.** A batch is a set of work items with no unmet dependency among them — mutually disjoint, runnable simultaneously. Batches are *derived, not declared*: given a task set (e.g. an `rmap next-bundle` result), group it by `depends_on` into successive batches. A task set with no internal dependencies is a single batch. (Hierarchy: phase ⊇ bundle ⊇ batch ⊇ task.)

**Batches nest inside a phase — they don't replace it.** Session-Per-Phase still holds: each *phase* runs in a fresh session with file-artifact handoffs. A *batch* is an in-session sub-structure within one phase's work. `⏸ CHECKPOINT` / `/compact` is the lightweight in-session boundary between batches; the fresh-session handoff stays the heavier boundary between phases. Phase > batch.

**Rule 1 — disjoint work in a batch fans out to subagents.** A batch's items are disjoint by construction, so dispatch them to parallel subagents instead of running them sequentially in the main session. Constraints (per the agents docs):

- Subagents that touch files use `isolation: worktree` — parallel edits collide otherwise.
- Subagents return a *summary*, not a dump — every result lands back in main context.
- **Subagents cannot spawn subagents** — a batch's fan-out is always orchestrated from the main session.
- For a *uniform, mechanical* batch (one instruction describes every item), `/batch` is the native single-batch executor (worktree-isolated fan-out, one PR per item). `/batch` covers one batch, not the inter-batch structure.

**Rule 2 — `/compact` is a first-class STOP checkpoint between batches.** Between batches, render an explicit marker — not a prose sentence the reader must notice:

    ⏸ CHECKPOINT — batch N complete, /compact before batch N+1

At the marker: finish the batch, one-line status, then **STOP**. Hand back so the user can `/compact` and signal continue. A checkpoint is a *planned* pause, not a clarification ask — compatible with "work without stopping for questions". If the batch closes with a commit the agent isn't making itself, the checkpoint carries a ready one-line commit message (see § "Implementer / Reviewer Handoff").

**Render both, structurally.** A genuinely multi-batch plan artifact shows the batches and `⏸ CHECKPOINT` markers as distinct elements. A sentence saying "you may want to compact between phases" does *not* satisfy the rule — the marker is a line of its own.

### Model Assumption Tagging

Every hook/automation encodes an assumption about what the model can't do:

- **Convention** (permanent) — standards-enforcement regardless of model capability (format check, compile check, test runner)
- **Model-limitation** (review when models improve) — compensates for current weaknesses (nudging toward `--failed`, suggesting test patterns)

When a new model ships, review model-limitation tags and strip what's no longer load-bearing.

### Verification Before Completion

No completion claims without fresh evidence. Run the command, read the output, then claim success. Applies to tests passing, files existing, JSON being valid.

### Workflow Routing

| Situation | Tool |
|-----------|------|
| Existing roadmap task (harness BEAM running) | `@~/.claude/includes/harness-workflow.md` + `skills/harness-driver/SKILL.md` |
| Existing roadmap task (no harness) | `task-driver` skill |
| New feature from scratch | `/elixir-plan` → `/elixir-implement` |
| Pre-commit review | `staged-review:code-review` |
| Post-implementation validation | `/elixir-qa` |
| Small-medium feature, single session | `/elixir-oneshot` |
| Large feature | Separate sessions + `.thoughts/` handoffs |

### Layered Architecture

| Layer | Scope | Example |
|-------|-------|---------|
| Global includes | Language-agnostic, loaded everywhere | `workflow-philosophy.md`, `task-prioritization.md`, `harness-workflow.md` |
| Universal skills | Language-agnostic foundations | `task-driver`, `staged-review:code-review` |
| Language commands | Domain concerns | `/elixir-plan`, `/elixir-qa` |
| Language hooks | Real-time enforcement | `post-edit-check.sh`, `pre-commit-unified.sh` |
