# zenhive marketplace — Roadmap

**Task tracking:** This file is rendered by `rmap` from `roadmap/tasks.toml`. Don't hand-edit the task tables inside `<!-- TASKS:BEGIN -->` / `<!-- TASKS:END -->` marker pairs — they're regenerated on every `rmap render`. Edit `roadmap/tasks.toml` or use `rmap status` / `rmap mark` / `rmap new`, then `rmap render`. Prose outside the marker pairs is byte-preserved.

## Milestones

<!-- MILESTONES:BEGIN -->
### v0_1 — zenhive cutover

- **target_version:** 0.1.0
- **status:** ✅ done
- **hypothesis:** Proves the deltahedge→zenhive rename + concern-split lands cleanly: all plugins resolve, includes→skills sync works from the new repo, and the old marketplace is fully unregistered.
- **pinned tasks:** 0/0 done
<!-- MILESTONES:END -->

## Phase 1 — Migration & cutover (deltahedge → zenhive)

<!-- TASKS:BEGIN phase=1 -->
> 0 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-1-migration-cutover-deltahedge-zenhive).
<!-- TASKS:END -->

## Phase 2 — Maintenance & new plugins

<!-- TASKS:BEGIN phase=2 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 1 | ⬜ | 🎁 **skill-ref-hygiene** · Sweep bare `staged-review` plugin-name and path references after staged-review→review rename [D:3/B:4/U:5 → Eff:1.5?] 🚀 |
| Task 2 | ⬜ | 🎁 **stack-hygiene** · Add ecosystem-detecting dependency-advisory SessionStart hook (stack-wide, one shared plugin) [D:4/B:6/U:6 → Eff:1.5] 🚀 |
| Task 3 | ⬜ | 🎁 **new-skills** · Register himalaya.md as auto-synced skill [D:2/B:6/U:7 → Eff:3.25] 🎯 |
<!-- TASKS:END -->
