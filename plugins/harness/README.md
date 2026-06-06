# harness plugin (`harness@zenhive`)

Language-agnostic orchestration surface for the [harness](https://github.com/ZenHive/harness) OTP engine. Wires a consuming repo to drive the **implement → review → land** loop: pull an rmap task → headless implementer agent works in an isolated git worktree → cross-family **reviewer AI** gates it (runs the project's checks itself, fixes inline, writes the verdict) → merge → post-merge audit.

Install:

```
/plugin marketplace add ZenHive/claude-marketplace
/plugin install harness@zenhive
```

## What's in it

| Component | Purpose |
|---|---|
| **Skill `harness-driver`** | The stable API/MCP contract — how an AI orchestrator drives harness from inside the harness checkout (dogfooding) or from another consuming repo. Native `mcp__harness__dispatch-*` tools, the `project_eval` escape hatch, result/verdict shapes, sharp edges. |
| **Skill `harness-workflow`** | The portfolio-wide workflow contract — dispatch-vs-hand-build, reading the reviewer's verdict, parallel dispatch by dependency graph, autonomous landing, and the layered relationship to the other workflow includes. |
| **Hook `SessionStart`** | Stale-base guard: warns when the current branch is behind its origin tracking branch. With auto-landing on, harness's lander is a second committer to `origin/<target>`, so your local ref drifts — this nudges you to rebase before committing. Fails open (silent on any git error). |

## Prerequisites

The skills assume a long-lived harness BEAM (`iex -S mix` in the harness checkout) reachable over MCP at `http://localhost:4018/harness/mcp`, with your project registered in `Harness.ProjectRegistry`. The `harness-driver` skill (§ "Context A") covers the full consuming-repo wiring: registering the project, adding harness's MCP endpoints to your repo's `.mcp.json`, and importing the skill.

## Canonical sources (do not edit the copies)

Both skills are **synced**, not authored here:

- `skills/harness-driver/SKILL.md` ← `~/_DATA/code/harness/skills/harness-driver/SKILL.md`
- `skills/harness-workflow/SKILL.md` ← `~/.claude/includes/harness-workflow.md`

Edit the source and re-sync. Each file carries a sync-note header.
