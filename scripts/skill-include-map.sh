#!/usr/bin/env bash
# Single source of truth for SKILL.md ↔ include mapping (zenhive marketplace).
# Sourced by both:
#   - scripts/sync-skills-from-includes.sh (writes the synced bodies)
#   - plugins/marketplace-hygiene/scripts/block-skill-edits.sh (denies direct edits)
#
# Format: "relative/path/to/SKILL.md:include-filename.md"
# Adding a new entry here registers the skill as auto-synced; the block hook
# starts denying direct edits to it on the next session.
#
# NOTE: harness plugin's skills (harness-driver, harness-workflow) are NOT mapped
# here — they self-sync from their own canonical sources with per-file headers.

MAPPINGS=(
  # --- elixir (core dev tooling + libs) ---
  "plugins/elixir/skills/zen-websocket/SKILL.md:zen-websocket.md"
  "plugins/elixir/skills/ex-unit-json/SKILL.md:ex-unit-json.md"
  "plugins/elixir/skills/dialyzer-json/SKILL.md:dialyzer-json.md"
  "plugins/elixir/skills/development-commands/SKILL.md:development-commands.md"
  "plugins/elixir/skills/elixir-setup/SKILL.md:elixir-setup.md"
  "plugins/elixir/skills/web-command/SKILL.md:web-command.md"
  "plugins/elixir/skills/reach/SKILL.md:reach.md"
  "plugins/elixir/skills/agent-economy/SKILL.md:agent-economy.md"
  "plugins/elixir/skills/api-toolkit/SKILL.md:api-toolkit.md"
  "plugins/elixir/skills/code-style/SKILL.md:code-style.md"
  "plugins/elixir/skills/development-philosophy/SKILL.md:development-philosophy.md"

  # --- elixir-volt (JS-on-BEAM stack, extracted from elixir) ---
  "plugins/elixir-volt/skills/oxc/SKILL.md:oxc.md"
  "plugins/elixir-volt/skills/quickbeam/SKILL.md:quickbeam.md"
  "plugins/elixir-volt/skills/elixir-volt/SKILL.md:elixir-volt.md"
  "plugins/elixir-volt/skills/npm-ci-verify/SKILL.md:npm-ci-verify.md"
  "plugins/elixir-volt/skills/npm-security-audit/SKILL.md:npm-security-audit.md"
  "plugins/elixir-volt/skills/npm-dep-analysis/SKILL.md:npm-dep-analysis.md"

  # --- phoenix ---
  "plugins/phoenix/skills/phoenix-setup/SKILL.md:phoenix-setup.md"
  "plugins/phoenix/skills/nexus-template/SKILL.md:nexus-template.md"

  # --- tasks (rename of task-driver; roadmap-planning moved in from elixir) ---
  "plugins/tasks/skills/rmap/SKILL.md:rmap.md"
  "plugins/tasks/skills/task-writing/SKILL.md:task-writing.md"
  "plugins/tasks/skills/roadmap-planning/SKILL.md:task-prioritization.md"

  # --- workflow (new; worktree + lifecycle + philosophy + upstream-pr) ---
  "plugins/workflow/skills/git-worktrees/SKILL.md:worktree-workflow.md"
  "plugins/workflow/skills/upstream-pr-workflow/SKILL.md:upstream-pr-workflow.md"
  "plugins/workflow/skills/dev-lifecycle/SKILL.md:dev-lifecycle.md"
  "plugins/workflow/skills/workflow-philosophy/SKILL.md:workflow-philosophy.md"

  # --- portfolio (rename of portfolio-strategy) ---
  "plugins/portfolio/skills/portfolio-strategy/SKILL.md:portfolio-strategy.md"

  # --- delegation (rename of cloud-delegation) ---
  "plugins/delegation/skills/linear-workflow/SKILL.md:linear-workflow.md"
  "plugins/delegation/skills/linear-queue/SKILL.md:linear-queue.md"
  "plugins/delegation/skills/agent-dispatch/SKILL.md:agent-dispatch.md"
  "plugins/delegation/skills/agent-pr-review/SKILL.md:agent-pr-review.md"
  "plugins/delegation/skills/flow-review/SKILL.md:flow-review.md"
  "plugins/delegation/skills/cloud-agent-environments/SKILL.md:cloud-agent-environments.md"
  "plugins/delegation/skills/sprite-claude-code/SKILL.md:sprite-claude-code.md"
  "plugins/delegation/skills/delegation-rules/SKILL.md:delegation-rules.md"
)
