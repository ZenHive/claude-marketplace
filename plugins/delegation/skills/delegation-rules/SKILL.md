---
name: delegation-rules
description: Hard rules for cloud-agent (Codex, Cursor) delegation flows. Use when delegating tasks to or reviewing PRs from cloud agents — don't execute [CX]/[CSR]-marked tasks locally, GH-native auto-merge (never run synchronous gh pr merge), default-DO Linear/PR comments during an active flow, never push to a codex/* branch (push back instead), and the one-shot cursor/* force-push scope authorization.
allowed-tools: Read, Grep, Glob, Bash
---

<!-- Auto-synced from ~/.claude/includes/delegation-rules.md — do not edit manually -->

# Delegation Flow Rules

Load this in repos that actively delegate to cloud agents (Codex, Cursor, future agents). For repos with no delegation, these rules add cognitive load without payoff. Foundational rule for all five below: `critical-rules.md` § "NEVER COMMIT WITHOUT EXPLICIT REQUEST".

## 🚨 DON'T STEAL CLOUD-AGENT-DELEGATED TASKS

**When a task in ROADMAP.md is marked with any cloud-agent delegation marker (`[CX]` for Codex, `[CSR]` for Cursor, or any future cloud-agent marker), do NOT execute it locally** unless the user explicitly redirects in this session ("actually, just do this one yourself").

A delegation marker means the task is queued for a specific cloud agent's pickup. Even if it looks small or you have idle context, executing it locally:
- Burns local tokens that should have been the cloud agent's bill
- Splits the review surface — local commit + cloud PR for the same scope
- Defeats the parallel-work model the marker exists for
- Breaks the at-a-glance promise: another session that opens ROADMAP and sees `[CX]` / `[CSR]` trusts the marker is load-bearing

**How to apply:**
1. When picking from ROADMAP.md, skip every cloud-agent-delegated row (`[CX]`, `[CSR]`, etc.) unless it's already `🔄 in-review` (those need GH-native auto-merge to fire — `gh pr merge --auto` was set when the PR opened — or manual `[BLOCK-MERGE]` review; not local re-implementation).
2. If you genuinely think a delegated task should be local instead, ask: "Task N is marked `[CX]` (or `[CSR]`) — are you sure you want me to do this rather than delegate?" Don't just execute.
3. Same discipline shape as `NEVER COMMIT WITHOUT EXPLICIT REQUEST` — the marker is a fence; explicit user override is the gate.
4. **Per-marker eligibility differs.** Cursor (`[CSR]`) can do strictly more than Codex (`[CX]`) — hex.pm, mix tasks, internet — so the user may have intentionally chosen one over the other. Don't second-guess the marker by reasoning "but Cursor could've done this — let me redirect."

The marker is load-bearing across every cloud agent in the lineup; adding more agents (Devin, OpenHands, etc.) expands the rule, doesn't loosen it.

## 🚨 DON'T AUTO-MERGE PRS

**Default: never run `gh pr merge` synchronously or click-merge in the GitHub UI.** The merge step is GitHub-native via the `--auto` flag, set when the PR opens; preconditions are enforced by branch protection.

### The GH-native auto-merge model

When opening a feature-branch PR (any branch that isn't the repo's default — worktree branches, `cursor/*`, `codex/*` all qualify), the same step runs:

```
gh pr create --title "..." --body "..."
gh pr merge <N> --auto --squash --delete-branch
```

GitHub holds the merge until ALL FOUR preconditions are met:

1. **All required status checks green** — including `harness` (or your equivalent CI job) AND `block-merge-gate / gate` (a tiny GH Action that fails when the `[BLOCK-MERGE]` label is present). Configure via branch protection — see `plugins/staged-review/templates/auto-merge.md`.
2. **No requested-changes** review state from a human reviewer.
3. **Feature branch** — PR head is NOT the repo's default branch (`main` / `master` / `development`). gh rejects same-branch merges anyway; stated for completeness.
4. **No `[BLOCK-MERGE]` label** on the PR — this is the manual override, enforced via the `block-merge-gate / gate` required status check.

When all four hold, GitHub merges automatically. Zero Claude / zero cloud-agent invocation pre-merge. Pre-merge phase is GH-native.

**`[BLOCK-MERGE]` label is the manual override.** Add via `gh pr edit <N> --add-label "BLOCK-MERGE"` to pause auto-merge on any PR (cloud-agent or self-authored worktree) — useful when the user wants to inspect manually before shipping (uncertainty, late-arriving context, holding for a coordination batch). Remove via `gh pr edit <N> --remove-label "BLOCK-MERGE"` and auto-merge fires when remaining checks stay green.

**Auto-merge tail ends at branch cleanup.** GitHub's `--auto --delete-branch` deletes the feature branch on merge. Do NOT chain `audit-review` — it runs deferred via the `staged-review` SessionStart hook (`check-unaudited-commits.sh`, ≥3 unaudited threshold). Clear via `/review:audit-status` (snapshot) or `Skill(audit-review) <range>` (batched audit).

### Forbidden under any condition

- **Force-merge bypassing branch protection** — preconditions are non-negotiable.
- **Synchronous `gh pr merge <N>` (without `--auto`)** for cloud-agent PRs or self-authored worktree PRs — wire `--auto` at PR-open time; let GitHub gate it. Synchronous merge is reserved for cases where the user explicitly authorizes it (e.g. removing a `[BLOCK-MERGE]` hold and immediately shipping).
- **Any human-reviewer `requested-changes` state** — reviewer must explicitly resolve first.
- **Merging a PR whose head IS the default branch** — out of scope by definition (gh rejects).

The five-phase chain (`task-driver` → worktree implementer + pre-commit `code-review` → bots → GH-native merge → deferred post-merge `audit-review`) covers what a synchronous merge gate previously caught. Self-authored worktree PRs and cloud-agent PRs follow the same rule. `.audit/<sha>.md` reports plus `audit(...)` commits are the durable post-merge inspection surface.

### How to apply

- **When opening any feature-branch PR:** run `gh pr create` and immediately follow with `gh pr merge <N> --auto --squash --delete-branch`. One short status line per step. Applies to worktree branches, `cursor/*`, and `codex/*` alike.
- **When the user wants to hold a PR for manual review:** add the `[BLOCK-MERGE]` label. Remove the label when ready to ship.
- **Subagents opening PRs inherit the auto-merge wire-up** — explicitly include "wire up GH-native auto-merge via `gh pr merge <N> --auto --squash --delete-branch` immediately after `gh pr create`" in delegation prompts.

### Cross-references

- `plugins/staged-review/templates/auto-merge.md` — GH-native auto-merge adoption guide (branch protection setup, `block-merge-gate.yml`, optional auto-undraft action).
- `~/.claude/includes/critical-rules.md` § "Git Commit / Push / PR-Create — Allowed by Default" — commits (including `audit(...)` on the default branch) need no per-action authorization; only history-rewrite confirms first.
- `~/.claude/includes/delegation-rules.md` § "Force-Push to `cursor/*` Is One-Shot Scope Authorization" — companion autonomy-first loosening for the iteration loop.
- `review:audit-review` skill — deferred post-merge hygiene + bookkeeping pass; surfaced by `staged-review`'s SessionStart hook, next session runs `Skill(audit-review) <range>` off that signal (`/review:audit-status` is a read-only snapshot the user can run if they want a peek).

## 🚨 POST LINEAR / PR COMMENTS WITHOUT ASKING DURING DELEGATION FLOWS

**During an active delegation flow, posting Linear comments and cloud-agent PR comments is DEFAULT-DO, not default-ask.** The Claude Code harness lists "creating/closing/commenting on PRs or issues" alongside `git push` as actions requiring user confirmation. That generic caution is correctly tuned for one-off PR comments on unfamiliar repos; it's wrong-tuned for a delegation queue the user has already authorized work in. This rule explicitly overrides the harness default for the scoped set below.

**In scope (default DO, no permission ask):**
- Linear issue comments — `@cursor` / `@codex` summon mentions, push-back paragraphs, evidence-tier asks (Tidewave findings, hex-docs lookups), status-transition narration
- PR review comments on cloud-agent PRs (`codex/...`, `cursor/...`, future agent branches) — line-level findings, verbatim paste-as-comment fix proposals
- Linear issue status transitions tied to the flow (`Todo` → `In Progress` on pickup, `In Progress` → `In Review` on PR open, `In Review` → `Done` after merge — GH-native auto-merge per § "DON'T AUTO-MERGE PRS", or audit-review Step 12.5 close-out)

**Out of scope (still ask first):**
- Comments on third-party / open-source PRs not in your delegation queue
- Slack, email, or other external messaging
- Creating new Linear issues outside the explicit task the user asked you to delegate
- Anything where the user hasn't named the project, queue, or PR you're operating in

Comment-posting must be friction-free for the asymmetric push-back model (`agent-pr-review.md`) to work — a "should I post this?" gate per `@cursor` mention defeats the loop the delegation pattern exists for.

**How to apply:**
- Surface what you're about to post in one short line ("Posting push-back to Linear issue MW-247: missing nil-check in `validate_address/1`"), then post. Don't wait for "ok."
- Approval is scope-bound to the named project/queue. "Delegate Phase 7 to Cursor" authorizes comments on Phase 7 issues + their PRs; it does NOT authorize comments on a different project's PRs in the same session.
- Subagents inherit this authorization — explicitly include "post Linear / cloud-agent-PR comments without asking, but never `git commit`, `git push`, `gh pr merge`, or push to a cloud-agent's branch" in delegation prompts. Three rules stay strict; one rule loosens.
- If a specific post feels boundary, "ask once, then post freely going forward in this scope" — never "ask for every comment."

**The five-rule asymmetry:**

| Action                                                                        | During active delegation flow |
|-------------------------------------------------------------------------------|-------------------------------|
| `git commit` / `git push` (your own branch, outside a tracked worktree)       | ❌ ask first                  |
| Synchronous `gh pr merge <N>` (without `--auto`)                              | ❌ ask first                  |
| `gh pr merge <N> --auto --squash --delete-branch` at PR-open time             | ✅ default DO (wire up GH-native auto-merge) |
| `git push` to `codex/*` branch                                                | ❌ ask first                  |
| `git push` (incl. `--force`) to `cursor/*` branch                             | 🟡 ask once per branch, then default DO |
| Linear / cloud-agent-PR comments                                              | ✅ default DO                 |

Commits outside tracked worktrees / `codex/*` branch-pushes / synchronous merges are irreversible-by-default; comments are reversible and ARE the workflow. `cursor/*` force-pushes and GH-native auto-merge wire-up sit between — once authorized (cursor branch in this session; PR opened in a tracked worktree), re-asking per-call defeats the loop. The asymmetry is deliberate.

## 🚨 NEVER PUSH TO A CLOUD-AGENT'S BRANCH

**Push-back is the default; never amend a cloud agent's branch (`codex/*`, `cursor/*`, future agent branches) to land a review fix.** The agent authored the work — corrections go back as a Linear `@cursor` / `@codex` comment or a GitHub PR review comment, and the agent re-pushes. Authorship stays intact and every change routes through the shared CI gate (`harness.yml`) instead of a local edit the agent never sees.

Fix-locally is the narrow exception, reserved for env-constraint cases the agent fundamentally can't verify — see `agent-pr-review.md` § "Push-Back-vs-Fix-Locally Matrix by Agent". Even then, the preferred channel is a verbatim paste-as-comment the agent applies, not a direct push.

**Two authorized exceptions, both scope-bound:**

1. **`cursor/*` one-shot force-push** — once the user authorizes a push to a specific `cursor/<name>` branch, it's scope-bound to that branch for the session. See § "Force-Push to `cursor/*` Is One-Shot Scope Authorization" below.
2. **Rebase-only carve-out (merge-train mode)** — during a `flow-review` merge train, rebasing a cloud-agent branch onto an advanced default branch + `git push --force-with-lease` is allowed when the post-rebase diff is byte-identical outside conflict regions and conflicts are resolved mechanically (no semantic edits). The full invariants live in `flow-review.md` § "Rebase cascade" — that file is the canonical statement of the carve-out.

**Forbidden under any condition:** semantic conflict resolution during a rebase, any logic / function-body edit on an agent's branch, any push to `codex/*` outside the rebase-only carve-out, any force-push without `--force-with-lease`.

Amending the agent's branch silently self-grades the work and breaks the implementer/reviewer separation — the agent never learns what was wrong, so the next PR repeats the mistake.

### Cross-references

- `agent-pr-review.md` § "Push-Back-vs-Fix-Locally Matrix by Agent" — when fix-locally is the narrow exception, and the paste-as-comment channel
- `flow-review.md` § "Rebase cascade" — canonical statement of the rebase-only carve-out invariants
- `delegation-rules.md` § "Force-Push to `cursor/*` Is One-Shot Scope Authorization" — the cursor-branch exception in detail

## 🟡 Force-Push to `cursor/*` Is One-Shot Scope Authorization

**Once the user explicitly authorizes a push (including `--force` / `--force-with-lease`) to a specific `cursor/<name>` branch in a session, that authorization is scope-bound to that branch for the remainder of the session.** Re-running the same operation against the same branch does NOT require re-asking.

Scope is granted once, then the loop runs without per-call friction. (Force-push to a shared branch still confirms first — `cursor/*` is the cloud-agent-iteration carve-out, not a blanket history-rewrite allowance.)

**Why `cursor/*` and not `codex/*`:** Cursor PRs commonly need local force-pushes to land review fixes on the same branch — Cursor's iteration shape rewards this. Codex PRs follow a different flow where pushing to `codex/*` is rare and risky. Keep Codex strict; loosen Cursor.

**Companion autonomy-first loosening:** `delegation-rules.md` § "DON'T AUTO-MERGE PRS" wires GH-native auto-merge on any feature-branch PR (worktree branches, `cursor/*`, `codex/*`) at PR-open time; GitHub gates the merge against branch protection (CI green + no requested-changes + no `[BLOCK-MERGE]` label). Same scope-bound autonomy-first lens. The two loosenings are complementary: cursor-force-push handles the iteration loop, GH-native auto-merge handles the merge step.

### In scope (after one-shot authorization for `cursor/<name>`)

- `git push origin cursor/<name>` (the SAME branch) — non-force or force
- `git push --force origin cursor/<name>` / `--force-with-lease`
- Any subagent push to that same branch when explicitly told to operate on it

### Out of scope (still ask first)

- A different `cursor/<other>` branch — each Cursor branch is its own scope
- Any `codex/...` branch — Codex flow stays strict
- `git push --force` to shared branches (`main`, `master`, `development`) — irreversible blast radius
- Force-push to your own feature branches outside a tracked worktree — covered by `critical-rules.md`
- A new session — scope authorization does NOT carry across sessions

### How to apply

1. **First push to `cursor/<name>` in this session:** ask once, plainly. *"Push these fixes to `cursor/foo`? It'll be a force-push because the local branch has rewritten history."* Wait for explicit ok.
2. **Subsequent pushes to the SAME `cursor/<name>` in this session:** announce in one line ("Force-pushing to `cursor/foo`") and run it. No re-ask.
3. **New `cursor/<other>` branch:** treat as fresh scope — ask once, then loosen for that branch.
4. **Subagents inherit the scope.** When dispatching a subagent that may push to a cursor branch the user already authorized, name the branch in the prompt: *"Force-pushing to `cursor/foo` is pre-authorized for this session; proceed without re-asking."*
