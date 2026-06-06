---
name: agent-pr-review
description: Review and land cloud-agent PRs (Codex, Cursor). Use when a delegated PR is open and needs review — review tiering, the push-back-vs-fix-locally matrix by agent, fetching existing bot/human comments before auditing, polling for ready-for-review, wake-mention discipline for @cursor/@codex, the bundled-code-revisions variant. Pairs with `agent-dispatch`; use `flow-review` for 2+ PRs.
allowed-tools: Read, Grep, Glob, Bash
---

<!-- Auto-synced from ~/.claude/includes/agent-pr-review.md — do not edit manually -->

## Cloud-Agent PR Review

The **review layer** of the Linear-as-queue workflow — reviewing and landing the PRs cloud agents (Codex, Cursor) open.

It builds on `linear-queue.md` (the substrate: status transitions, issue-body template) and `agent-dispatch.md` (the outbound path: how the PRs got delegated). For 2+ open delegated PRs, `flow-review.md` (merge-train mode) orchestrates the batch and hands per-PR critical-tier reviews back here.

### Polling for "Ready for Review"

**The PR attachment is the authoritative signal, not the issue status.** Linear's status field is a cached version of "agent opened a PR" — neither Codex nor Cursor write the cache reliably.

```
filter:
  delegate ∈ { Codex, Cursor }
  status ∈ { In Review, In Progress }
then:
  filter to issues with at least one open GitHub PR attachment
  (via mcp__linear-server__get_issue → attachments[].url)
```

Group results into:

- **`In Review` (canonical):** the agent's transition fired correctly
- **`In Progress` with open PR (non-canonical):** agent opened the PR but didn't flip — surface explicitly so the reviewer/user can flip after review

This is the polling shape the cloud-agent review surface uses — `audit-review` Step 4.5 reuses it post-merge to resolve each commit's source PR (squashed `(#NNN)` or `gh search prs --merge-commit <sha>`) when batching the unaudited tail. For batch processing of N≥2 PRs pre-merge (merge-train mode), see `flow-review.md`.

### Fetch Existing Comments Before Auditing

**Before any cloud-agent PR audit, fetch existing comments from BOTH the GitHub PR and the Linear issue.**

GitHub PR — Copilot, CodeRabbit, Codex's GitHub bot, human reviewers:

```bash
gh pr view <number> --json reviews,comments        # PR-level + issue-style
gh api repos/OWNER/REPO/pulls/<number>/comments    # line-level review comments
```

Linear issue — delegating user's clarifications, scope adjustments, prior-reviewer notes, agent's PR-open summary, prior `@codex` / `@cursor` push-back exchanges:

```
mcp__linear-server__list_comments   # filter by issueId
mcp__linear-server__get_issue       # also returns the comment thread
```

Use both to **skip** issues already flagged, **cross-reference** with own findings, **defer to** existing reviewers when something is intentional, **detect scope drift** (Linear comment usually wins over original issue body), **track push-back round-trips**.

Bot caveats: Copilot can fabricate verbatim diff citations (verify before acting); Codex's GitHub bot does evidence-based fact-checking with permalinks.

### Review Tiering: When to Hold for Manual Review

Pre-merge is GH-native auto-merge (`gh pr merge --auto`). Bots + CI gate the merge. The question shifts from "should I run an expensive review skill?" to "should I hold this PR for manual review via `[BLOCK-MERGE]` before letting auto-merge fire?"

**Bots cover the correctness layer.** CodeRabbit, Copilot, and Codex's GitHub bot (3-bot ensemble) catch substantive code-correctness defects at critical tier — wrong arg shapes, missing nil-handling, panic-table swaps. Codex's bot specifically does evidence-based fact-checking with permalinks. Post-merge, `audit-review` Step 5d triages bot findings as a third reasoner alongside Claude (Step 5a) and Codex (Step 5b).

**Manual-hold's unique value at critical tier is NOT second-line code review.** It's the orchestration layer above the bots, applied pre-merge only when the PR genuinely needs it:

1. **Triage** — turn CodeRabbit "consider this" into a verbatim push-back patch with `@cursor`; defer out-of-scope bot findings instead of letting them dilute push-back.
2. **Project-specific rule enforcement** — `.sobelow-skips` regen, `TODO(Task N):` markers, ROADMAP/CHANGELOG acceptance bullets, `harness.yml` conventions.
3. **Procedural orchestration** — merge-conflict surfacing, duplicate-PR closure, CI-red triage, status transitions, push-back-vs-fix routing.
4. **Deep diagnosis** — test-isolation failures, GenServer state pollution, runtime/compile-time interaction bugs that require reading beyond the diff.

If you're re-finding what CodeRabbit already flagged, you're duplicating bot work — pivot to the four roles above, or let auto-merge fire and trust `audit-review`'s post-merge triage.

| Tier | What it covers | Action |
|---|---|---|
| **Critical** | signing, transaction encoding/decoding, ABI codec, RPC client, KMS, anything in the ≥95% coverage tier per `critical-rules.md` § "RAISE COVERAGE BEFORE MUTATING" | Add `[BLOCK-MERGE]` label to hold; manually review with the four-role framing above; push back via Linear `@cursor` / GH PR review comment; remove label to release. Post-merge, `audit-review` runs the full 5+1 audit. |
| **Standard** | type/spec fixes, doc updates, coverage pushes, generator changes, test additions, refactors outside the critical-tier list | Let GH-native auto-merge fire on CI green. If a bot flagged something worth pre-merge eyeballs: optional 5-min skim, then merge or hold. `audit-review` catches post-merge. |
| **Ceremony** | close-out PRs, AGENTS.md tweaks, README-only changes, ROADMAP/CHANGELOG-only updates | Auto-merge fires on CI green. No skim. |

**Touched-files semantic > LOC count.** A 50-LOC change in `lib/<app>/signer/` is critical; a 200-LOC docs change is ceremony.

The push-back-vs-fix matrix below applies to critical-tier manual-hold reviews and to `audit-review` post-merge follow-ups. Standard/ceremony PRs don't engage the calculus — auto-merge fires or `[BLOCK-MERGE]` holds.

For batches of 2+ open cloud-agent PRs, `flow-review.md` applies this tier matrix automatically.

### Push-Back-vs-Fix-Locally Matrix by Agent

#### Default flow is review-only

Read the diff via `gh pr view`, `gh pr diff`, `gh api repos/.../pulls/<n>/comments`. Don't spin up a worktree or `gh pr checkout` unless the finding lands in a fix-locally row OR CI is absent — branch checkout silently biases toward "I'll amend this."

#### CI as the Shared Harness

CI is the shared error gate: every push to a cloud-agent's branch triggers `harness.yml`, so push-back → agent re-pushes → CI runs → green = ready / red = next round. The matrix below is the exception list — local fix is reserved for env-constraint cases the agent fundamentally can't verify.

| Bug class | Codex action | Cursor action |
|---|---|---|
| User-code logic / project-internal API misuse | Push back | Push back |
| Hex-package API correctness (third-party signatures) | **Fix locally** — Codex has no hex.pm | **Push back** — Cursor has hex.pm |
| Test failure / coverage gap on new code | Push back (best Codex can do without `mix test`) | **Push back** — Cursor runs `mix test` |
| Coverage gap on legacy code surfaced by the PR | **Fix locally** — pre-existing debt | **Fix locally** — same |
| Live-data / runtime-state — verification only | **Push back with Tidewave evidence** (Codex has no Tidewave) | **Push back** — Cursor can run Tidewave via `curl` (or `CallMcpTool` if pre-started) |
| Live-data / runtime-state — fix needs verifier's runtime | **Fix locally** (paste-as-comment if viable) | **Push back** if Cursor can verify in its own VM; **fix locally** only if local-only state (your IEx, your DB) is required |
| External spec / RFC / EIP correctness | **Fix locally** — Codex has no external HTTP | Push back (Cursor likely has HTTP) |
| Acceptance criteria not met | Push back | Push back |

#### Tidewave is verification, not necessarily fix

Local Claude has `mcp__tidewave__project_eval` and live runtime/database access. Cursor can also reach Tidewave from its VM (curl-to-MCP always; `CallMcpTool` if pre-started — see `cloud-agent-environments.md` § "Tidewave on Cursor — Reach details"); Codex cannot. Open IEx in the host project (NOT a PR worktree — Tidewave runs against host's currently-loaded code), run `project_eval` against the suspected case, paste the result into the push-back comment as evidence. The asymmetry is a **push-back strengthener**, not a fix-locally trigger — fix-locally only when the code fix is too large to paste verbatim or needs generated artifacts.

> ```
> @cursor verified failure case via Tidewave:
>
> iex> Acme.Users.process(%{user_id: nil})
> ** (FunctionClauseError) no function clause matching in Acme.Users.process/1
>
> Please add a nil guard or update the spec to exclude nil. Re-pushing should green CI.
> ```

#### Preferred channel for fix-locally-required findings

When a finding lands in a fix-locally row, paste the fix as a Linear `@cursor` (or `@codex`) comment with a verbatim code block:

> ```
> @cursor please apply verbatim and re-push:
>
> ```elixir
> # exact code block here, with file:line context above
> ```
>
> Verified against [link to hex docs / RFC / Tidewave query result].
> ```

The agent applies, re-pushes, CI verifies. Authorship preserved. Single error gate.

**Fallback:** separate branch off the PR's base commit — only when the fix is too large to paste verbatim or needs generated artifacts.

**Never amend the agent's branch.** See `delegation-rules.md` § "NEVER PUSH TO A CLOUD-AGENT'S BRANCH".

**Hybrid is fine:** a PR may have both push-back and fix-locally blockers. Surface as two groups; user decides.

### Wake-Mention Discipline

`@cursor` (and `@codex`, future cloud-agent display names) is a **wake/summon signal, not a tag**. Within ~5 min of an `@cursor` mention on a Linear comment, Cursor's Background Agent picks it up as a fresh push-back and runs a session — including issues already in `Done`. Three hard rules:

1. **Never use `@cursor` on a "stop," "FYI," or closing-out comment.** Posting `@cursor — task is complete; please don't spawn further sessions` literally summons the session you're trying to prevent. For closing-out / informational mentions, write `Cursor:` or `Cursor —` in plain prose. Reserve `@cursor` for **fix-this-now push-back**.

2. **One wake mention per push-back round, not one per surface.** When pushing back across both surfaces (GitHub PR review for line-level, Linear comment for scope/intent), the wake mention goes on **exactly one**. Two `@cursor` mentions in the ~5min pickup window risks double-summons.

3. **Decide BEFORE posting either surface.** If `@cursor` placement is genuinely ambiguous, ask the user before the first surface goes up. Posting one with `@cursor` and asking afterwards has already burned the wake signal. Same shape for `@codex`.

**Where to place the one mention.** Linear `@cursor` is the verified wake channel — prefer it. The GitHub PR review is the **content**, not the wake signal — post line-level findings without `@cursor` if the Linear comment carries the mention. Cleanest single-surface shape: skip the GitHub review, put line-level findings + scope paragraph inline in **one** Linear `@cursor` comment with verbatim code blocks.

**Recovery.** If you slip and post a wake-mention in a stop-intent comment, edit-update via `mcp__linear-server__save_comment` with the comment `id` to replace the body — fast edit beats most polls.

### Bundled Code-Revisions in Bookkeeping Commit (Variant)

A deferred `audit-review` pass produces an `audit(...)` commit on the repo's default branch that is normally **hygiene-only** (doc updates, ROADMAP/CHANGELOG, in-code `@doc`/`@spec` drift). This variant uses the same skeleton with **code revisions bundled into the audit commit**, trading evaluator separation for round-trip-cost savings when push-back is high-cost / low-yield.

**When this fires.** All four conditions hold:

- PR is mostly-good but ships some dead/unwanted code that should NOT block merge.
- Reviewer's diff to remove the dead code is small (≤ a few small edits, no logic change, no behavior shift).
- Pushing back would cost more than it saves — typically because the verification the agent needs is one **its own harness can't run** (e.g. `mix dialyzer` OOMs in Cursor's cloud VM, no hex.pm in Codex Cloud, no Tidewave on Codex; Cursor reaches Tidewave so this exception is narrower than it used to be).
- The PR contains something **worth keeping** that rejecting would drop. If net-negative, close-without-merging instead.

**Shape.**

1. **Merge the PR as-is** — `gh pr merge --squash --delete-branch` (auto-merge if preconditions hold, otherwise user-confirmed).
2. **Pre-stage the code revisions, then invoke `audit-review` over the merge SHA range.** On the repo's default branch, edit the offending files to drop the dead code, `git add` (do NOT commit), then run `Skill(audit-review) <merge-sha>^..<merge-sha>`. The audit pass runs against the staged-but-uncommitted state, applies hygiene fixes, and folds everything into one `audit(<merge-sha>): N fixes — bundled-revisions` commit. The bundled-revisions variant is the one case where audit-review fires on a specific merge SHA rather than waiting for the SessionStart hook to flag the tail — pre-staged dead-code edits left across sessions would drift.

   **Recovery if interrupted.** If the session ends or audit-review aborts mid-run, you'll be left with staged-but-uncommitted edits on the default branch. Either resume in a new session by re-running `Skill(audit-review)` (the staged edits remain pre-staged), or `git stash` to set them aside, run a clean `audit-review`, then `git stash pop` and recommit. Don't leave the default branch dirty across sessions.
3. **Linear close-out:** the closing comment **explicitly distinguishes what was merged from what was reverted, and why the agent couldn't have caught it** (env constraint — preserves no-blame framing). Flip status → `Done` manually if Linear's auto-transition didn't fire.

**Trade-offs.** Reviewer DOES grade the merged work this time (the trade), but against hard ground truth (dialyzer / hex / live-data) which is harder to fake. INE traceability preserved (audit commit body names the PR). Touched-file scope rule applies. PR diff drift on GitHub: anyone reading `gh pr view N` sees the original diff (including dead code that no longer exists on the default branch); the closing Linear comment + `.audit/<sha>.md` document the divergence. Revert atomicity: `git revert <audit-sha>` reverts both hygiene updates AND code revisions.

**When NOT to use.** Dead code large enough to be its own PR (push back). Agent CAN run the necessary verification (no env constraint → no excuse to skip push-back). PR is net-negative (close-without-merging). User explicitly said "always push back" in this session.

### Tooling

**`~/.claude/scripts/flow-stats.sh`** — reconstruct cloud-agent PR delegation-flow stats from GitHub timeline events (round count via `head_ref_force_pushed`, draft time, time-to-first-review, merge lag, reviewer breakdown).

```bash
~/.claude/scripts/flow-stats.sh <PR#> [--repo OWNER/REPO] [--json]
~/.claude/scripts/flow-stats.sh https://github.com/OWNER/REPO/pull/<PR#>
```

Auto-detects `--repo` from current git dir. Use after a cloud-agent PR merges to verify the workflow is reducing round-trips (target: 1-2 force-pushes, draft time → 0, merge lag low). Linear-side augmentation is intentionally not in the script — MCP isn't bash-callable; invoke from a Claude session and layer `mcp__linear-server__list_comments` + `get_issue` data when needed.

### Cross-References

- `linear-queue.md` — the substrate (status transitions, issue-body template, self-authored worktree flow)
- `agent-dispatch.md` — the outbound path: how the PRs under review got delegated
- `flow-review.md` — merge-train mode for 2+ open cloud-agent PRs (applies Review Tiering automatically)
- `cloud-agent-environments.md` — per-agent env reference; the Push-Back matrix depends on it
- `delegation-rules.md` § "DON'T AUTO-MERGE PRS", § "NEVER PUSH TO A CLOUD-AGENT'S BRANCH", § "POST LINEAR / PR COMMENTS WITHOUT ASKING DURING DELEGATION FLOWS"
- `staged-review:audit-review` skill — deferred post-merge audit; consumes the tier matrix + push-back framing here (post-merge gaps file as rmap follow-ups per audit-review Step 9 / Step 5d). The Bundled Code-Revisions variant pre-stages into a same-session invocation.
- `plugins/staged-review/templates/auto-merge.md` — GH-native auto-merge wire-up; `[BLOCK-MERGE]` label is the manual-hold gate the tier matrix above pivots around.
- `task-prioritization.md` § "Ceremony Floor" — review-time cost-benefit gate
