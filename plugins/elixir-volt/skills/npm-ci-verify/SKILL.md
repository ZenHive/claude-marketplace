---
name: npm-ci-verify
description: npm_ex CI/CD and installation verification workflows. Use when setting up CI pipelines with npm_ex, debugging lockfile sync issues, ensuring reproducible builds, diagnosing "works locally but fails in CI" problems, or integrating npm_ex into Mix compilers. Covers mix npm.ci, npm.check, npm.verify, npm.doctor, npm.shrinkwrap, the --frozen flag, and the programmatic NPM.CI/NPM.Verify/NPM.Lockfile APIs with correct argument orders.
allowed-tools: Read, Bash
---

<!-- Auto-synced from ~/.claude/includes/npm-ci-verify.md — do not edit manually -->

## npm_ex CI/CD & Installation Verification

**Min version: `{:npm, "~> 0.7.4"}`.**

Reproducible builds. The tools form a pipeline — each checks a different layer.

### Verification Stack

| Symptom | Tool | Checks |
|---|---|---|
| "Install healthy?" | `mix npm.doctor` | Overall sanity |
| "node_modules matches lockfile?" | `mix npm.verify` | File presence + version match |
| "Lockfile matches package.json?" | `mix npm.check` | Lockfile freshness |
| "Frozen install for CI" | `mix npm.ci` | Clean install from lockfile only |
| "Lock versions for publishing" | `mix npm.shrinkwrap` | Freeze exact versions |

### CI Pipeline

```bash
mix npm.check      # lockfile ↔ package.json
mix npm.ci         # clean frozen install (fails on stale lockfile)
mix npm.verify     # node_modules ↔ lockfile
```

`mix npm.install --frozen` combines check + ci in one command.

### Programmatic API

```elixir
:ok = NPM.Install.CI.preflight()        # lockfile + package.json exist?
:ok = NPM.Install.CI.validate()         # full CI validation
true = NPM.Install.CI.needs_clean?()    # needs rebuild?

{:ok, lockfile} = NPM.Lockfile.read()
[] = NPM.Verify.check("node_modules", lockfile)     # (path, lockfile) — path first
true = NPM.Verify.clean?("node_modules", lockfile)

# Convenience — path-based (reads lockfile internally)
NPM.Lockfile.has_package?("ccxt")
{:ok, names} = NPM.Lockfile.package_names()
{:ok, entry} = NPM.Lockfile.get_package("ccxt")
NPM.Lockfile.has_package?("ccxt", "path/to/npm.lock")
```

### Gotchas

- `Lockfile.read/0` returns `{:ok, map}` — unwrap before passing downstream. #1 mistake.
- `Verify.check/2` is `(path, lockfile)` — path first. `@spec check(String.t(), map())`.
- `Install.CI.needs_clean?/0` returning `true` means "reinstall needed," not "broken."
- `npm.install --frozen` and `npm.ci` both fail on stale lockfiles. `npm.ci` additionally wipes `node_modules` first.
- `mix npm.run` / `mix npm.exec` propagate non-zero exit codes — don't wrap them expecting silent failure.
- `npm.lock` records the dependency security policy; `--frozen` fails on locks written under a weaker policy. Policy-less lockfiles (no policy section at all) install cleanly.
- `--frozen` checks `optionalDependencies` for drift alongside regular deps.

### npm.lock vs npm-shrinkwrap.json

- `npm.lock` — standard lockfile, checked into VCS. Used by `mix npm.install` and `mix npm.ci`.
- `npm-shrinkwrap.json` — created by `mix npm.shrinkwrap`. For published packages where consumers should get your exact tree. Rare for applications.

### Mix Compiler Integration

```elixir
# mix.exs
def project, do: [compilers: [:npm | Mix.compilers()], ...]
```

Runs `NPM.install()` during compile — useful when npm packages are needed at compile time (e.g., loading a browser bundle).
