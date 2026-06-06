---
name: elixir-ci-harness
description: Use when adding deterministic CI to an Elixir repo that's a cloud-agent delegation target (Codex/Cursor PRs need shared harness evidence). Provides a copy-ready `harness.yml` GitHub Actions workflow that runs format / compile (warnings-as-errors) / credo --strict / doctor / sobelow / test.json with coverage gate / dialyzer on every PR push. Closes the Codex-env-blocked-hex.pm gap by making harness output a PR check rather than a local re-run. Sources Elixir/OTP versions from `.tool-versions` (no matrix-pin drift). Documents threshold tuning (default 85% project / 80% standard / 95% critical), integration-tag exclusion, branch-trigger customization, the cache shape that covers dialyxir's PLT path, and a forward-compat multi-version variant.
allowed-tools: Read, Bash, Grep, Glob
---

# Elixir CI Harness — Deterministic Gate for Delegation-Target Repos

Copy a ready GitHub Actions workflow into the target repo so every PR push runs the full Elixir harness as a PR check. Closes the Codex-Cloud-no-hex.pm gap: even when the cloud agent's env can't run `mix dialyzer` or `mix doctor`, the PR check does.

## When to Use

- **Adding CI to a delegation target.** A repo receives `[CX]` (Codex) or `[CSR]` (Cursor) PRs and currently has no shared harness gate. Without CI, every PR review re-runs the harness locally (15+ minutes per PR) and the cloud agent ships drift.
- **Auditing existing CI.** A repo has a workflow but it's missing canonical steps (no coverage gate, no `--strict` credo, no `--warnings-as-errors`, runs only on push not PR).
- **Baseline for GH-native auto-merge.** `gh pr merge --auto` (wired at PR-open per `plugins/staged-review/templates/auto-merge.md`) holds the merge until required status checks pass. This skill is the prerequisite that makes those checks present — the `harness` job is the canonical required check.

Skip if the repo isn't a delegation target *and* has no plans to be — local hooks already cover the gates for solo work.

## Why Deterministic CI Is Load-Bearing for Delegation

- **Codex Cloud has no hex.pm.** It cannot run `mix deps.get`, `mix dialyzer`, or anything that touches third-party packages. Code can ship without `mix test` evidence.
- **Cursor Cloud has hex.pm but no enforced harness pre-PR.** Cursor SHOULD run the harness; observed PRs sometimes ship with format/credo drift anyway.
- **CI is the shared canonical gate.** Visible to user, agent, and PR review tooling. The reviewer reads `gh pr checks <n>` instead of re-running mix locally.

The shift: **CI gates the mechanical concerns; local Claude judges the design.** Token economics flip — implementation goes to the cloud agent, verification goes to deterministic CI, judgment stays local but is fast.

## Quick Adoption

1. Copy `templates/harness.yml` to `<target-repo>/.github/workflows/harness.yml`
2. Customize four inputs (see "Customization Points" below): branch, MIX_ENV, coverage threshold, integration tag
3. Confirm required deps + config files exist (see "Required Setup")
4. Commit, push to a PR branch, watch the `Harness` check appear under the PR
5. Verify by intentionally breaking format or credo on a throwaway commit — the gate should fail loudly

## Required Setup in Target Repo

The template assumes these are present (per `~/.claude/includes/elixir-setup.md` standard setup):

- **`ex_unit_json` dep** — `mix test.json` is the test step
- **`dialyxir` dep** — for `mix dialyzer`
- **`doctor` dep + `.doctor.exs`** — or remove the doctor step
- **`sobelow` dep + `.sobelow-conf`** — or remove the sobelow step
- **`mix.exs` `cli/0` with `preferred_envs`** — so `mix test.json` runs in `:test`
- **`.tool-versions`** at repo root — single source of truth for Elixir/OTP versions; the workflow reads from this so CI and local dev never drift

If any are missing, the corresponding step fails until added. Don't paper over with `continue-on-error` — the missing dep is a real gap.

## Customization Points

The template ships with four marked customization points:

| Point | Default | When to change |
|---|---|---|
| Branch trigger | `[development]` | Repo's main long-lived branch (`main`, `master`, `trunk`) |
| `MIX_ENV` | `test` | Repo-specific test env (rare) |
| Coverage threshold | `85` | See "Threshold Tuning" below |
| Integration tag | `integration` | Repo's tag name if the convention differs |

Edit these inline — they're commented in the template.

## Threshold Tuning

Three real options, grounded in `~/.claude/includes/critical-rules.md` § "RAISE COVERAGE BEFORE MUTATING":

### Standard tier — 80%

```yaml
run: mix test.json --cover --cover-threshold 80 --summary-only --exclude integration
```

Matches the rule's standard-tier minimum. Right when coverage is just starting to take hold and the repo would block too often at higher thresholds.

### Project default — 85% (template ships this)

```yaml
run: mix test.json --cover --cover-threshold 85 --summary-only --exclude integration
```

Cartouche's empirically-tuned floor: meaningful bump from 80%, leaves headroom under their current ~87%. Right for most working repos. Inline comment in the template captures the reasoning so future adopters can re-justify or change.

### Critical tier — 95%

```yaml
run: mix test.json --cover --cover-threshold 95 --summary-only --exclude integration
```

Right for codebases where everything handles signing, money, cryptographic operations, or wire-format encoders. Most repos are mixed-tier and shouldn't apply 95% globally — see the per-module ratchet below for the targeted approach.

### Per-module 95% ratchet (advanced, optional addendum)

For mixed-tier codebases where some modules are critical (signing, key derivation, ABI/RLP encoders) and most aren't, add a second job that runs `mix test.json --cover --cover-threshold 95` against tagged critical tests:

```yaml
- name: Critical-tier coverage gate (>=95%)
  run: mix test.json --cover --cover-threshold 95 --summary-only --only critical
```

This is a separate ratchet, not the default. Cartouche explicitly punted it as "a follow-up." Document `:critical` (or `:tier_critical`, project's choice) tag convention in the repo's `.credo.exs` or test helpers; CI fails only if the tagged subset drops below 95%.

## TagTODO / TagFIXME Design

The template uses:

```yaml
run: mix credo --strict --ignore TagTODO,TagFIXME
```

**Rationale (preserved as inline comment):** TODO/FIXME tags are *tracked-debt visibility*, not regressions. They stay enabled in `.credo.exs` so humans + Claude see them in `mix credo --strict` output during local work, but they don't gate CI. This avoids blocking PRs on known debt accumulated across sessions — the same posture as `~/.claude/includes/cloud-agent-environments.md` § "Credo TODO/FIXME exit code" (Cursor / Codex envs treat exit code 2 with only TODO findings as expected).

Keep `.credo.exs` consistent: `tag_todo` and `tag_fixme` enabled there (visibility), excluded here in the workflow (CI gating).

## `mix doctor --raise` vs `--failed`

The template uses:

```yaml
run: mix doctor --raise
```

**Rationale (preserved as inline comment):** `--raise` overrides `.doctor.exs raise=false` to gate CI without changing local behavior. If a target repo has `.doctor.exs raise: true` already, `--raise` is redundant but harmless; if the repo expects local `mix doctor` to print-not-fail, `--raise` in CI gives you the gate without forcing devs to change their local config.

## Integration Tag Exclusion

The template excludes integration tests by default:

```yaml
run: mix test.json --cover --cover-threshold 85 --summary-only --exclude integration
```

**Rationale:** CI typically lacks credentials, network access to testnets, or live exchange access. Integration tests that hit real services would `flunk` on missing env vars (per `~/.claude/includes/critical-rules.md` § "INTEGRATION TESTS: NEVER SKIP SILENTLY ON MISSING CREDENTIALS").

For repos that genuinely need integration coverage in CI, add a separate `integration.yml` workflow (nightly schedule, secrets injected via repo secrets). Pattern documented; not shipped as a template — integration concerns differ enough per repo (which exchange, which testnet, which secrets) that one template would be misleading.

## Branch Trigger Customization

Default targets `development`:

```yaml
on:
  pull_request:
    branches: [development]
  push:
    branches: [development]
```

Switch to `main` if that's the long-lived branch:

```yaml
on:
  pull_request:
    branches: [main]
  push:
    branches: [main]
```

Or trigger on multiple branches:

```yaml
on:
  pull_request:
    branches: [main, development]
  push:
    branches: [main, development]
```

## Drift-Free Version Sourcing

The template uses:

```yaml
- id: beam
  uses: erlef/setup-beam@v1
  with:
    version-file: .tool-versions
    version-type: strict
```

**Rationale:** `mix format` formats per the dev's installed Elixir version. CI checks against whatever the workflow pins. If those drift (e.g., dev runs Elixir 1.20-rc.4, CI pins 1.18.4), PRs fail on whitespace nobody touched. Sourcing both from `.tool-versions` guarantees they're identical.

`.tool-versions` is the asdf-format file at the repo root:

```
elixir 1.20.0-rc.4-otp-29
erlang 29.0-rc3
```

**Caveat — empty matrix.** Without a matrix scaffold, the single-version path is the only path. The cache key still discriminates by Elixir/OTP version (via `steps.beam.outputs.elixir-version` / `otp-version`, which `setup-beam` populates regardless of how it sourced the version), so multi-runtime caching works if you later expand to a matrix.

## Forward-Compat Multi-Version Variant

`templates/harness-multi-version.yml` is the addendum for repos in mid-migration (e.g., OTP 27 → 29). It runs an explicit matrix where the **primary entry mirrors `.tool-versions` exactly** (drift-free) and adds the in-flight runtime as a secondary entry so dep incompatibilities surface at PR-open time.

**Worked example (cartouche session):** during the OTP 27 → 29 migration, adding OTP 29-RC to a matrix entry would have caught a `meck` pin incompatibility *at PR-open time*, letting Cursor (which can run mix tasks) fix it autonomously without a human round-trip. That's high-leverage during a runtime migration; not needed in steady-state.

**Critical:** the primary entry MUST mirror `.tool-versions` exactly. Drift between primary CI entry and `.tool-versions` reintroduces the format-drift bug this skill exists to solve. Copy from `.tool-versions` when first setting up; re-copy whenever `.tool-versions` changes.

## Caveats

- **Single Elixir/OTP combo by default.** The default template runs the version `.tool-versions` declares. Use the multi-version variant during migrations or when forward-compat coverage is load-bearing.
- **Integration tests excluded.** See "Integration Tag Exclusion" above. Add a separate `integration.yml` if needed.
- **One global coverage threshold.** Per-module tier classification (95% critical vs 80% standard) is a judgment call CI can't make — CI enforces one number. Use the per-module ratchet addendum if mixed-tier matters.
- **PLT cache hit rate.** First run on a fresh branch builds the dialyzer PLT (~1-2 min); subsequent runs hit cache in seconds. The cache step covers the default `_build/<env>/dialyxir_*.plt` path.

## Worked Example Reference

`cartouche/.github/workflows/harness.yml` on the `development` branch is the canonical reference implementation. The cartouche workflow has iterated three times (`ad7fed0` initial → `c4cb0eb` YAML fix → `3a3a79d` "stop gating CI on TagTODO/TagFIXME") and may iterate further. This skill captures *current best practice as a snapshot*, not an immutable template.

When cartouche's workflow evolves, **resync the templates here** — see "Maintaining the Template" below.

**Known follow-up:** at the time this skill was written, cartouche's CI still pinned `1.18.4 / 27.3` while its `.tool-versions` declared `1.20.0-rc.4-otp-29 / 29.0-rc3` — 8 versions of drift, exactly the failure mode this skill exists to solve. Cartouche should adopt the `version-file: .tool-versions` pattern as a follow-up referencing this skill.

## Verification

- **Open a trivial PR** (typo fix on a doc) on the configured branch
- **Confirm `Harness` check appears** under the PR — if not, double-check `on:` matches the PR's base branch
- **Confirm green** — every step passes
- **Intentionally break a gate** on a throwaway commit (e.g., remove a `mix format` invocation, add an unused alias) — confirm the matching step fails with a useful message
- **Check coverage output** — `mix test.json --cover --summary-only` should emit a single coverage line; if the threshold is missed, the step fails with the percentage gap

## Maintaining the Template

The template is a snapshot of cartouche's current best practice. To resync:

```bash
diff -u \
  <(cd ~/_DATA/code/cartouche && git show development:.github/workflows/harness.yml) \
  ~/_DATA/code/claude-marketplace-elixir/plugins/elixir/skills/elixir-ci-harness/templates/harness.yml
```

The diff should show only the customization-point comments this skill adds. If cartouche's workflow has gained new steps or comments, copy them in and update this SKILL.md's threshold/tag/branch sections to match.

## Cross-References

- `~/.claude/includes/elixir-setup.md` — standard deps + `cli/0` for `preferred_envs`
- `~/.claude/includes/critical-rules.md` § "RAISE COVERAGE BEFORE MUTATING" — coverage tier definitions
- `~/.claude/includes/cloud-agent-environments.md` § "CI as the Shared Harness" — how CI closes the Codex-Cloud-no-hex.pm gap
- `plugins/staged-review/templates/auto-merge.md` — GH-native auto-merge (`gh pr merge --auto`) holds merge until required status checks pass; the `harness` job is the canonical required check
- `development-commands` skill — `mix test.json`, `mix dialyzer.json`, `mix credo --strict --format json`
