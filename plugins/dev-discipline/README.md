# dev-discipline

Pause-and-pick hooks for the moments where Claude tends to choose ceremony over inline fix.

Three PreToolUse hooks. **All are soft reminders, none block.** They emit
`additionalContext` so Claude (and you) sees the prompt at the trigger
moment; exit code is always 0.

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
or project settings level — the global plugin defaults are deliberately
non-blocking, so worst case the additionalContext is informational noise
you can ignore.
