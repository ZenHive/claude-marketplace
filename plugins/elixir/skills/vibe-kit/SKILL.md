---
name: vibe-kit
description: vibe_kit — Igniter installer for the elixir-vibe toolchain. Use when bootstrapping a project with the vibe analyzer stack (credo, dialyxir, ex_dna, ex_slop, reach) and a mix ci pipeline via Igniter. Overlaps the elixir-setup stack. Covers installer flags, generated config, and the mix ci pipeline.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/vibe-kit.md — do not edit manually -->

## VibeKit — Igniter Installer for the Elixir Vibe Quality Stack

One-command bootstrap: adds `mix ci`, quality-tool deps (Credo, Dialyxir, ExDNA, ExSlop, Reach), and starter config files to a new or existing Mix project.

**Min version: `{:vibe_kit, "~> 0.1", only: [:dev, :test], runtime: false}`.** Published on Hex as of v0.1.5 (June 12, 2026) by `dannote`; MIT license.

**Installer, not a runtime dep.** `mix igniter.install vibe_kit` applies changes and can be removed from `deps` afterwards unless you want `mix vibe_kit.install` to stay available.

**Requires Igniter.** `{:igniter, "~> 0.7"}` must be in deps; without it the install task exits with an error message.

**Portfolio fit: this installer is a *subset* of your `elixir-setup` skill.** Your skill already wires `ex_unit_json`, `dialyzer.json`, `sobelow`, `mix doctor`, `tidewave`, and PostToolUse hooks — things VibeKit does not touch. Use VibeKit to document what the ecosystem *expects* as a baseline `mix ci`; reference your skill for the fuller picture. Both describe `credo --strict`, `dialyzer`, `ex_dna`, `reach.check --arch --smells` — know they overlap.

**Caveat:** v0.1.x — API surface is small and stable, but the library is young. Pin `~> 0.1` to stay on the 0.1.x series.

**Does NOT cover:** PostToolUse hooks, `ex_unit_json`/`dialyzer.json` JSON reporters, Sobelow, `mix doctor`, Tidewave, runtime dependencies, or test configuration beyond `plt_add_apps: [:ex_unit]`.

---

### Installation

**Into an existing project:**
```sh
mix igniter.install vibe_kit
```

**Into a new project:**
```sh
mix igniter.new my_lib --install vibe_kit
```

**Run the suite:**
```sh
mix ci
```

---

### What Gets Applied

VibeKit is an Igniter task (`Mix.Tasks.VibeKit.Install`) that mutates `mix.exs` and creates config files in one pass:

| Change | Detail |
|--------|--------|
| `mix ci` alias added to `mix.exs` | See pipeline below |
| `def cli` updated | `preferred_envs: [ci: :test]` |
| `dialyzer: [plt_add_apps: [:ex_unit]]` | Appended if not present |
| Deps added | Latest Hex versions of credo, dialyxir, ex_dna; optionally reach, ex_slop |
| `.credo.exs` created/patched | ExSlop plugin prepended to the `"default"` config's `plugins`; relaxes `Credo.Check.Design.AliasUsage` and `ExSlop.Check.Readability.NarratorDoc` |
| `.reach.exs` created | Starts as `[]`; fill in layer/boundary policies as architecture settles |
| `AGENTS.md` / `CLAUDE.md` | Optional; created only with `--agents-md` / `--claude-md` |

**Default `mix ci` pipeline** (exact order):
```elixir
ci: [
  "compile --warnings-as-errors",
  "format --check-formatted",
  "test",
  "credo --strict",
  "dialyzer",
  "ex_dna --max-clones 0",    # omitted if --no-strict-clones
  "reach.check --arch --smells" # omitted if --no-reach
]
```

---

### Installer Options

All options are boolean flags. Defaults shown:

| Flag | Default | Effect |
|------|---------|--------|
| `--no-reach` | reach: true | Skip Reach dep + `reach.check --arch --smells` step |
| `--no-strict-clones` | strict_clones: true | Run `ex_dna` instead of `ex_dna --max-clones 0` |
| `--no-ex-slop` | ex_slop: true | Skip ExSlop dep + `.credo.exs` plugin setup |
| `--agents-md` | false | Create `AGENTS.md` with VibeKit quality gate section |
| `--claude-md` | false | Create `CLAUDE.md` with VibeKit quality gate section |

Combine freely:
```sh
mix igniter.new my_lib \
  --install vibe_kit \
  --no-reach \
  --no-ex-slop \
  --agents-md
```

---

### Generated `.credo.exs` Shape

VibeKit patches an existing `.credo.exs` (or creates one) to prepend ExSlop and relax two checks:

```elixir
%{
  configs: [
    %{
      name: "default",
      plugins: [{ExSlop, []}],          # prepended; idempotent on re-run
      checks: [
        {Credo.Check.Design.AliasUsage, false},          # relaxed for generated code
        {ExSlop.Check.Readability.NarratorDoc, false}    # relaxed for generated code
      ]
    }
  ]
}
```

The patcher uses `ExAST.Pattern.match` + `ExAST.Patcher.replace_all` to surgically update AST, so hand-customized `.credo.exs` files are patched in-place rather than overwritten (if `"default"` config exists).

---

### Keeping the Installer Available

After `mix igniter.install vibe_kit` the dep can be removed — the pipeline is baked into `mix.exs`. To keep `mix vibe_kit.install` available for teammates or CI re-runs:

```elixir
{:vibe_kit, "~> 0.1", only: [:dev, :test], runtime: false}
```

---

### Included Tools (what each does in this context)

| Tool | Dep | Role in `mix ci` |
|------|-----|-----------------|
| Credo | `{:credo, "~> 1.7"}` | Static analysis + ExSlop plugin checks |
| Dialyxir | `{:dialyxir, "~> 1.4"}` | Dialyzer type-checking via `mix dialyzer` |
| ExDNA | `{:ex_dna, "~> 1.5"}` | AST-aware clone detection; `--max-clones 0` enforces zero-tolerance |
| ExSlop | `{:ex_slop, "~> 0.4"}` | Credo plugin for generated-code quality patterns |
| Reach | `{:reach, "~> 2.6"}` | Architecture policy + cross-function smell checks |

All added as `only: [:dev, :test], runtime: false`.

---

### Redundancy vs. Your `elixir-setup` Skill

VibeKit's `mix ci` is a **public ecosystem convention** — what the elixir-vibe tools expect as a CI baseline. Your `elixir-setup` skill is a **superset** with project-specific additions:

| Surface | VibeKit | Your `elixir-setup` skill |
|---------|---------|--------------------------|
| `credo --strict` | yes | yes |
| `dialyzer` | yes | yes (+ `dialyzer.json` reporter) |
| `ex_dna --max-clones 0` | yes | yes |
| `reach.check --arch --smells` | yes (default) | yes |
| `ex_unit_json` JSON reporter | no | yes |
| `sobelow` security scanner | no | yes |
| `mix doctor` coverage | no | yes |
| Tidewave MCP integration | no | yes |
| PostToolUse hooks | no | yes |

When contributing to an elixir-vibe ecosystem project, `mix ci` is the gate. On your own projects, use your full skill pipeline.

---

### Common Issues

| Problem | Cause | Fix |
|---------|-------|-----|
| `mix vibe_kit.install` task not found | Igniter not in deps | Add `{:igniter, "~> 0.7"}` and run `mix deps.get` |
| `mix ci` alias already exists, warns | `add_alias` with `if_exists: :warn` | Installer warns and skips — manually merge steps |
| ExSlop checks not running | `.credo.exs` exists but has no `"default"` config name | Rename your config to `"default"` or add ExSlop plugin manually |
| `reach.check` fails on empty `.reach.exs` | `[]` is valid; Reach treats it as no-policy | This is correct; populate as architecture solidifies |
| `ex_dna --max-clones 0` blocks CI on generated code | Clones in generated/vendor files | Use `--no-strict-clones` flag or configure ExDNA ignore paths |

---

### DO NOT

1. Add `vibe_kit` as a runtime dep — it's an installer; `runtime: false` is correct.
2. Edit `.credo.exs` ExSlop section by hand then re-run `mix igniter.install vibe_kit` — the patcher will re-prepend ExSlop (idempotent, safe, but redundant).
3. Run `mix vibe_kit.install` (the Igniter task form) directly — use `mix igniter.install vibe_kit` which resolves deps and chains correctly.
4. Assume `--claude-md` and `--agents-md` create a complete agent instructions file — they append a `## VibeKit quality gate` section only; your existing CLAUDE.md is preserved.
5. Confuse this with runtime tooling — nothing from vibe_kit ships to production.

---

### Dependencies

```elixir
# In mix.exs (keep only if you want mix vibe_kit.install to stay available):
{:vibe_kit, "~> 0.1", only: [:dev, :test], runtime: false}

# Required peer dep for the installer to function:
{:igniter, "~> 0.7"}
```

Source: `github.com/elixir-vibe/vibe_kit` | Hex: `hex.pm/packages/vibe_kit`
