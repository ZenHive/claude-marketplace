---
name: elixir-setup
description: Standard Elixir project setup and dev tooling. ALWAYS invoke when running `mix new`, starting a new Elixir project, or adding dev dependencies. Configures Styler, Credo, Dialyxir, Doctor, Tidewave, ex_unit_json, dialyzer_json, .formatter.exs, and quality gates. For Phoenix projects, use this as base then add phoenix-setup.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/elixir-setup.md — do not edit manually -->

## Elixir Project Setup

Standard dependencies and tooling for Elixir projects (libraries, CLI tools, escripts).

### Recommended Dependencies

| Dep | Purpose | When |
|-----|---------|------|
| ex_unit_json | `mix test.json` — AI-friendly test output | Always |
| dialyzer_json | `mix dialyzer.json` — AI-friendly dialyzer output | Always |
| styler | Auto-formatter extending `mix format` | Always |
| credo | Static analysis | Always |
| dialyxir | Dialyzer wrapper | Always |
| ex_doc | HexDocs + `llms.txt` for AI | Always |
| doctor | Doc quality gates (@moduledoc, @doc, typespecs) | Always |
| tidewave | Dev tools + Claude Code MCP | Always |
| bandit | HTTP server for Tidewave | Non-Phoenix only |
| descripex | `api()` macro, JSON Schema, MCP tools, progressive disclosure | Any project with ≥3 public modules |
| api_toolkit | InboundLimiter, RateLimiter, Metrics, Cache, Provider DSL (see `api-toolkit.md`) | API services |
| ex_dna | AST-based duplication detector | Always |
| ex_ast | AST-based code search/replace | Always |

### Version Pinning

Pinned versions below are starting points. Before adding a dep, check hex for current:
```bash
curl -s https://hex.pm/api/packages/<pkg> | jq -r .latest_stable_version
```
Hex `~>` operator (per `Version.match?/2`):
- `~> X.Y` allows everything up to (not including) the next major: `~> 2.0` = `>= 2.0.0 and < 3.0.0`; `~> 0.3` = `>= 0.3.0 and < 1.0.0`.
- `~> X.Y.Z` allows everything up to (not including) the next minor: `~> 2.0.0` = `>= 2.0.0 and < 2.1.0`; `~> 0.3.1` = `>= 0.3.1 and < 0.4.0`.

For 0.x packages, every minor bump can be breaking under hex semver — so prefer the three-segment form (`~> 0.3.1`) when you want to lock to a single 0.x minor and opt into bumps deliberately.

### mix.exs deps (libraries/non-Phoenix)

```elixir
defp deps do
  [
    {:ex_unit_json, "~> 0.4", only: [:dev, :test], runtime: false},
    {:dialyzer_json, "~> 0.2", only: [:dev, :test], runtime: false},
    {:styler, "~> 1.4", only: [:dev, :test], runtime: false},
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
    {:ex_doc, "~> 0.40", only: :dev, runtime: false},
    {:doctor, "~> 0.23", only: [:dev, :test], runtime: false},
    {:tidewave, "~> 0.5", only: :dev},
    {:bandit, "~> 1.10", only: :dev},      # non-Phoenix only
    {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
    {:ex_ast, "~> 0.12", only: [:dev, :test], runtime: false},
    {:descripex, "~> 0.6"},                # full dep — macros expand at compile time
    {:api_toolkit, "~> 0.1"}               # API services only
  ]
end
```

### Required: cli/0 for preferred_envs

Mix doesn't inherit `preferred_envs` from deps. Without this, `mix test.json`/`mix dialyzer.json` run in `:dev`:

```elixir
def cli do
  [preferred_envs: ["test.json": :test, "dialyzer.json": :dev]]
end
```

**Gotcha:** `preferred_envs` only fires for top-level Mix invocations. **Inside an alias step it's ignored** — the step inherits the parent alias's env (usually `:dev`). To run an alias step in `:test`, wrap with `cmd`: `"cmd MIX_ENV=test mix test.json ..."`. See § "Standard Aliases" below.

### Formatter

Add `Styler` to `.formatter.exs` plugins: `plugins: [Styler]`.

### Standard Aliases — `check.fast` + `precommit` + `precommit.full`

Three tiers split by **inner-loop cost**. The marketplace's `pre-commit-unified.sh` hook runs its **own** inline gate at commit time (format · compile · credo · doctor · sobelow · mix_audit · ash — **no tests, no dialyzer, no ex_doc**); it does **not** invoke these aliases. The aliases are for manual / CI runs: `precommit` adds the test+cover gate, `precommit.full` adds dialyzer. (`mix docs` belongs in CI / a manual run — too slow for the commit gate.)

```elixir
defp aliases do
  [
    # TagTODO/TagFIXME stay on in .credo.exs for visibility (`mix credo` shows them);
    # the gate excludes them so it fails only on real regressions, not tracked debt.
    "check.fast": [
      "format --check-formatted",
      "compile --warnings-as-errors",
      "credo --strict --ignore TagTODO,TagFIXME"
    ],
    # Manual / CI gate (NOT run by the commit hook). Drops dialyzer; keeps tests + sobelow + doctor.
    precommit: [
      "format --check-formatted",
      "compile --warnings-as-errors",
      "credo --strict --ignore TagTODO,TagFIXME",
      "doctor --raise",
      # `preferred_envs` (cli/0) is ignored for alias steps — set MIX_ENV explicitly.
      "cmd MIX_ENV=test mix test.json --quiet --cover --cover-threshold 85 --summary-only --exclude integration",
      "sobelow --skip"                 # --skip honors inline # sobelow_skip; drop on pure libs
    ],
    # CI mirror — adds dialyzer. Matches `elixir-ci-harness` `harness.yml`.
    "precommit.full": ["precommit", "dialyzer.json --quiet"]
  ]
end
```

**Three tiers, by inner-loop cost:**

- `mix check.fast` — format + compile-with-warnings + credo. Seconds. Run after every meaningful edit.
- `mix precommit` — adds doctor, test+cover gate, sobelow. Tens of seconds. **Manual / pre-handoff gate** — the commit hook does *not* run this; use it before handing work off when you want the test+cover gate locally.
- `mix precommit.full` — adds dialyzer. Minutes (mostly dialyzer). Run before handing off to a reviewer / matches CI; **not** for the hook path.

**Flag rationale:**

- **`credo --strict --ignore TagTODO,TagFIXME`.** TODO/FIXME are tracked-debt visibility (`development-philosophy.md` § "TODO Comment Requirements"), not regressions. Standalone `mix credo` still surfaces them so an agent can SEE the debt; the gate doesn't fail on them so PRs aren't blocked by accumulated tags.
- **`doctor --raise`.** Overrides `.doctor.exs` `raise: false` to gate CI without changing local behavior. Redundant if the repo already sets `raise: true`, but harmless.
- **`test.json --cover --cover-threshold 85 --summary-only --exclude integration`.** 85% is the project default (cartouche's empirical floor; meaningful bump from 80%, leaves headroom under typical ~87% project coverage). Critical-path repos (signing, money, crypto, wire-format encoders) raise to `95`. `--exclude integration` because local + CI lack credentials/network for live services; see `elixir-ci-harness` SKILL.md § "Integration Tag Exclusion" for the separate-workflow pattern if integration coverage is needed.
- **`sobelow --skip`.** `--skip` makes sobelow honor inline `# sobelow_skip` annotations (without it they're ignored — see "Sobelow skip/config semantics" below). Phoenix / Plug / web-facing apps only — drop on pure libraries. Pass `--config` instead if the project keeps its settings in `.sobelow-conf`.
- **`dialyzer.json --quiet`** (in `precommit.full`). Agent-friendly JSON variant (`harness.yml` uses plain `mix dialyzer` because GH Actions consumes human-readable output; agents prefer JSON). For pipeline parsing: `dialyzer.json --quiet --output /tmp/dialyzer.json` then jq.

**Sobelow skip/config semantics** (source-verified, `nccgroup/sobelow`; flag behavior drifts across versions — re-check before relying):

- Inline `# sobelow_skip [...]` annotations are honored **only with `--skip`** — bare `mix sobelow` ignores them (`lib/sobelow.ex`: `if get_env(:skip), do: combine_skips(...), else: funs`).
- The `.sobelow-skips` *fingerprint* file (written by `mix sobelow --mark-skip-all`) is read **unconditionally** — honored even without `--skip`. (So `--skip` and `.sobelow-skips` are two different mechanisms; the flag governs only the inline annotations.)
- `.sobelow-conf` (written by `--save-config`) loads **only when `--config` is passed**, and the conf then **replaces** all CLI opts (`lib/mix/tasks/sobelow.ex`) — so `mix sobelow --config --format json` silently drops `--format json` unless the conf itself sets `format:`. **Bare `mix sobelow` does NOT auto-load `.sobelow-conf`.**
- Therefore: to honor inline skips, pass `--skip`; to honor a `.sobelow-conf`, pass `--config` and put `format:` / `out:` inside the conf (not on the CLI). The marketplace pre-commit hook always passes `--skip` for this reason and does not pass `--config` (it would break its `--format json` JSON parse).

**Why split, not one alias.** The commit hook enforces a fast inline gate (no tests, no dialyzer) so the inner loop stays cheap and deterministic. The aliases layer the slower checks back on for deliberate runs: `precommit` adds the test+cover gate for pre-handoff, `precommit.full` adds dialyzer to match CI (`harness.yml`). Keeping them separate means the slow steps run where no inner-loop tax applies — CI, or a human before opening a PR — never blocking every commit.

Why no `try/rescue` aggregator by default: an agent that wants "all failures in one pass" can override at the call site (`mix format --check-formatted; mix credo --strict --ignore TagTODO,TagFIXME; mix test.json ...` joined with `;` runs every step regardless of exit). The default alias stays fail-fast because the cheapest-fail-first ordering means the agent rarely needs the aggregate — fixing the first failure usually unblocks the rest.

### Tidewave (Non-Phoenix)

Three files must agree on PORT. Registry: `~/.claude/tidewave-ports.md`. MCP registration is **project-scope** only (`.mcp.json`) — never user-scope; local/user scope collides across projects.

1. `~/.claude/tidewave-ports.md` — registry row
2. `mix.exs` alias:
   ```elixir
   tidewave: ["run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: PORT) end)'"]
   ```
3. `.mcp.json` (project root):
   ```json
   {"mcpServers":{"tidewave":{"type":"http","url":"http://localhost:PORT/tidewave/mcp"}}}
   ```

Run with `iex -S mix tidewave`. Restart Claude Code after creating/changing `.mcp.json`. Check scope with `claude mcp get tidewave`; remove user/local if present.

### Tidewave Recompile Gotcha

Tidewave runs in the same BEAM as the IEx session. After editing source, the old bytecode stays loaded — call `recompile()` via `project_eval` (or `r(SomeModule)` for one module). For the full MCP tool list, see the `tidewave-guide` skill.

### Dialyzer PLT — `:apps_direct` to avoid OOM

Default `plt_add_deps: :app_tree` walks the full transitive dep tree. For libraries / non-Phoenix projects, tidewave + bandit (dev) drag in plug, finch, mint, gun, hpax, cowlib, thousand_island, websock, mime — none of which are in `lib/`'s call graph. PLT bloats to ~800 modules and on macOS routinely OOM-kills the build at the deps-dev step (verified: peak RSS ~8 GB before kill).

Per dialyxir docs, the canonical OOM mitigation is `plt_add_deps: :apps_direct` — load only **direct** runtime deps, no transitive recursion:

```elixir
defp dialyzer do
  [
    # OOM mitigation: skip transitive deps (default is :app_tree).
    # Tidewave/bandit's HTTP stack (plug, finch, mint, gun, cowlib, etc.)
    # is not in lib/ call graph and bloats PLT to ~800 modules.
    plt_add_deps: :apps_direct,
    plt_add_apps: [:mix],
    plt_local_path: "priv/plts",
    plt_core_path: "priv/plts",
    ignore_warnings: ".dialyzer_ignore.exs"
  ]
end
```

**Verified result** on a typical onchain-stack lib (onchain_evm): 794 → 236 modules in deps-dev PLT (~70% reduction), full PLT build in 18.6s vs OOM-killed at ~10min.

**PLT location: `priv/plts/` not `_build/dialyzer/`.** PLTs in `_build/` get nuked on `mix clean` / `rm -rf _build`. Every cleanup costs a 5-10min from-scratch rebuild. `priv/plts/` survives `_build` wipes. Add `/priv/plts/` to `.gitignore`. To migrate: `find _build/dialyzer priv/plts -name '*.plt' -delete 2>/dev/null` then `mix dialyzer --plt`.

**Trade-off ladder** (per dialyxir docs):

| Option | Aggressiveness | When |
|---|---|---|
| `plt_ignore_apps: [:foo]` | Least | A few specific deps cause warnings or PLT bloat |
| `plt_add_deps: :apps_direct` | **Moderate — recommended default** | Transitive HTTP/SDK trees cause memory issues |
| `plt_apps: [explicit list]` | Most | Surgical replace; you know exactly what to include |

`:apps_direct` plus `plt_add_apps:` for any specific extras (`:mix`, `:descripex`, etc.) covers the typical library case. For project-specific optional stacks the lib doesn't call (e.g. cartouche's `:google_api_cloud_kms, :goth, :tesla, :jose`), layer `plt_ignore_apps:` on top.

**Phoenix exception:** Phoenix apps use bandit/plug at runtime and depend on transitive deps (Ecto adapters, etc.). Default `:app_tree` is usually correct; only switch to `:apps_direct` if memory is a problem, and verify no real warnings get suppressed.

**Runtime-Req exception:** if your lib has `{:req, "~> X.Y"}` as a runtime dep (not just dev-via-tidewave), `:apps_direct` excludes Req's transitive HTTP stack (finch, mint). Usually fine — Req-call warnings get suppressed via `~r/Function Req\./` in `.dialyzer_ignore.exs`. If "function unknown" warnings about Finch/Mint surface, either add them via `plt_add_apps: [:finch, :mint, ...]` or extend the regex.

### ex_doc llms.txt

`mix docs` generates `doc/llms.txt` alongside HTML — Markdown optimized for LLMs. Published packages have it at `https://hexdocs.pm/<package>/llms.txt`. Use for loading library context.

### ExDNA — Duplication Detection

```bash
mix ex_dna                            # scan for duplicates (Type I — exact)
mix ex_dna --literal-mode abstract    # Type II — catch renamed variables
mix ex_dna --min-similarity 0.85      # Type III — near-miss (structural similarity)
mix ex_dna --min-mass 50              # only flag larger clones
mix ex_dna --max-clones 10            # CI budget — exit 1 only above threshold
mix ex_dna --format json              # machine-readable
mix ex_dna --format html              # self-contained browsable report
mix ex_dna --format sarif             # GitHub Code Scanning
mix ex_dna.explain 3                  # anti-unification breakdown of one clone
```

Config: `.ex_dna.exs` in project root. Suppress intentional dupes with `@no_clone true`. Credo integration: add `{ExDNA.Credo, []}` to `.credo.exs`. LSP server pushes diagnostics to Expert/ElixirLS.

### ExAST — AST Search & Replace

```bash
mix ex_ast.search 'IO.inspect(_)'           # find debug leftovers
mix ex_ast.search 'IO.inspect(...)'         # ellipsis — any arity
mix ex_ast.replace 'dbg(expr)' 'expr'       # remove dbg, keep expression
mix ex_ast.replace --dry-run old new        # preview
mix ex_ast.diff lib/old.ex lib/new.ex       # syntax-aware diff
```

Patterns: `_` = wildcard, named vars (`expr`) capture and carry to replacement. `...` = zero-or-more (args, list items, block body). Structs/maps match partially. `_` in function-name position of `def`/`defp` patterns matches the function name even when arguments are present (e.g. `defp _(_), do: _` matches `defp helper(x), do: x + 1`). The `piped()` selector predicate distinguishes form inside the `~p`/`where` DSL — `where(piped())` matches only `|>` calls, `where(not piped())` matches only direct calls. `ExAST.search_many/3` and `ExAST.Patcher.find_many/3` run multiple named patterns in a single traversal, returning matches tagged with `:pattern`. See `development-commands.md` for the full surface (pipe awareness, `--inside`/`--not-inside`, multi-node, `~p` sigil, quoted patterns, AST/zipper input).

### Quality Gates

- Dialyzer: 0 warnings (mandatory)
- Credo: 0 issues in `--strict`
- Doctor: all public modules documented
- Tests: 80%+ coverage (95% for critical business logic)
