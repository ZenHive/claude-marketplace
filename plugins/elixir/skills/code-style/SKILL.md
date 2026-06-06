---
name: code-style
description: Elixir code quality KPIs and complexity budgets. Use when structuring a module or function, judging whether code is too complex, or checking against the project's per-tier limits (functions per module, lines per function, call depth, pattern-match depth for simple/standard/complex code) and the universal standards (Dialyzer 0 warnings, Credo 8.0+, 80%/95% test coverage, 100% public-API docs).
allowed-tools: Read, Bash
---

<!-- Auto-synced from ~/.claude/includes/code-style.md — do not edit manually -->

## Code Quality KPIs (Complexity-Based)

**Simple Code** (utilities, helpers, data transforms):
- Functions per module: 12 max
- Lines per function: 10 max
- Call depth: 2 max
- Pattern match depth: 3 max

**Standard Code** (business logic, controllers, contexts):
- Functions per module: 8 max
- Lines per function: 15 max
- Call depth: 3 max
- Pattern match depth: 4 max

**Complex Code** (GenServers, supervisors, distributed systems):
- Functions per module: 6 max
- Lines per function: 20 max
- Call depth: 4 max
- Pattern match depth: 5 max

**Universal Standards:**
- Dialyzer warnings: 0 (mandatory)
- Credo score: 8.0 minimum
- Test coverage: 80% minimum (95% for critical business logic)
- Documentation coverage: 100% for public APIs
