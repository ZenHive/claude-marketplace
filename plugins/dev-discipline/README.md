# dev-discipline

Pause-and-pick hooks for the moments where Claude tends to choose ceremony over
inline fix — plus three `roadmap/tasks.toml` integrity guards.

Six PreToolUse hooks. **Five are soft reminders** (emit `additionalContext`,
exit 0). **One blocks** — `tasks-toml-block-human-assignee.sh` denies an edit
that masks dispatchable work as human-assigned; masking is costly and the deny
is cheaply recoverable (add a `# human:` line, re-apply).

## Hooks

### `rmap-new-pause.sh`

**Fires:** PreToolUse:Bash when the command contains `rmap new` (any form —
`rmap new`, `rmap new --from-stdin`, `... && rmap new ...`).

**Asks:** Is this finding fixable in the current commit's scope?
- Cross-session / cross-repo → file.
- In-scope / fits current commit → fix inline, don't file.
- Same-PR follow-up → push back or amend, don't file.

### `tasks-toml-new-task-pause.sh`

**Fires:** PreToolUse:Edit/Write/MultiEdit when the target is
`*/roadmap/tasks.toml` AND the edit adds a `[[task]]` block (header count
in the new content > old content).

**Closes the workaround corridor:** without this, the `rmap-new-pause`
Bash matcher can be bypassed by directly editing the TOML.

Silent on status flips, marker toggles, body/score edits, and edits to
non-`tasks.toml` files.

### `polling-warn.sh`

**Fires:** PreToolUse:Bash on `sleep N` where N ≥ 10, or `until/while ...;
do ... sleep ...` polling loops.

**Asks:** Are you ducking a "return to the user, wait for the
notification" moment? The harness notifies on completion; sleeping past
that notification just delays your own response. For external state Claude
can't observe (CI, deploy), use a Monitor with an event-shaped check, not
a fixed-length sleep.

Silent on short bridge sleeps (`sleep 1..9`).

### `tasks-toml-block-human-assignee.sh` — the one blocking hook

**Fires:** PreToolUse:Edit/Write/MultiEdit when the target is
`*/roadmap/tasks.toml` AND the new text sets `assignee = "human"` without a
`# human:` blocker line.

**Blocks** (`permissionDecision: deny`). `human` is RESERVED — legitimate only
when no agent can do the work from a sandbox, and the concrete blocker must be
named on a `# human:` comment line (external account / network vantage,
business/legal sign-off, or a genuine decision spike). The recurring failure
mode: a dispatchable task gets `assignee = "human"`, lands silently on the
operator, and the delivery pipeline never picks it up. A dispatch hint (e.g.
`handbuild`) is never an assignee; parking is a `status` (`blocked` +
`blocked_reason`), not a `human` assignee.

Silent on any other assignee, on a human assignee that carries its `# human:`
line, and on non-`tasks.toml` files.

### `tasks-toml-warn-demand-hedging.sh`

**Fires:** PreToolUse:Edit/Write/MultiEdit when the new text in a
`*/roadmap/tasks.toml` matches demand-hedge phrasing (`wait until`, `unproven
demand`, `table-stakes`, `buyers expect`, ...).

**Asks:** Are you reframing requested work as needing evidence you can't get?
Critical-rules § NO PSEUDO-RIGOROUS HEDGING — the developer IS the demand
signal. A task may only be gated on a NAMED technical / legal / market-scope
dependency with a concrete unblock path, never on speculated demand. Soft —
ignore it when the phrase names a real market-scope trigger.

### `tasks-toml-warn-evidenceless-done.sh`

**Fires:** PreToolUse:Edit/Write/MultiEdit when the new text in a
`*/roadmap/tasks.toml` sets `status = "done"` with no `implemented` /
`shipped_in` / `delivered_by` beside it.

**Asks:** Is this a genuinely-shipped done, or a decision-only "done" burying a
deferred build where it drops out of the backlog (the same silent-defer failure
as masking work as `human`, in a different shape)? Shipped → add the evidence;
deferred → it's `blocked` (+ `blocked_reason`) or still `pending`, not done.

## Why this exists

The close-2-open-2 anti-pattern: close N tasks, open N new tasks — net
zero progress on the queue, plus accumulated coordination overhead.

Memory entries like `feedback_dogfood-task-spawn-rate` name the *outcome*
("ratio must stay positive") but don't fire at the *trigger word*. Hooks
fire deterministically at the moment of action; memory is fuzzy recall.

The origin trace is captured in the `rmap` task that landed this plugin —
`hookify:conversation-analyzer` surfaced these three patterns from a real
session where the user explicitly flagged the close-2-open-2 churn as
cross-session, not session-local.

## Install

This plugin is registered in `.claude-plugin/marketplace.json` as
`dev-discipline`. Standard marketplace install picks it up. No additional
configuration needed.

## Override

If you want to silence one hook locally (e.g. during a long marketplace
audit pass where rmap new IS the work), unregister or replace at the user
or project settings level. The five soft reminders are informational noise
you can ignore at worst; the one blocking hook
(`tasks-toml-block-human-assignee.sh`) is always recoverable in place — add
the `# human:` blocker line, or give the task a dispatchable assignee — so
it never strands an edit.

The three `tasks.toml` integrity guards (`block-human-assignee`,
`warn-demand-hedging`, `warn-evidenceless-done`) were promoted from per-repo
`hookify.*.local.md` rules into distributed plugin scripts so every repo with
the plugin enabled gets them with zero per-repo setup.
