# Task Driver Plugin

Roadmap-driven task execution workflow. Language-agnostic — works with any project that has a ROADMAP.md.

## What It Does

1. Reads ROADMAP.md and linked planning docs
2. Enters plan mode — presents top tasks sorted by D/B efficiency
3. User approves task selection
4. Implements with TodoWrite progress tracking
5. Adds `TODO(Task N):` markers for discovered work
6. Updates all project docs (ROADMAP, CHANGELOG, CLAUDE.md, README)
7. Adds newly discovered tasks to ROADMAP.md with D/B scores

## Usage

```
/task-driver:task-driver
```

## Relationship to Other Skills

- **roadmap-planning** (elixir plugin) — defines the D/B scoring format. task-driver *consumes* that format.
- **staged-review** — reviews staged files. task-driver implements and stages files.

## Installation

```bash
/plugin marketplace add ZenHive/claude-marketplace-elixir
/plugin install task-driver@deltahedge
```
