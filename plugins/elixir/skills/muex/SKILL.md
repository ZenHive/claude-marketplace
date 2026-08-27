---
name: muex
description: muex — mutation testing for Elixir/Erlang via `mix muex`. Use when running or interpreting a mutation-testing audit, reading survivors, or configuring a run. Carries the two traps that silently zero a run — the 10s default `--timeout` and the file-filter/optimizer defaults — plus the undocumented progress legend and the flicker rule that forbids using it as a CI gate.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/muex.md — do not edit manually -->

## Muex — Mutation Testing for Elixir / Erlang

Introduces deliberate bugs into `lib/` and checks whether the suite catches them. A killed
mutant means a test actually asserted the behavior; a **survivor** means the line is executed
but nothing checks the result — the class of hole coverage percentage cannot see.

**`{:muex, "~> 0.9.1", only: [:dev, :test], runtime: false}`.** Invoked as `mix muex`.

### 🚨 Never a gate — it is a hand-run audit

Verdicts **flicker between byte-identical runs**, and the deviation always goes toward
**false green**. Measured on upstream_repos 2026-08-26: four identical `--concurrency 1`
runs over the same 79 mutants returned 49 / 49 / 51 / 50 killed. Not a 0.9.0 regression
(0.8.3 flickers the same way); cause unknown.

Consequences, both load-bearing:

- **One run is not evidence.** Repeat a measurement before quoting any score in a report,
  a CHANGELOG, or a task body.
- **Never wire `--fail-at` into CI or a precommit alias.** A flickering grader that fails
  toward green is worse than no grader — it certifies.

Serializing does **not** fix the flicker (it was measured *at* `--concurrency 1`), so
`--concurrency 1` costs ~10× wall time and buys nothing. Use the default.

*Counter-measurement, so the rule is applied and not just repeated:* on bourse
(`lib/bourse/signing/eip712.ex`, 398 mutants, 0.9.1, default concurrency) two identical runs
returned identical counts **and byte-identical survivor lists**. So the flicker is not
universal — check it on your own surface with one small module run twice before deciding how
much a single score is worth. Compare the survivor *lists*, not the totals: equal counts can
coincide.

### 🚨 `--timeout` is the trap that silently zeroes a run

**Default is 10 000 ms, and that is far too low for any non-trivial project.** Each mutant
runs a sandboxed `mix test`; the sandbox symlinks `_build` and deep-copies only the mutated
app, but the mutated file and its dependents still recompile.

**The failure is silent and looks like a finished run:** every mutant returns `:timeout`,
so killed = 0 and survived = 0, and the score is computed over an empty denominator.
Measured on bourse 2026-08-27: 1533 mutants processed → 1144 timeouts, 386 invalid,
**0 killed, 0 survived**. Raising to `--timeout 60000` removed the timeouts entirely.

**Set it from a measurement, never a guess:** time one warm cycle of the exact test scope
first (`time mix test.json <paths>`), then allow 5–10×. On bourse a *warm* cycle with zero
recompilation was 6.89 s — already 69 % of the default budget.

### Reading a run — the progress legend is not in `--help`

| Symbol | Result | Meaning |
|---|---|---|
| `·` green | `:killed` | a test caught the mutation — good |
| `×` red | `:survived` | **the finding** — line runs, nothing asserts it |
| `-` yellow | `:invalid` | mutant did not compile |
| `?` magenta | `:timeout` | budget exceeded — see the timeout section |
| `≡` gray | `:equivalent` | semantically identical to the original, correctly discounted |
| `∅` gray | `:no_coverage` | no test reaches the line |

A wall of `?` or `-` with no `·`/`×` means the run measured **nothing** — read it as a
broken harness, never as a score.

**Use `--format terminal --verbose` for anything long.** `--format json` emits only at the
end, so a multi-hour run shows no progress and cannot be judged mid-flight.

### 🚨 Always `--no-filter --no-optimize`

Two independent defaults can silently reduce the measured set to nothing and still exit 0:

- **The file filter** drops modules with **≥ 3 `@callback`** even when they carry their own
  logic (threshold is `count >= 3`). Behaviour-heavy surfaces — signing dispatchers, adapters
  — vanish without a word.
- **The optimizer** (on by default) can reduce the mutation set to **0** and exit 0.
  `--no-filter` alone does not close this.

*History, so scores are never compared across versions:* before 0.9.0 the filter read a
`@behaviour` **attribution** as a behaviour *definition*, so every implementing file was
skipped. Measured against bourse's `lib/`: `"Behaviour definition"` skips fell **28 → 1** on
0.9.0. Any pre-0.9.0 score was taken over a much smaller surface and with `StatementDeletion`
never applied — expect a re-baseline to read **lower**, and read that as the removed defect,
not a regression.

### Scale — probe one file before scaling

Mutant counts are far larger than they look. On bourse's signing surface: **2355 mutants for
one 200-line module**, **7099 for 14 files**. At ~7 s per mutant that is hours even fully
parallel.

**The working order** — doing it in reverse costs hours:

1. Time one warm test cycle for the intended scope.
2. Set `--timeout` to 5–10× that.
3. Run **one file** with `--verbose` and confirm real `·`/`×` verdicts appear.
4. Only then widen `--files`.

`--coverage-guided` (run only tests covering the mutated line) and `--since <ref>` (only lines
changed since a git ref) are the two levers that make a repeated audit affordable.

### 🚨 Sandbox hazards

- **Under a narrow `--test-paths`, the sandbox fixture path is a symlink into the real
  project.** A test that writes inside `test/` therefore mutates **real repository files**.
  (New in 0.9.0 — on 0.8.3 the same write went nowhere.) Before narrowing `--test-paths`,
  check that writing tests target `System.tmp_dir!()`.
- **Only `test/`, `priv/` and `config/` are copied into the sandbox.** Fixtures outside those
  three are missing, so every mutant returns `:invalid` and the score reads 0 %.

### Fixed in 0.9.1 — the map-update swap

Through 0.9.0, `FunctionCall` swapped the arguments of `%{s | k: v}` and emitted an AST shape
no parser produces, so `Code.Normalizer` raised `FunctionClauseError`. There was no crash —
the mutant landed as `:invalid` and dropped out of the denominator, costing mutations
**silently**. Measured on bourse before the fix: 36 hits across 15 of 15 inspected files.
0.9.1 visits the operands instead of the `|` node. **An invalid-heavy run taken on ≤ 0.9.0
is not comparable to one taken after** — re-baseline rather than reading the change as a
regression.

**A second invalid-producing cause is still open.** On bourse's `hmac_recipe.ex` the fix
added 11 mutants and left the invalid count at exactly 370 across both versions — ~16 % of
the mutation set, removed from the denominator with no error. Treat a double-digit invalid
percentage as an unexplained hole in the measurement, not as a property of the code.

### Key flags

| Flag | Purpose |
|---|---|
| `--files <pattern>` | Directory, file, or glob (default `lib`); `--path` is a synonym |
| `--test-paths <paths>` | Comma-separated test dirs/files/globs (default `test`) — see the symlink hazard |
| `--timeout <ms>` | Per-mutant test budget (default 10 000 — **raise it**) |
| `--no-filter` | Disable file filtering — required |
| `--no-optimize` | Disable mutation optimization — required |
| `--verbose` | Per-mutant progress; essential for any long run |
| `--format terminal\|json\|html` | `terminal` for interactive runs, `json` for archiving a finished one |
| `--coverage-guided` | Run only tests covering the mutated line |
| `--since <ref>` | Mutate only lines changed since a git ref |
| `--mutators <list>` | Restrict the 18 strategies |
| `--fail-at <score>` | Threshold — **do not use**, see the flicker section |

### Does NOT cover

- Whether the code is *correct* — a killed mutant proves a test reacts, not that the
  expectation is right. A golden computed from the same wrong constant kills mutants happily.
- External / provider semantics. Mutation testing grades the suite against itself; it is a
  regression detector on your own code, never an oracle for anything outside it.
- Clone detection (→ ex_dna), lint anti-patterns (→ ex_slop/Credo), type errors (→ dialyzer).

### Provenance

Flicker measurement, symlink hazard, sandbox fixture scope and the `FunctionCall` defect:
upstream_repos session, 2026-08-26, `upstream_repos/_ours/muex/quirks.md` §1–§13.
Timeout diagnosis, progress legend, behaviour-filter 28 → 1 and the mutant-count figures:
measured on bourse, 2026-08-27.
