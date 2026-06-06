# Phoenix Plugin

Phoenix-specific setup and template skills for Claude Code.

## Skills

| Skill | Description |
|-------|-------------|
| `phoenix-setup` | Phoenix project setup — phx.gen.auth, Sobelow, LiveDebugger, formatter |
| `nexus-template` | Nexus Phoenix admin template, Iconify icons, partials system |

## Installation

```bash
/plugin install phoenix@deltahedge
```

## Usage

Skills are invoked automatically by Claude when working on Phoenix projects, or manually:

```bash
/phoenix:phoenix-setup       # Phoenix project setup conventions
/phoenix:nexus-template      # Nexus admin template
```

## When to Install

Install this plugin when working on:
- New Phoenix projects (setup conventions, Sobelow, LiveDebugger)
- Projects using the Nexus admin template

Phoenix 1.8 framework patterns (LiveView, forms, streams, Scope), daisyUI 5 component patterns, and Phoenix JS hooks are covered by Claude Opus 4.7's training data and no longer ship as dedicated skills. See the root CHANGELOG for the retirement rationale.

Non-Phoenix Elixir projects do not need this plugin.
