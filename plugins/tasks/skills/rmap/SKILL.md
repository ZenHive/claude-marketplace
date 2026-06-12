---
name: rmap
description: Use when working with a project roadmap — picking the next task, scoring with D/B/U, changing task status or markers, creating tasks, rendering ROADMAP.md, or migrating a hand-edited ROADMAP.md to the rmap substrate. rmap is the CLI that manages roadmap/tasks.toml as canonical source and renders ROADMAP.md + roadmap/data.json. Language-agnostic.
allowed-tools: Read, Bash
---

<!-- Auto-synced from ~/.claude/includes/rmap.md — do not edit manually -->

## rmap — Roadmap Substrate

`rmap` is a single-binary CLI that manages `roadmap/tasks.toml` as the typed source of truth for a project's roadmap, rendering `ROADMAP.md` (human view) and `roadmap/data.json` (agent view) from it. **Every project uses rmap** — `tasks.toml` is canonical, `ROADMAP.md` is generated. Hand-editing task tables in `ROADMAP.md` is legacy; migrate (see below).

This file is the **decision layer** — *which* command, *when*. The authoritative command contract is `rmap --help` / `rmap schema` (the live `tasks.toml` field list, derived from the source) plus rmap's own CI-gated `SKILLS.md` in the rmap repo. Don't hand-maintain a parallel command reference here.

### Project layout

```
<project_root>/
├── ROADMAP.md         # rendered — hand-edited prose outside marker pairs is byte-preserved
└── roadmap/
    ├── tasks.toml     # canonical source — author this
    └── data.json      # generated — agents read it for structured access
```

`rmap` walks ancestors of cwd to find `roadmap/tasks.toml`.

### Command surface, by intent

| Intent | Command |
|---|---|
| Read one task / many | `rmap show <id> [--json]` · `rmap list --status\|--phase\|--marker\|--bundle\|--milestone\|--delivered-by [--json]` |
| Pick the next task | `rmap next [--marker M] [--bundle B] [--milestone V] [--count N] [--json]` |
| Pick a session-sized bundle | `rmap next-bundle [--json]` · `rmap bundles` to discover them |
| Pick the parallel-safe dispatch set | `rmap ready [--bundle B] [--phase N] [--marker M] [--milestone V] [--count N] [--dispatchable] [--fields a,b,c] [--json]` |
| List release lines / pin to a release | `rmap milestones [--has-next\|--status\|--json]` · `rmap milestone <id> <name\|none>` |
| Change status | `rmap status <id> <pending\|in_progress\|blocked\|done\|superseded> [--implemented "..."] [--delivered-by <agent>] [--verified] [--shipped-in <sha>] [--reason "..."]` (bulk `1,2,3` atomic; `done` requires `implemented`; outcome flags settable only on `done`; `--reason` settable only on `blocked`) |
| Toggle a marker | `rmap mark <id> +parallel -cx` |
| Add a dependency | `rmap depend <id> on <id>` |
| Create task(s) | `rmap new --from-stdin` (TOML on stdin, atomic batch, full field set per `rmap schema`) — see `task-writing.md`. Interactive `rmap new` covers the common subset; reach for `--from-stdin` when interactive doesn't prompt for a field you need. **`new` rejects `status` and every transition/outcome field** (`status`, `implemented`, `delivered_by`, `verified`, `shipped_in`, `started_at`, `done_at`) with `unknown field` — a created task is *always* `pending`; flip it afterward via `rmap status`. Creation-time fields only: `id phase bundle milestone title scores markers depends_on linear_id assignee module model acceptance_criteria out_of_scope files_to_modify touches cross_repo branch body created_at scored_at`. |
| Format a task as a cloud-agent prompt | `rmap delegate <id> [--to claude\|codex\|cursor\|grok\|antigravity\|pi\|droid]` — `--to` optional, defaults to the task's `assignee` |
| Migrate a hand-edited ROADMAP.md | `rmap import` |
| See what changed vs a git ref | `rmap diff [--verbose] [--json]` |
| List stalled in-progress tasks | `rmap stale --over <dur>` (e.g. `30d`, `2w`; also folded into `doctor`) |
| Health signals (soft, always exit 0) | `rmap doctor [--json]` |
| Strict gates (pre-commit / CI) | `rmap validate` · `rmap validate --check-render` |
| Render after editing tasks.toml directly | `rmap render` (or `rmap watch` for live re-render) |
| Emit data.json to stdout (read-only) | `rmap export json` (`render` is what writes the file) |

All mutators **validate-then-write**: an invalid mutation leaves `tasks.toml` byte-equal to its prior state. `--json` envelopes on the read commands are append-only stable surfaces.

### Concurrent sessions write to rmap — verify task IDs before mutating

`roadmap/tasks.toml` is a **shared, multi-writer file**: parallel Claude sessions, harness dispatches, and cloud agents all create and mutate tasks concurrently. A task ID or task state read earlier in your session is a *snapshot*, not a lock — another writer may have created tasks (shifting "the next ID"), completed the task you're about to mark, or changed the very task you're targeting.

Before any mutation, re-verify against the current file:

- **Before `rmap status <id> …` / `rmap mark` / `rmap milestone` / `rmap depend`:** run `rmap show <id>` first and confirm the title/body matches the task you mean. An ID memorized earlier (or quoted by another session) may now point at a different or already-mutated task.
- **Before `rmap new`:** never assume what ID the new task will get; read it from the command's output after creation, not from "last ID I saw + 1".
- **Before hand-editing `tasks.toml` directly:** re-read the file immediately before the edit — never write from a stale in-context copy. Prefer the `rmap` mutators over hand edits; they re-read and validate-then-write atomically.
- **Referencing tasks across sessions / handoffs:** quote the task *title* alongside the ID so the receiver can detect drift (`rmap show <id>` title mismatch ⇒ stop and re-resolve).

The validate-then-write guarantee protects against *invalid* writes, not *lost* ones — two valid writers can still silently overwrite each other's fields. The verification habit above is the consumer-side discipline that prevents it.

### 🚨 Search existing tasks before `rmap new` — update beats duplicate

A roadmap accretes near-duplicate tasks when each session files "the obvious next task" without first checking whether one already covers it. The result is two tasks the harness dispatches twice, scored inconsistently, drifting apart. **Before filing ANY new task, search the roadmap for prior coverage** — and prefer *updating* an existing task over creating a sibling.

The gate, before every `rmap new`:

1. **Search by concept, not just title.** `grep -niE "<keyword>|<synonym>" roadmap/tasks.toml` across titles *and* bodies (the overlap usually hides in an existing task's `acceptance_criteria`/`body`, not its title), plus `rmap list --bundle <b>` for the bundle the task would land in. One keyword misses it; search the 2–3 ways the idea could be phrased.
2. **Read the candidates in full** — `rmap show <id>` for each near-match. A task whose ACs already imply your work is coverage, even if its title reads differently.
3. **Classify the finding, then act:**
   - **Already fully covered** → don't file. Note the existing ID back to whoever asked.
   - **~80% covered, missing a facet** → *update the existing task* (add an AC + a dated body note naming the new facet) rather than file a near-clone. Hand-edit `tasks.toml`, then `rmap validate && rmap render`.
   - **Genuinely new, but adjacent** → file it, and wire `depends_on` / a body cross-ref to the adjacent task so the relationship is explicit (`out_of_scope` is the right place to say "X belongs to Task N, not here").
   - **Splits into build-now + decide-later** → file the buildable part and a separate *decision spike* (the `task-writing.md` spike shape), rather than one oversized task.
4. **Report the verdict before writing** when the ask was "scope these tasks": say which are new, which fold into an existing ID, which are already done — so the human sees the dedupe, not just the result.

This pairs with the ID-safety rule above (that one stops you *colliding* on an ID; this one stops you *duplicating* the work) and with `task-writing.md`'s Pre-Creation Gate (add the dedupe search as the first gate question — content novelty precedes scoring).

### 🚨 `tasks.toml` is a machine-read contract — corruption or missing outcome fields makes harness re-dispatch landed work

`roadmap/tasks.toml` is not a human notes file. **Harness ingests it as the run queue** (`mcp__harness__roadmap-ingest` / `roadmap-ready`), and the landing pipeline writes back through it (`Harness.Lander` advances `done --verified --shipped-in <sha>` on a successful ff-push). The file is the *single source of truth for what has already landed.* When it's wrong, harness believes already-shipped tasks are still open and **re-dispatches work that is already in `development`** — burning a full implement→review→land cycle (and agent tokens) to redo a merged task, or worse, landing a conflicting second copy.

Two failure classes cause this, both observed in this repo:

1. **Parse-breaking corruption** — a duplicate key in a `[[task]]` table, an invalid `status` enum (`"completed"` instead of `"done"`), a malformed value. `rmap` and every harness consumer that loads the file then **error out or skip the whole file**, so *every* task — including landed ones — reads as absent/pending. One bad table blinds the consumer to the entire roadmap.
2. **Incomplete outcome layer on a landed task** — `status = "done"` but missing `shipped_in` / `done_at` / `verified`. The task parses, but a consumer keying landing-state off those fields can't tell it shipped, so it stays eligible for dispatch. `done` alone is "an implementer claimed it"; **`shipped_in` is the proof it's in the branch** — set both together.

**The disciplines that prevent it:**

- **Prefer the `rmap` mutators over hand-editing.** They re-read, validate-then-write atomically, and reject invalid status/missing-`implemented` transitions — exactly the corruption classes above. Reach for a hand-edit only when no mutator covers the field.
- **After ANY hand-edit of `tasks.toml`, run `rmap validate` before you move on.** It is the gate that catches duplicate keys, bad enums, and `done`-without-`implemented` before a harness consumer trips over them. A hand-edit you didn't validate is a landmine for the next ingest.
- **When work lands, write the full outcome layer in one motion** — `rmap status <id> done --implemented "…" --verified --shipped-in <sha>`. A `done` task without `shipped_in` is an incomplete record harness can misread as still-open. Use the full 40-char SHA, matching the existing rows.
- **Never leave `tasks.toml` in a non-parsing state across a commit.** If `rmap list` errors, fix it *now* — a committed parse error means every concurrent session and every harness ingest is flying blind until someone notices.

This is the rmap-specific, high-stakes corollary of § "Concurrent sessions write to rmap": there the cost of a sloppy write is a lost field; here, because harness *acts* on the file, the cost is redundant or conflicting dispatch of already-shipped work.

### rmap is cheap — set and complete inline; don't manufacture a session

A task's *existence in rmap* is decoupled from *how it gets executed*. Creating one
(`rmap new`) and completing it (`rmap status <id> done`) are lightweight ledger
writes — seconds, a handful of tokens. Neither warrants a separate session, a
dispatch, or a round of "should this even be a task?" deliberation.

When a task is small and you're already in the relevant code, the cheapest correct
path is: **do it inline now, then `rmap status <id> done --implemented "…"` in the same
motion.** Reserve a separate dispatched/cloud-agent session for work that genuinely
earns it — large, risky, parallelizable, or (under a dogfooding mandate) a change to
the orchestrator's own surface. Capturing a discovery as a *pending* task is also fine
and cheap — but **capture ≠ dispatch, and a task ≠ a session.** Hand-done inline tasks
honestly leave `verified` unset (no independent grader ran).

**Failure mode this kills:** treating every rmap entry as a dispatch-and-verify cycle,
or looping in discussion over whether to file/dispatch, when setting + doing +
marking-done inline costs less than the deliberation. Set it, do it (or defer it),
mark it done — don't burn time, tokens, and circles on the ceremony around it.

### 🚨 Right-size tasks — a task is a *dispatch unit*, not a *changelog line*

**The unit of an rmap task is one implement→review→land cycle's worth of coupled
work — not the smallest namable edit.** Every dispatched task pays a full cycle's
overhead (worktree, implementer run, cross-family reviewer, merge, audit). A task
too small to justify that overhead is a manufactured session: it spends an entire
loop to land a one-liner. The 223 lesson (a whole dispatchable task filed for a
moduledoc edit) is the canonical anti-pattern — **that work gets done inline, the
instant you spot it, never filed.**

**Before creating OR splitting a task, apply the coupling test — split on coupling,
never on size:**

1. **Does task B only delete / fix up / wire what task A orphans?** Then B is not a
   task — it's the second half of A. Fold it in. (Tell: B `depends_on` A *and* B's
   files are the ones A stops using; or A's own acceptance criteria already entail
   B's deliverable. Worked example: the CapabilityScore-delete task was redundant —
   its parent's criteria already said "no magic weights remain in the routing
   path," which *is* the deletion. Merged.)
2. **Would one reviewer naturally verify both in a single pass over a single diff?**
   Then they're one dispatch. Don't make the merge train run twice for one logical
   change.
3. **Is it ALL of: D≤2, ≤30 LOC, ≤3 files, no public-surface change?** Then it's an
   *inline* task, not a *dispatch* — do it now and `rmap status … done`, per "rmap
   is cheap" above. Don't file it for later; don't route it through an agent.

**The opposite anti-pattern is equally wrong — do NOT grab-bag.** Combine only
*coupled* small tasks (shared files, one orphans the other, same atomic change).
Two small tasks that are merely both small but touch disjoint files and unrelated
concerns stay separate — bagging them creates a task a reviewer can't verify as one
thing. **Coupling is the merge criterion; size is only the inline-vs-dispatch
criterion.**

**Failure-mode tell — about to file/keep a task whose entire body is "delete the
thing the previous task stopped using," or whose deliverable is already entailed by
a sibling's acceptance criteria? STOP. Fold it into the sibling. About to merge two
small tasks that share no files and no dependency just because both are small? STOP.
That's a grab-bag — keep them separate.**

### Batches are derived, not declared

`rmap next-bundle` returns a session-sized **bundle** — a set of related pending tasks. A *batch* is a finer-grained slice of that bundle: the executor groups bundle tasks by `depends_on` into successive layers of disjoint work (per `workflow-philosophy.md` § "Batched Execution"). There is no `rmap batch` command — batch derivation is the executor's job, not the source-of-truth's. Hierarchy: phase ⊇ bundle ⊇ batch ⊇ task.

### Parallel-dispatch surface (`rmap ready` + the orchestration fields)

When you need *the set of tasks I can dispatch in parallel right now* — not "a session's worth" (`next-bundle`) and not "the single best" (`next`) — use **`rmap ready`**. It returns every `pending` task whose deps are all `done`, which is **mutually independent by construction** (a pending task with all deps done can't depend on another pending task), so the whole set is safe to fan out at once. `rmap ready --bundle <B>` is the dispatchable layer-0 of a bundle — the parallel batch `next-bundle`'s serial chain can't express. Five facts the orchestrator reads instead of re-parsing every task body:

- **`assignee`** (creation-time field, validated against `human|claude|codex|cursor|grok|antigravity|pi|droid`): **THE agent-routing field** — which agent executes the task. Orchestrators route on it (`--fields id,assignee,markers`), and `rmap delegate` defaults `--to` from it. `assignee = "human"` means "not for autonomous dispatch" — consumers skip it. Don't overload `model` (a free-text LLM id) or the `cx`/`csr` markers (filter/discovery tags) for routing. **Set `assignee` at creation** (`rmap new` / `--from-stdin`) — it's easy to omit, but an unset assignee carries no routing intent, so the interactive `rmap delegate` errors (pass `--to`) and an autonomous consumer falls back to *its* configured default dispatch agent rather than your intent. Pick the agent when you file the task; leave it `human` only when the work genuinely isn't for headless dispatch.
- **`dep_layer`** (computed, on every `--json`): longest-path depth over the in-repo dep graph. Within a result set the lowest `dep_layer` present is the current parallel wave; higher layers are later waves — makes `next-bundle`'s topo chain self-describing.
- **`handbuild` marker + `--dispatchable`**: `--dispatchable` (on `ready` / `list`) drops `handbuild`-marked tasks. **UI/LiveView/CSS work is NOT handbuild by default** — incremental UI against an existing design system or a frontend-design doc is normal headless dispatch. Reserve `handbuild` for the genuine minority where a human-in-browser is required: net-new visual identity with no design spec to build against (exploratory look-and-feel / motion / brand). Everything else — backend and spec-anchored UI alike — is headless-dispatchable by default.
- **`touches`** (creation-time field): the broader *involvement hint* — files a task may read or write, typically a superset of `files_to_modify` (the write target). Consumer collision rule (you dedupe; rmap doesn't enforce): two tasks conflict iff `(touches(A) ∪ files_to_modify(A)) ∩ (touches(B) ∪ files_to_modify(B)) ≠ ∅`. Unioning both fields keeps `files_to_modify` respected even when a task's `touches` isn't a perfect superset — `touches` is "typically," not guaranteed, a superset. Set it via `rmap new --from-stdin`.
- **`--fields a,b,c`** (on `ready` / `list`): projects `--json` to a bare array of just the named keys per task — token-cheap for an orchestrator that only needs `id,status,eff,depends_on,dep_layer,touches`. Implies `--json`; unknown name exits 1.

### D/B/U mapping

rmap's scoring **is** the `task-prioritization.md` framework, executable:

- `scores = { d, b, u }` on each `[[task]]` ⇒ the `[D:X/B:Y/U:Z]` you'd otherwise hand-write
- `eff = (b + u) / (2 × d)`, computed at read time, never stored — same formula, same tiers (`≥2.0 🎯 / ≥1.5 🚀 / ≥1.0 📋 / else ⚠️`)
- `scored_at` older than 30 days renders an `Eff:W?` decay suffix

Set scores in `tasks.toml` (via `rmap new` or editing the file); never hand-format the bracket — `rmap render` produces it.

### Status & marker vocabulary

- **status:** `pending | in_progress | blocked | done | superseded` — transitions go through `rmap status`. `blocked` requires a `blocked_reason` (set inline via `--reason "..."`; free-text, blocked-only, overwrites, and **auto-cleared when the task leaves the blocked state** — it renders inline on the blocked row in `ROADMAP.md`); `done` requires `implemented` (set inline via `--implemented "..."`, or pre-populated in `tasks.toml`; on a TTY without the flag, `rmap status` prompts). For bulk `rmap status 1,2,3 done`: the mutation is atomic — if any task is missing `implemented` AND no `--implemented` flag is given AND we're not on a TTY, the whole batch is rejected; `--implemented "..."` applies the same string to every task in the batch.
- **markers:** `parallel | cx | csr | bug | security | docs | handbuild` — `parallel` is the old `[P]`; `cx` / `csr` are the Codex / Cursor delegation markers; `handbuild` flags the narrow human-in-browser exception — net-new visual identity with no design spec (NOT routine UI/LiveView/CSS, which is dispatchable) — that `rmap ready --dispatchable` / `rmap list --dispatchable` exclude.
- **milestone status:** `pending | active | done` — distinct vocabulary from task status. Flip by hand-editing `[milestones.<name>].status` (no mutator yet); `active` milestones sort first in `rmap milestones` and are the load-bearing affordance for the "what release am I cutting next?" query.

### Milestones — first-class release lines

`[milestones.<name>]` is a fourth top-level concept alongside phases / bundles / markers. **Phase** orders work, **bundle** groups topically, **markers** modify execution, **milestone** pins a task to a release line. Milestones cross phases by design: a `v1.0` cut typically pulls from several phases.

**Milestone `description` MUST state a hypothesis.** One sentence naming what the milestone tests (e.g., *"proves Bali professionals will pay for a Bali-specific material-price tool"*, not *"data platform complete"*). Feature-checklist descriptions break the Pre-Creation Gate's milestone-fit check (`task-writing.md` § 4): without a hypothesis, no pinned task can be classified as "tests hypothesis" vs "assumes hypothesis, builds on top", and heavy moat-building drifts onto early validation milestones.

**Default at session start: pick the next task via the active milestone.** Keep exactly one milestone at `status = "active"` (the MVP/release you're cutting); plain `rmap next` then auto-biases to it — no `--milestone` flag needed. Reach for `rmap next --milestone <name>` only to override to a different release line.

- Author the table in `tasks.toml`: `[milestones.v0_1] name = "..." order = N status = "active" target_version = "0.1.0"`. `target_version` is optional free-text.
- Pin a task: `rmap milestone <id> v0_1` (or set `milestone = "v0_1"` directly). Unpin: `rmap milestone <id> none`. One milestone per task.
- Discovery: `rmap milestones` (table view with done/total counts + next-task glyph + active-first sort); `rmap milestones --json` for the agent envelope.
- Drive a release line: `rmap next --milestone v0_1` returns the next pending task in that release; composes with `--bundle`, `--phase`, `--marker`. Without an explicit `--milestone`, `rmap next` automatically biases toward tasks pinned to any `active` milestone — analogous to the existing focus-phase bias. **Focus phase dominates** milestone when the two diverge (4-tier lexicographic: focus-only > active-milestone-only); pass `--milestone <name>` to override the auto-bias to a different release.
- `rmap delegate` surfaces the milestone in `## Context` as `- Milestone: v0_1 (target=0.1.0)` so the target agent knows which release ships their work.
- `rmap render` adds a conditional `🚀 **<milestone>** ·` segment to the task row in `ROADMAP.md` — rows without a milestone render byte-identically to before.
- `rmap render` also fills an optional `<!-- MILESTONES:BEGIN -->` / `<!-- MILESTONES:END -->` section when present. Body shape: one markdown block per declared milestone, sorted like `rmap milestones`; each block includes `### <key> — <name>`, `target_version` (`none` when absent), status glyph + status (`🔄 active`, `⬜ pending`, `✅ done`), the hypothesis from `milestone.description`, and `<done>/<total> done` pinned-task counts. Projects without the marker pair render byte-identically to before.

### `body` vs `implemented`

- `body` = original task definition / intent (never mutated after creation — the spec at scoping time).
- `implemented` = what was actually built and why (required when `status = "done"`; `rmap show` renders both side-by-side as `body (original intent):` / `implemented (what shipped):` when present together). For trivial tasks where delivery matched the spec, `implemented = "as specified in body"` is honest and durable.

### Outcome layer: `delivered_by` + `verified` + `shipped_in`

Three optional transition-time fields next to `implemented`, all set by `rmap status <id> done`. The triple answers who built it, whether a grader agreed, and where it landed:

- `delivered_by = "<agent>"` — which agent or instance actually shipped the task (free-text, unvalidated, like `model`). Answers "who built this?" as a queryable fact without parsing prose. Settable via `--delivered-by <agent>` on `done` transitions; overwrites on re-set.
- `verified = true` — independent evaluator confirmed the task. Two-state: `true` = a check separate from the implementer passed (verification stack green, code-review approved); absent = not yet graded (hand-built, bootstrap, merged directly). Settable via `--verified` presence flag on `done`; to clear, edit `tasks.toml` directly. Encodes evaluator-separation as a fact, not as a status — `done` means "an implementer said so", `verified` means "a grader agreed".
- `shipped_in = "<sha>"` — where the work landed (commit SHA / PR ref, free-text, unvalidated). Settable via `--shipped-in <sha>` on `done` transitions; overwrites on re-set. No sha-shape validation, no git auto-derivation — the caller supplies it.

All three surface in `rmap show`, `rmap list` JSON / `data.json` (via `ExportedTask`), and `rmap diff --verbose`. `rmap list --delivered-by <agent>` filters the roadmap into a per-agent delivery ledger (status-agnostic — matches the field, not just done tasks). `rmap doctor` emits a soft `ClaimedNotGraded` advisory for `done && verified.is_none()` ("claimed, not graded") — always exit 0, hand-built tasks are legitimate. All three stay off `StdinTask` / `NewTaskFields` on purpose; they are outcome facts, not creation-time intent.

### Pinning an LLM model per task

`model = "<model-id>"` on a `[[task]]` records which LLM should do the work — the *value* is free-text and unvalidated (model IDs churn, so no closed set). `rmap delegate` surfaces it as a `- Model:` bullet in the prompt's `## Context` so the target agent knows which model to run. Settable at creation via `rmap new` (interactive + `--from-stdin`) or a direct edit.

**`model` is required (presence, not value) on a live agent-assigned task.** `rmap validate` hard-errors (exit 1, agent-grep `missing model`) when a `pending`/`in_progress` task has `assignee` set and != `"human"` but no `model` — harness hard-rejects a dispatch that resolves to no model (it never falls through to the agent CLI's ambient default), so rmap refuses to author one. The mutators inherit this (validate-then-write): `rmap new --assignee <agent>` on a model-less task fails before write — pin a model whenever you set an agent assignee on a live task. Terminal tasks (`done`/`superseded`/`blocked`) and assignee-unset / `human` tasks are exempt.

The three-way split — don't conflate them:

- **`assignee`** = which *agent* executes the task (validated agent set; THE routing field consumers route on)
- **`model`** = which *LLM* that agent runs (free-text pin; never an agent name)
- **`delegate --to`** = explicit render-time override of `assignee` for one prompt (omit it to honor the stored routing intent)

A fourth, advisory dimension sits alongside these: **`domains`** = a free-text list of capability tags on a `[[task]]` (e.g. `domains = ["otp", "ecto"]`), unvalidated and no closed enum — the *downstream consumer* owns the vocabulary (harness maps them to its `CapabilityDomain` for per-`{agent, domain}` capability scoring). Unlike `assignee`/`model`/`--to`, `domains` does not route a single dispatch — it labels the task so a consumer can group outcomes by domain and move dispatch from explore to exploit. Settable at creation via `rmap new` (interactive + `--from-stdin`) or a direct edit; surfaces on every `--json` payload, in `data.json`, and as a `- Domains:` bullet in `rmap delegate`'s `## Context`.

### Migrating a hand-edited ROADMAP.md

Run `rmap import` — it emits a paste-ready prompt that walks an agent through converting one or more hand-edited `ROADMAP.md` files into `roadmap/tasks.toml` (schema, marker pairs, validate → render → diff-check). One-time, LLM-driven; the prompt carries the detail so this include doesn't have to.

### Cross-references

- `task-prioritization.md` — the D/B/U framework, tiers, ceremony floor, exclusions that rmap executes
- `task-writing.md` — how to write a task's `body` / `acceptance_criteria`; the `rmap new --from-stdin` shape
- `workflow-philosophy.md` § "Batched Execution" — canonical rule for the batch derivation referenced in § "Batches are derived, not declared"
