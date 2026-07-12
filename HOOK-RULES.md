# Hook Rule Catalog

Named, numbered registry of every rule enforced by zenhive's hook-enforcement
plugins (`code-quality`, `dev-discipline`, `marketplace-hygiene`). Each hook's
deny/warn message cites its rule ID here, so a blocked or nudged edit is
traceable to a stable, greppable identifier instead of ad hoc prose.

Packaging only — this catalog names/numbers existing enforcement. It adds no
new rules, no new hooks, and no enforcement-logic changes.

ID prefix = plugin (`CQ` = code-quality, `DD` = dev-discipline, `MH` =
marketplace-hygiene). **Tier** is `hard` (PreToolUse `permissionDecision:
deny` — blocks the edit) or `soft` (`additionalContext` — informational, exit
0, edit proceeds).

## code-quality

Single PreToolUse LLM-prompt hook (`hooks/hooks.json`, matcher
`Edit|Write|MultiEdit`) enforcing four checks against non-doc source files.

| ID | Tier | Rule |
|---|---|---|
| CQ-1 | hard | Untracked TODO/FIXME — every marker needs a `TODO(Task N)` / `TODO(ROADMAP: ...)` / `TODO(#123)` tracking reference. |
| CQ-2 | hard | Unmarked deferred work — comments signaling a temporary/workaround implementation without a TODO/FIXME marker. |
| CQ-3 | hard | Stub functions — hardcoded returns or placeholder-only bodies with no real logic (excludes identity/delegation/test fixtures). |
| CQ-4 | hard | Silent workarounds — swallowed errors, nil-guard fallbacks, or catch-alls that mask upstream bugs instead of propagating/fixing them; a TODO does not satisfy this one. |

## dev-discipline

Seven PreToolUse hooks (`hooks/hooks.json`) — two block, five are soft
pause-and-pick reminders.

| ID | Tier | Script | Rule |
|---|---|---|---|
| DD-1 | hard | `tasks-toml-block-human-assignee.sh` | `assignee = "human"` in `roadmap/tasks.toml` requires a `# human:` blocker line naming the concrete reason no agent can do the work. |
| DD-2 | hard | `tasks-toml-block-stale-model.sh` | `model = "gpt-5-codex"` is a dead/blocked codex model pin — use `gpt-5.5`. |
| DD-3 | soft | `rmap-new-pause.sh` | Pause before `rmap new` — is this cross-session/cross-repo (file it) or in-scope for the current commit (fix inline, don't file)? |
| DD-4 | soft | `polling-warn.sh` | Long `sleep`/polling loop detected — wait for the event/notification instead of burning wallclock. |
| DD-5 | soft | `tasks-toml-new-task-pause.sh` | Same pause-and-pick question as DD-3, for a `[[task]]` block added via direct TOML edit (closes the `rmap new` Bash-matcher bypass). |
| DD-6 | soft | `tasks-toml-warn-demand-hedging.sh` | Demand-hedge phrasing ("wait until someone asks", "table-stakes", ...) in a task body — gate on a named technical/legal/market-scope blocker, never speculated demand. |
| DD-7 | soft | `tasks-toml-warn-evidenceless-done.sh` | `status = "done"` set with no `implemented`/`shipped_in`/`delivered_by` in the same edit — may be a decision-only "done" burying a deferred build. |

## marketplace-hygiene

Two hooks — one PreToolUse block, one PostToolUse informational check.

| ID | Tier | Script | Rule |
|---|---|---|---|
| MH-1 | hard | `block-skill-edits.sh` | Direct edits to a `SKILL.md` registered in `scripts/skill-include-map.sh` are denied — edit the canonical `~/.claude/includes/<name>.md` and re-sync instead. |
| MH-2 | soft | `validate-marketplace-json.sh` | After editing a `marketplace.json`/`plugin.json`/`hooks.json`, surfaces `jq` parse errors immediately as context. |

## Adding a rule

New hooks/checks get the next free ID in their plugin's sequence and a row
here in the same change. IDs are never reused or renumbered after a rule is
removed — a retired ID's row moves to a `## Retired` section (create it when
first needed) rather than being deleted, so old deny messages referencing it
in transcripts/logs stay resolvable.
