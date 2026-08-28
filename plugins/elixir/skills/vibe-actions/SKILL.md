---
name: vibe-actions
description: elixir-vibe/actions — shared GitHub Actions and reusable CI workflows for Elixir and Rustler projects. Use when wiring CI for an Elixir or Elixir+Rustler project: setup-elixir/setup-rust composite actions, elixir-ci.yml or elixir-rustler-ci.yml reusable workflows, or elixir-rustler-release.yml NIF precompilation. Reference as elixir-vibe/actions@v1.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/vibe-actions.md — do not edit manually -->

## vibe-actions — Shared GitHub Actions and Reusable Workflows for Elixir/Rustler Projects

**Not a Hex package — GitHub Actions repo only.** Pin by tag: `elixir-vibe/actions@v1`. No `mix.exs` entry.

**Current tag: `v1`** (commit `3dd94dc`, pushed 2026-06-11). All `uses:` references below target `@v1`.

**Two composite actions + three reusable workflows.** `setup-elixir` and `setup-rust` are composites (called from `steps:`); `elixir-ci.yml`, `elixir-rustler-ci.yml`, and `elixir-rustler-release.yml` are reusable (`workflow_call`, referenced from `jobs:`).

**Default matrix: Elixir 1.20 / OTP 29 (latest) + Elixir 1.19 / OTP 27 (minimum).** Both pairs configurable per-input; `run-min: false` skips the minimum job entirely.

**Caveat:** `elixir-rustler-release.yml` requires `contents: write` permission at the calling workflow level — it uploads artifacts and creates GH release assets via `softprops/action-gh-release@v2`.

**Does NOT cover:** `mix ci` definition (that's your repo's `mix.exs` alias), per-module coverage gating, Sobelow, Credo, Doctor (those live in `harness.yml` from `elixir-ci-harness`). The vibe workflows delegate the entire CI command to the caller via `latest-command` / `min-command`.

---

### Composite Actions

#### `setup-elixir` (set up BEAM with caching)

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: elixir-vibe/actions/setup-elixir@v1
    with:
      elixir-version: "1.20"   # required
      otp-version: "29"         # required
      working-directory: .      # optional; default "."
      cache-prefix: mix         # optional; prefixes deps/_build + PLT cache keys
      restore-deps-cache: "true"   # optional; set "false" to skip
      restore-plt-cache: "true"    # optional; set "false" to skip dialyxir cache
      deps-command: mix deps.get   # optional; override for umbrella or custom install
  - run: mix ci
```

Internally calls `erlef/setup-beam@v1` then `actions/cache@v4` twice (deps+`_build`, then `dialyxir *.plt`). Cache key shape: `{os}-mix-{otp}-{elixir}-{hashFiles(mix.lock)}` with two restore-key fallbacks.

#### `setup-rust` (Rust toolchain + Cargo cache)

```yaml
steps:
  - uses: elixir-vibe/actions/setup-rust@v1
    with:
      rust-toolchain: stable         # optional; or "1.95.0" to pin
      rust-profile: minimal          # optional; rustup profile
      rust-components: "rustfmt,clippy"  # optional; comma-separated
      rust-targets: ""               # optional; comma-separated cross targets
      rust-cache-workspaces: ". -> target"  # optional; Swatinem/rust-cache format
      rust-cache-prefix: rust        # optional; prefix for cache keys
      restore-rust-cache: "true"     # optional; set "false" to skip
```

Uses `Swatinem/rust-cache@v2`. Multi-workspace: newline-separated `"native/foo -> target\nnative/bar -> target"`.

---

### Reusable Workflows

#### `elixir-ci.yml` (pure Elixir CI)

Minimal caller — all inputs are optional:

```yaml
# .github/workflows/ci.yml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
permissions:
  contents: read
jobs:
  ci:
    uses: elixir-vibe/actions/.github/workflows/elixir-ci.yml@v1
```

Full input reference:

| Input | Default | Notes |
|-------|---------|-------|
| `latest-elixir` | `"1.20"` | Primary job Elixir version |
| `latest-otp` | `"29"` | Primary job OTP version |
| `min-elixir` | `"1.19"` | Minimum check Elixir version |
| `min-otp` | `"27"` | Minimum check OTP version |
| `working-directory` | `.` | Directory containing `mix.exs` |
| `deps-command` | `mix deps.get` | Override for custom dep install |
| `latest-command` | `mix ci` | Command run on latest pair |
| `min-command` | `mix compile --warnings-as-errors && mix test` | Command run on minimum pair |
| `run-min` | `true` | Set `false` to skip the minimum job |
| `restore-deps-cache` | `true` | Pass through to `setup-elixir` |
| `restore-plt-cache` | `true` | Pass through to `setup-elixir` |

Custom commands example:

```yaml
jobs:
  ci:
    uses: elixir-vibe/actions/.github/workflows/elixir-ci.yml@v1
    with:
      latest-command: mix ci
      min-command: mix compile --warnings-as-errors && mix test
```

#### `elixir-rustler-ci.yml` (Elixir + Rustler NIF CI)

Same Elixir inputs as above, plus Rust-specific ones:

| Input | Default | Notes |
|-------|---------|-------|
| `rust-toolchain` | `stable` | Or `"1.95.0"` to pin |
| `rust-profile` | `minimal` | Rustup profile |
| `rust-components` | `rustfmt,clippy` | Comma-separated |
| `rust-targets` | `""` | Comma-separated; for cross compilation |
| `rust-cache-workspaces` | `". -> target"` | Swatinem/rust-cache format |
| `rust-cache-prefix` | `rust` | Prefix for Rust cache keys |
| `checkout-submodules` | `"false"` | Pass `recursive` for git submodules |
| `apt-packages` | `""` | Space-separated Ubuntu packages (`libfontconfig1-dev ...`) |
| `extra-env` | `""` | Newline-separated `KEY=VALUE` pairs injected before deps + CI |
| `restore-rust-cache` | `true` | Set `false` to skip Cargo cache |

Single workspace with apt packages:

```yaml
jobs:
  ci:
    uses: elixir-vibe/actions/.github/workflows/elixir-rustler-ci.yml@v1
    with:
      rust-toolchain: stable
      rust-cache-workspaces: native/my_app_nif -> target
      apt-packages: libfontconfig1-dev libfreetype6-dev
```

Multiple Rust crates + extra env:

```yaml
jobs:
  ci:
    uses: elixir-vibe/actions/.github/workflows/elixir-rustler-ci.yml@v1
    with:
      rust-toolchain: "1.95.0"
      rust-profile: default
      rust-cache-workspaces: |
        . -> target
        native/my_app_lint_nif -> target
        native/my_app_fmt_nif -> target
      extra-env: |
        MY_APP_BUILD=1
```

#### `elixir-rustler-release.yml` (precompiled NIF builds on tag push)

Builds `rustler_precompiled` archives via `philss/rustler-precompiled-action@v1.1.4` and uploads to GH release. Triggers on `push: tags: ["v*"]` at the caller.

```yaml
# .github/workflows/release.yml
name: Build precompiled NIFs
on:
  push:
    tags: ["v*"]
permissions:
  contents: write   # required — uploads release assets
jobs:
  build_release:
    uses: elixir-vibe/actions/.github/workflows/elixir-rustler-release.yml@v1
    with:
      project-name: my_app_nif
```

| Input | Default | Notes |
|-------|---------|-------|
| `project-name` | — | **Required.** Rustler crate name |
| `project-dir` | `.` | Dir passed to rustler-precompiled-action |
| `project-version-command` | `sed -n 's/^  @version "\(.*\)"/\1/p' mix.exs \| head -n1` | Extracts version from `mix.exs` |
| `nif-versions` | `'["2.15"]'` | JSON array of NIF versions |
| `jobs` | 5-target matrix (see below) | JSON array of `{target, os, use-cross?}` |
| `cargo-args` | `""` | Extra cargo args |
| `cross-version` | `from-source` | `cross` version |
| `rust-cache` | `true` | Whether to restore Rust cache |
| `rust-cache-prefix` | `rustler-precompiled` | Prefix for cache keys |
| `checkout-submodules` | `"false"` | Pass `recursive` for submodules |

Default job matrix (5 targets):

| Target | OS | Notes |
|--------|----|-------|
| `aarch64-unknown-linux-gnu` | `ubuntu-22.04` | `use-cross: true` |
| `aarch64-apple-darwin` | `macos-14` | — |
| `x86_64-apple-darwin` | `macos-15` | — |
| `x86_64-unknown-linux-gnu` | `ubuntu-22.04` | — |
| `x86_64-unknown-linux-musl` | `ubuntu-22.04` | `use-cross: true` |

---

### Common Issues

| Problem | Cause | Fix |
|---------|-------|-----|
| `contents: write` error on release workflow | Calling workflow has `contents: read` | Add `permissions: contents: write` at calling workflow level |
| PLT cache miss on every run | `restore-plt-cache: false` or mismatched OTP/Elixir versions in key | Verify inputs match `.tool-versions`; default `restore-plt-cache` is `true` |
| Multi-workspace Rust cache not restoring | Newline string not interpreted correctly in YAML | Use literal block scalar `\|` under `rust-cache-workspaces:` |
| `extra-env` values not visible to `deps-command` | `extra-env` is exported before `setup-elixir`, but `deps-command` runs inside `setup-elixir` — order is correct; check KEY=VALUE format | One `KEY=VALUE` per line, no quotes around values |
| Release step skips asset upload | `startsWith(github.ref, 'refs/tags/')` is false | Workflow must be triggered by a tag push, not a branch push |
| `project-version-command` returns empty | `@version` macro indentation differs from default `sed` pattern | Override `project-version-command` with a `grep`/`awk` expression matching your `mix.exs` format |

### DO NOT

1. Pin to a commit SHA directly — the repo exposes `@v1` as a stable moving tag; SHA pins break when `@v1` is updated with bug fixes.
2. Use `setup-rust` in a workflow that doesn't need Rust — adds 30–60 s of toolchain install even with cache.
3. Set `restore-plt-cache: false` unless the repo genuinely has no `dialyxir` dep — the cache is free when PLT doesn't exist.
4. Add `permissions: contents: write` to pure Elixir CI workflows — only the release workflow requires it; the CI workflows need only `contents: read`.
5. Override `deps-command` in `elixir-rustler-ci.yml` — the Rustler workflow defers dep install to after Rust is set up (`deps-command: "true"` in setup-elixir) and runs it as a separate step; overriding `deps-command` input silently replaces the deferred install, not the composite's `"true"` placeholder.

---

### Diff vs Your `elixir-ci-harness` (`harness.yml`)

The vibe workflows and the local harness serve different jobs:

| Dimension | `vibe-actions` workflows | `harness.yml` (elixir-ci-harness) |
|-----------|--------------------------|----------------------------------|
| **Purpose** | Shared CI primitives for elixir-vibe org repos | Deterministic gate for cloud-agent (Codex/Cursor) delegation targets |
| **Version sourcing** | Explicit inputs (`latest-elixir: "1.20"`) | `.tool-versions` file via `erlef/setup-beam version-file:` — no drift |
| **What runs** | Caller-supplied `latest-command` (defaults to `mix ci`) | Fixed steps: format, compile, credo --strict, doctor, sobelow, test.json + coverage gate, dialyzer |
| **Coverage gate** | Not included — delegate to `mix ci` alias | `mix test.json --cover --cover-threshold 85` baked in with tier tuning |
| **Dialyzer PLT cache** | Separate `restore-plt-cache` boolean; bundled in `setup-elixir` | Single `mix-{os}-otp-elixir-{lockfile}` cache covering `deps` + `_build` (includes `dialyxir*.plt`) |
| **Concurrency** | Not set | `cancel-in-progress: true` to avoid queue pileup on rapid pushes |
| **Rust** | `setup-rust` composite + `elixir-rustler-ci.yml` | Not covered |
| **NIF precompile** | `elixir-rustler-release.yml` | Not covered |

**Use vibe-actions when:** the repo is in the elixir-vibe/elixir-volt org and wants to stay on the shared opinionated defaults, or you need Rustler NIF CI/release without wiring it yourself.

**Use harness.yml when:** the repo is a Codex/Cursor delegation target and you need the fixed mechanical gate (credo --strict, doctor, sobelow, coverage threshold) as a named PR check.

**They can coexist:** a Rustler elixir-vibe repo can use `elixir-rustler-ci.yml` for the base Elixir+Rust matrix and `harness.yml` on PRs for the stricter mechanical gate — just call `mix ci` from `latest-command` and let `mix ci` run the harness steps locally.

Portfolio fit: the `elixir-ci-harness` skill and `harness.yml` template in this user's repos are the local equivalent of what vibe-actions provides for the org — understanding both lets you decide which to reference or compose when adding CI to a new elixir-vibe project or migration target.

---

### Dependencies

No Hex deps. External GitHub Actions used internally:

```
erlef/setup-beam@v1          — Elixir/OTP install (setup-elixir)
actions/cache@v4             — deps/_build + PLT cache (setup-elixir)
Swatinem/rust-cache@v2       — Cargo cache (setup-rust, elixir-rustler-ci)
dtolnay/rust-toolchain@stable — Rust install in release workflow
philss/rustler-precompiled-action@v1.1.4 — NIF archive build
actions/upload-artifact@v4   — Artifact upload (release)
softprops/action-gh-release@v2 — GitHub release asset publish
```
