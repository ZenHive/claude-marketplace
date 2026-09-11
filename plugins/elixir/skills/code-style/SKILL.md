---
name: code-style
description: Elixir code quality KPIs and complexity budgets. Use when structuring a module or function, judging whether code is too complex, or checking against the project's per-tier limits (functions per module, lines per function, call depth, pattern-match depth for simple/standard/complex code) and the universal standards (Dialyzer 0 warnings, Credo 8.0+, 80%/95% test coverage, 100% public-API docs).
allowed-tools: Read, Bash
---

<!-- Auto-synced from ~/.claude/includes/code-style.md — do not edit manually -->

## Code Quality KPIs

Keep modules narrow and functions short — a helper module that has grown past a dozen
functions, or a function you can't read without scrolling, is asking to be split. There is
no numeric gate on this; Credo's nesting and complexity checks are the enforced floor.

**Universal Standards:**
- Dialyzer warnings: 0 (mandatory)
- Credo `--strict`: clean
- Test coverage: 80% minimum (95% for critical business logic)
- Documentation coverage: 100% for public APIs
