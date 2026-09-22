# Hook Rule Catalog

Named, numbered registry of every rule enforced by a zenhive hook that blocks
or nudges. Each hook's deny/warn message cites its rule ID here, so a blocked
edit is traceable to a stable, greppable identifier instead of ad hoc prose.

**Tier** is `hard` (PreToolUse `permissionDecision: deny` — blocks the edit)
or `soft` (`additionalContext` — informational, exit 0, edit proceeds).

## Repo-local hooks (this repository only)

Wired in this repo's `.claude/settings.json`, scripts under `scripts/hooks/`.
They guard the includes → skills sync invariant and are not distributed as a
plugin.

| ID | Tier | Script | Rule |
|---|---|---|---|
| MH-1 | hard | `block-skill-edits.sh` | Direct edits to a `SKILL.md` registered in `scripts/skill-include-map.sh` are denied — edit the canonical `~/.claude/includes/<name>.md` and re-sync instead. |
| MH-2 | soft | `validate-marketplace-json.sh` | After editing a `marketplace.json`/`plugin.json`/`hooks.json`, surfaces `jq` parse errors immediately as context. |

## Distributed plugin hooks

The `elixir` plugin's hooks are deterministic mechanics (format, compile,
matching test, commit gate, destructive-command block, test.json/dialyzer.json
rewrites) and carry no rule IDs — they run a tool and report its output. The
same holds for `harness`'s stale-base guard and `dep-audit`'s advisory nag.

## Retired

IDs are never reused. Rows stay here so old deny messages in transcripts remain
resolvable.

| ID | Was | Retired because |
|---|---|---|
| CQ-1..CQ-4 | `code-quality` LLM prompt hook: untracked TODO, unmarked deferred work, stub functions, silent workarounds | Duplicated `critical-rules.md` (No evasion, silent workarounds, tracked TODOs) at the cost of one model call per edit. Plugin removed. |
| DD-1 | `assignee = "human"` requires a `# human:` blocker line | Format check that belongs in `rmap validate`, not a hook. Plugin removed. |
| DD-2 | Blocked a hardcoded stale model pin | Model ids are read live from harness `model_availability`; a pinned id in a hook is the fossil it warned about. |
| DD-3, DD-5 | Pause-and-pick before `rmap new` / a new `[[task]]` | Judgment encoded as a trigger-word regex. |
| DD-4 | Long `sleep` / polling loop warning | Same. |
| DD-6 | Demand-hedge phrasing in task bodies | Covered by `critical-rules.md` § "No pseudo-rigorous hedging". |
| DD-7 | `status = "done"` without evidence fields | Judgment as regex. |
| DD-8 | Sibling-class fuzzy title match blocking `rmap new` | "Is this the same class of task?" is a judgment call, not a Python similarity score. |
