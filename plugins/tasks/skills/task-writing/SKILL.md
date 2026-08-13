---
name: task-writing
description: Writing roadmap task descriptions as prompts. Use when authoring a roadmap/tasks.toml task (rmap new), writing a cross-instance handoff doc, or justifying a task's score — covers the 4-question pre-creation gate (baseline-before-optimization, one-session=one-task merge rule, milestone-fit, no pseudo-rigorous hedging), task-as-prompt vs over-specification, and the tasks.toml field set (body, acceptance_criteria, out_of_scope, scores).
allowed-tools: Read, Bash
---

<!-- Auto-synced from ~/.claude/includes/task-writing.md — do not edit manually -->

## Writing Task Descriptions as Prompts

### Scope

Applies to **`roadmap/tasks.toml`, task lists, cross-instance docs**. Does NOT apply to `/plan` files (single-task session blueprints, consumed by the same instance that wrote them).

**Cross-instance docs** optimize for durability: prompt-style, vague enough to survive codebase changes. **Plan mode files** are the opposite — specific (exact paths, function names, line numbers) because the research just happened and will be used immediately.

**Plan mode files include:** exact paths, concrete approach (not alternatives), specific reuse patterns with locations, verification steps.

**Plan mode files exclude:** D/B scoring, prompt-style vagueness, "let Claude research" (you ARE Claude — you just did).

---

Task descriptions in cross-instance documents are **prompts for Claude Code to implement**, not implementation specs. Claude adapts to current codebase state.

### Observable Results and Reality Contracts

`acceptance_criteria` are the contract a fresh QA/reviewer session verifies. Write observable outcomes, not implementation steps or self-reports. A live task explicitly assigned to a non-human agent must carry at least one non-blank criterion; rmap enforces that mechanical floor, while the author/reviewer judges quality.

For work against an external API or service, the task must name the provider-owned authority and required evidence in `body` or `acceptance_criteria`:

- Authority boundary: **live API / observed traffic + the provider's official docs/specs/SDKs > existing code > assumptions**.
- Third-party clients, aggregators, wrappers, and reference implementations — including CCXT — are compatibility/reference material only. They cannot define semantic correctness or override the provider-owned contract.
- Require at least one real success call and one relevant real error call before implementation.
- Require an integration test that pins the observed request, response, and error semantics.
- Mocks and fixtures may be derived only after observing reality and never replace the live test.
- Missing credentials must fail loudly with exact setup instructions; they never silently skip.
- Verify domain meaning, not merely shape (`is_map`, non-empty body, or HTTP 200 alone is weak evidence).
- For stateful APIs, require isolated setup/cleanup and idempotency where the operation can be retried.

Do not create a separate research task for this observation when the same implementer will build from it in one session; reality discovery is part of the implementation task.

**Encode clarification answers into the task, not the chat** (inspired by spec-kit's `/speckit.clarify`): when the user answers a scoping or clarifying question, fold the answer into `body` / `acceptance_criteria` / `out_of_scope` before filing. An answer that lives only in the conversation is invisible to every future session and to the dispatched implementer — the task file is the only channel that survives.

### Pre-Creation Gate

Run all 6 before `rmap new`. Any fail → defer / merge / rewrite. Do not create the task.

**1. Baseline before optimization.** Quality / normalization / fuzzy-match / ML / multi-variant / observability-depth tasks score U:low until the raw single-path version is shipped.
- "Cheaper to build now than retrofit" is not a valid score input.
- Disallowed: seed taxonomies before raw data, embeddings before raw search, speculative multi-variant branching before a single working path.

**2. One session = one task.** If implementing agent lands this task AND an adjacent task in one Claude session / one PR / one branch → merge. No exceptions for "logical separation".
- Test: predicted PR count = 1 → write 1 task.
- Always-merge patterns: install-X + use-X; define-resource + CRUD-LiveView-for-resource; adjacent sibling features in same bundle with no dependency split.
- Full rule: `task-prioritization.md` § Refine, Merge, Don't Duplicate.

**3. Milestone-fit.** Milestone `description` MUST state a hypothesis (`rmap.md` § Milestones). For each pinned task, classify:
- Tests hypothesis → pin.
- Assumes hypothesis true, builds on top → unpin; move to next milestone.
- No classification possible → milestone description is broken; fix it first.

**4. No hedging in justification** (`critical-rules.md` § NO PSEUDO-RIGOROUS HEDGING). Disallowed phrases in `body` as load-bearing reason for B/U: "table-stakes", "increasingly expected", "now standard", "buyers expect", "competitors are starting to", "modern apps all do".
- Required instead: a concrete named reason — the user asked for it (the developer IS the demand signal), a named technical/legal trigger, a named competitor lever — OR an honest low score.
- Test: remove the hedge phrase. If `body` no longer justifies the score → demote.

**5. Premises verified — or marked as hypotheses.** Any claim in `body` about *current* behavior ("the outer assertion still catches it, so there is no false green"; "X already handles this"; "the venue rejects that anyway") must either name its evidence (a run, a test, a live call, a read of the specific code) or be explicitly tagged `premise unverified — confirm before building on it`, with a confirming step in `acceptance_criteria`.
- An asserted-but-wrong premise steers both implementer AND reviewer wrong: it reads as established fact in the prompt, so nobody re-checks it (observed: a task asserting "no false green" was disproven in review — an `assert {:error, %CCXT.Error{}}` outer match was satisfied by the swallowed failure, and a test had been green on a wrong request).
- Test: for each factual claim in the body, ask "what would I cite if challenged?" No citation and no hypothesis tag → rewrite before filing.

**6. Routing decided at filing — a filed task defaults to an agent.** `assignee` is a ROUTING DECISION, not metadata: rmap freezes it (plus `model`) at creation, and every later session reads the assignee as "routing already decided" — the gate never re-fires. A task that reaches filing is cross-session by definition (inline-doable work was done inline, never filed — see `rmap.md` § "rmap is cheap"), and a cross-session task with verifiable acceptance criteria is exactly what the dispatch loop exists for. **Default-route it to a dispatch agent with a pinned `model`**, spread across the roster (`harness-workflow.md` § "Delegation roster": cursor/codex/grok first, opus last). `assignee = "human"` must be EARNED by a hand-build reason named in the body:
- an operator-gated action blocks the build (license application, credential registration, a purchase, an account approval) — the agent would stall on a step only the human can perform
- net-new visual identity with no spec or design system to build against (the `handbuild` marker's legitimate territory)
- the work reshapes the harness runtime / dispatch loop itself while that loop is in flux, or a headless reviewer genuinely cannot judge the result
- the user explicitly claimed the work for themselves
- Test: for `assignee = "human"`, point to the hand-build sentence in `body`. Can't point → route to an agent. (Inverse of the pre-2026-08-13 rule, which defaulted `human` and demanded a trigger for agents — observed failure: trading_dashboard tasks 86/87, both dispatchable — spec-anchored UI with a working reference, an archive-anchor build with a durable source pointer — filed `human` by reflex, caught by the operator.)
- Reviewer/audit `proposed_tasks` still carry NO routing authority — the filer picks agent + model itself per the roster; the proposal's suggested shape is not the decision. And the pre-filing question stays primary: a proposal inline-doable in minutes is DONE, not filed (observed: ccxt_client task 470, a D2 one-file test-helper fix that should never have become a task — the filing was the defect, not the assignee).
- **"The human owns a decision inside this work" is NOT a reason to route it `human`** — and not a reason to `blocked` it either. Routing answers *who writes the code*; an open decision answers *what the implementer must be told first*. `human` downgrades dispatchable work to hand-build; `blocked` is for an external blocker with an unblock path, and misusing it here hides the task from the queue so the decision is never surfaced. **The task stays `pending` with its agent assignee and `model`.** Name the open decisions explicitly at the top of `body` — each one specific enough to answer ("what search range", "what tolerance counts as zero"), never a bare "discuss first".
- **The orchestrator asks before it dispatches.** A pending task carrying named open decisions is dispatch-*ready*, not dispatch-*now*: the driving AI reads the body when it picks the task up, puts those questions to the human, folds the answers into `body`/`acceptance_criteria` (per § "Observable Results and Reality Contracts" — an answer that stays in chat is invisible to the implementer), and only then dispatches. That obligation is the orchestrator's, on the seat that already reads task bodies to plan a wave — it is not something the queue mechanism enforces for it.
- Test: for each decision the human owns, is it written in `body` as an answerable question? A task routed `human` or parked `blocked` because "the human needs to weigh in" has mis-encoded a briefing as a routing or blocking fact.

Pass all 6 → write body (next section).

### 🚨 Re-Generalize an Agent's Decomposition Before Filing

**When an agent breaks a too-big problem into sub-tasks, its split is overfit to the
solution it happened to find — not the problem's natural seams.** The tasks read as
"the steps of *my* implementation," carrying the agent's accidental architecture
forward into your roadmap. File them verbatim and you've hard-coded one run's
incidental structure as the project's plan.

Before turning any agent-proposed breakdown into `rmap new` tasks, re-generalize:

- **Ask "what are the problem's seams?", not "what did the agent build?"** A task
  should name a capability/boundary that survives a different implementation — not a
  step that only exists because the agent chose approach X.
- **Strip solution-shape tells:** sub-tasks named after the agent's modules/functions,
  a split that mirrors its file-creation order, "wire up the thing the previous step
  made" steps (that's the coupling smell from `rmap.md` § Right-size — fold it in).
- **Re-apply the coupling test to the *generalized* shape**, not the agent's — overfit
  splits routinely propose N tasks where the problem has 2 (or 1).

This pairs with the Pre-Creation Gate: the gate filters *whether* a task earns its
existence; this filters *whose architecture* its shape encodes. The agent's
decomposition is a draft input, never the filed plan.

### Bad: Over-Specified

```
Task: Add user authentication
Files to modify: lib/myapp/accounts.ex, lib/myapp_web/controllers/session_controller.ex
Implementation: [exact module structure, function signatures...]
```

Paths rot. Code examples conflict with evolving patterns.

### Good: Task as Prompt

```
Task: Add user authentication

Add email/password authentication with session tokens. Users register, log in, access protected routes. Hash passwords with bcrypt. Include tests for registration, login success, login failure.
```

Claude finds where, matches existing patterns, survives codebase changes. Clear success criteria, no implementation constraints.

### When Specificity Is Warranted

- User explicitly requested a specific approach
- External constraints (API contracts, database schemas)
- Migration paths where exact steps matter
- Security requirements needing precise implementation

Separate the *requirement* from the *suggestion* even then.

### Task Fields in `roadmap/tasks.toml`

A task's prose lives in two `rmap` schema fields; the rest is structured metadata:

- `title` — one-line imperative summary
- `body` — the prompt: WHAT to accomplish, in prose (the "Task as Prompt" content above)
- `acceptance_criteria` — observable results a fresh QA session can verify; external-boundary tasks include live success/error evidence
- `out_of_scope` — what the task explicitly does NOT do
- `files_to_modify` — anchor paths **only when specificity is warranted** (see above); omit for prompt-style tasks
- `scores = { d, b, u }`, `markers`, `depends_on`, `phase`, `bundle` — structured metadata, not prose

Author tasks with `rmap new --from-stdin` (TOML on stdin, atomic batch):

```bash
rmap new --from-stdin <<'TOML'
[[task]]
phase = 2
bundle = "auth"
title = "Add user authentication"
scores = { d = 5, b = 9, u = 8 }
body = "Add email/password auth with session tokens. Users register, log in, access protected routes. Hash passwords with bcrypt."
acceptance_criteria = ["Registration creates a user", "Login success issues a token", "Login failure is rejected"]
TOML
```

`rmap delegate <id> --to claude|codex|cursor` renders a task as a paste-ready cloud-agent prompt — the task-as-prompt principle with an executable consumer. See `rmap.md`.
