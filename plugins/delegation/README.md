# cloud-delegation

Linear-as-queue + cloud-agent (Codex, Cursor) delegation workflow.

Seven skills, all bodies auto-synced from the canonical includes in `~/.claude/includes/`. Don't edit the SKILL.md bodies directly — they get overwritten by `scripts/sync-skills-from-includes.sh`.

## Skills

The Linear-as-queue + cloud-agent delegation workflow is split into four composable skills along a substrate/layer axis, plus a thin hub index. `linear-queue` is standalone — usable without cloud agents at all.

| Skill | Purpose | Canonical source |
|---|---|---|
| `linear-queue` | Substrate: Linear MCP setup, workspace shape, issue-body-as-prompt template, status transitions, self-authored worktree flow, cross-repo coordination, ROADMAP-fallback. **Standalone** — usable without cloud agents | `~/.claude/includes/linear-queue.md` |
| `agent-dispatch` | Dispatch layer: push self-contained tasks to cloud agents (Codex, Cursor) — delegation flows, per-agent eligibility, plan-shaped issue specs, batch sizing, pre-flight conflict detection | `~/.claude/includes/agent-dispatch.md` |
| `agent-pr-review` | Review layer: review and land cloud-agent PRs — polling, comment-fetch, review tiering, push-back-vs-fix-locally matrix, wake-mention discipline | `~/.claude/includes/agent-pr-review.md` |
| `flow-review` | Merge-train mode for 2+ open cloud-agent PRs — dependency-sort, rebase cascade, per-PR auto-merge | `~/.claude/includes/flow-review.md` |
| `linear-workflow` | Hub index — points to the four skills above; use it to find which skill owns a concern | `~/.claude/includes/linear-workflow.md` |
| `cloud-agent-environments` | Agent's-own-env reference: what each cloud agent's harness can / can't do (hex.pm, mix tasks, Tidewave, external HTTP), runtime gotchas, AGENTS.md generation workflow | `~/.claude/includes/cloud-agent-environments.md` |
| `sprite-claude-code` | Operational reference for Fly Sprite-hosted Claude Code as a third cloud-delegation target | `~/.claude/includes/sprite-claude-code.md` |

## When to install this plugin

Adopt when:

- A repo uses cloud-agent delegation (Codex, Cursor) and wants the queue / push-back / review patterns documented in-repo via skills rather than only via per-user CLAUDE.md `@`-imports.
- The repo's own `AGENTS.md` references Linear-as-queue conventions; installing the plugin makes the same reference material available as a discoverable skill, not just a manual import.

Skip when:

- The repo doesn't use Linear or cloud-agent delegation.
- The reference material lives in the user's CLAUDE.md `@`-import chain and that's sufficient — the plugin is value-add when team members or fresh sessions need the skill discoverable in a marketplace search, not strictly required for a single-user setup.

## Linear MCP tools referenced

The skills reference these Linear MCP tools (install the Linear MCP server first):

- `mcp__linear-server__list_issues` / `get_issue` / `save_issue`
- `mcp__linear-server__list_comments` / `save_comment`
- `mcp__linear-server__list_users` (look up agent ids by `displayName`)
- `mcp__linear-server__list_projects` / `save_project`

See `~/.claude/includes/linear-queue.md` § "MCP Registration" for the full surface.

## Sync workflow

The SKILL.md files are kept in sync with the canonical includes via the marketplace's `scripts/sync-skills-from-includes.sh`. After editing any include:

```bash
./scripts/sync-skills-from-includes.sh
```

This preserves the SKILL.md frontmatter (name, description, allowed-tools) and replaces the body with the include content.

## Hook: AGENTS.md auto-sync

`scripts/agents-md-sync.sh` is a PostToolUse hook (matcher `Edit|Write|MultiEdit`) that regenerates `AGENTS.md` whenever a file flowing into it is edited.

**Trigger set:**
- `~/.claude/CLAUDE.md` → walks `~/_DATA/code/*/`, regenerates `AGENTS.md` in every repo that has *both* `CLAUDE.md` and an existing `AGENTS.md`
- `~/.claude/includes/*.md` (direct children only — nested subdirs are excluded) → same portfolio walk
- `~/_DATA/code/<repo>/CLAUDE.md` → regenerates only that repo's `AGENTS.md`, *if* it already has one
- Anything else → silent no-op

**Behavior:**
- Calls the marketplace's `scripts/sync-agents-md.sh` (idempotent — running twice writes byte-identical output, so `git status` stays clean unless upstream content actually changed)
- Repos without an existing `AGENTS.md` are skipped (the hook doesn't auto-create — keep your repo opt-in)
- No git operations: never stages, never commits — the user controls integration timing
- Failures in one repo don't abort the run; the output flags `⚠️ failed: <repo>` per failing repo and continues
- Output: one `🔄 AGENTS.md regenerated:` line per affected repo (suppressed when no-op)

**Env-var overrides** (for tests / non-default layouts):
- `AGENTS_SYNC_PORTFOLIO_ROOT` (default `$HOME/_DATA/code`)
- `AGENTS_SYNC_USER_CLAUDE_ROOT` (default `$HOME/.claude`)
- `AGENTS_SYNC_SCRIPT` (default resolves to the marketplace's `sync-agents-md.sh`)

**Why a hook here:** the SessionStart drift checks (`check-setup-guide.sh`, `check-project-includes.sh`) catch staleness reactively at the *next* session; between an edit and that session, `AGENTS.md` lies. This hook closes that window — cloud agents picking up work after a Claude Code edit see the same instruction set the local session wrote.

**Opt-out:** uninstall the plugin, or remove `AGENTS.md` from a repo that should stop participating.
