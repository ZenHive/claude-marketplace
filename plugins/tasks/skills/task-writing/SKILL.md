---
name: task-writing
description: Writing roadmap task descriptions as prompts. Use when authoring a roadmap/tasks.toml task (rmap new), writing a cross-instance handoff doc, or justifying a task's score — covers the 5-question pre-creation gate (anchor to a first consumer, baseline-before-optimization, one-session=one-task merge rule, milestone-fit, no pseudo-rigorous hedging), task-as-prompt vs over-specification, and the tasks.toml field set (body, acceptance_criteria, out_of_scope, scores).
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

### Pre-Creation Gate

Run all 5 before `rmap new`. Any fail → defer / merge / rewrite. Do not create the task.

**1. Anchor.** `body` MUST name the first consumer (sibling task in same bundle, user-visible feature, regulator inquiry, incident class).
- Consumer ≤2 tasks away in same bundle → merge into consumer.
- Consumer unscheduled or in later phase → do not create yet.
- No named consumer → U = low; do not create.
- Disallowed phrases: "for future use", "so we have it", "upfront because cheaper later".

**2. Baseline before optimization.** Quality / normalization / fuzzy-match / ML / multi-variant / observability-depth tasks score U:low until BOTH:
- (a) raw single-path version is shipped, AND
- (b) ≥1 specific user has complained about the thing this task fixes.
- "Cheaper to build now than retrofit" is not a valid score input.
- Disallowed: branching/variants before users, seed taxonomies before raw data, embeddings before raw search.

**3. One session = one task.** If implementing agent lands this task AND an adjacent task in one Claude session / one PR / one branch → merge. No exceptions for "logical separation".
- Test: predicted PR count = 1 → write 1 task.
- Always-merge patterns: install-X + use-X; define-resource + CRUD-LiveView-for-resource; adjacent sibling features in same bundle with no dependency split.
- Full rule: `task-prioritization.md` § Refine, Merge, Don't Duplicate.

**4. Milestone-fit.** Milestone `description` MUST state a hypothesis (`rmap.md` § Milestones). For each pinned task, classify:
- Tests hypothesis → pin.
- Assumes hypothesis true, builds on top → unpin; move to next milestone.
- No classification possible → milestone description is broken; fix it first.

**5. No hedging in justification** (`critical-rules.md` § NO PSEUDO-RIGOROUS HEDGING). Disallowed phrases in `body` as load-bearing reason for B/U: "table-stakes", "increasingly expected", "now standard", "buyers expect", "competitors are starting to", "modern apps all do".
- Required instead: named partner asked, named competitor lever, measured conversion uplift, OR honest low score.
- Test: remove the hedge phrase. If `body` no longer justifies the score → demote.

Pass all 5 → write body (next section).

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
- `acceptance_criteria` — bullet list a fresh QA session can verify
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
