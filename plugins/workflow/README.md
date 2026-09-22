# workflow plugin (`workflow@zenhive`)

Language-agnostic workflow and roadmap methodology. Skills only, no hooks — safe to enable globally.

| Skill | Source | Owns |
|---|---|---|
| `rmap` | synced ← `rmap.md` | the roadmap substrate (`roadmap/tasks.toml` → `ROADMAP.md`), statuses, markers, bundles |
| `task-writing` | synced ← `task-writing.md` | task-as-prompt authoring, the pre-creation gate, field set |
| `roadmap-planning` | synced ← `task-prioritization.md` | D/B/U scoring, ceremony floor, discovery capture |
| `task-driver` | native | pickup and plan-and-file session modes |
| `git-worktrees` | synced ← `worktree-workflow.md` | worktree-per-branch rules and lifecycle |
| `upstream-pr-workflow` | synced ← `upstream-pr-workflow.md` | contributing to forked external libraries |
| `onchain-verification` | synced ← `onchain-verification.md` | layered verification for Solidity / EVM / money invariants |

Install:

```
/plugin marketplace add ZenHive/claude-marketplace
/plugin install workflow@zenhive
```

Synced skills are regenerated from `~/.claude/includes/` by `scripts/sync-skills-from-includes.sh`; edit the include, not the copy.
