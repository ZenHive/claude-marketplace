# dep-audit

Ecosystem-detecting dependency-advisory nag. One shared SessionStart hook,
shipped from this marketplace plugin, enabled per-repo via `enabledPlugins` —
not copied per-repo.

## What it does

`scripts/dep-audit-check.sh` detects which package manifests are present in
the current repo and runs the matching advisory check:

| Manifest present | Check run | Requires |
|---|---|---|
| `mix.lock` | `mix hex.audit` (retired Hex packages) | nothing extra — ships with Hex |
| `mix.lock` | `mix mix_audit` (Hex CVEs) | `:mix_audit` added as a dep |
| `native/*/Cargo.toml` | `cargo audit` (RustSec advisories) | `cargo-audit` installed |
| `package.json` | `npm audit` | `npm` on PATH |
| `npm.lock` (npm_ex's own lockfile — not `package.json`) | `mix npm.audit` | the `{:npm, ...}` dep (already present wherever npm_ex is used) |

Multiple manifests can coexist in one repo (e.g. `onchain_evm` has both
`mix.lock` and `native/*/Cargo.toml`) — every matching check runs, findings
accumulate into one message.

**Silent by default.** No advisories, missing tooling, or a still-fresh
watermark all suppress output (`{"suppressOutput": true}`) — the hook never
errors and never stalls a session. On a genuine finding it emits one
`additionalContext` line naming which check(s) fired and pointing at the
repo's disclosure policy for triage (see `critical-rules.md` §
"NEVER BROADCAST AN UNPATCHED VULNERABILITY" — sanitized rmap task only, no
exploit mechanism/trigger detail in a committed file; open + undisclosed goes
to a private GitHub Security Advisory).

## Watermark gating

State lives in `.dep-audit-watch.json` at the repo root (`{"checked_at":
"YYYY-MM-DD"}`, mirrors mpp's `.sdk-watch.json` pattern). The hook only
re-runs the checks after `THRESHOLD_DAYS` (7) have passed since the last run
— every session in between is a silent no-op, regardless of whether the last
run found something. Delete the state file to force a re-check on next
session start.

## Install path per repo

1. Enable the plugin in the repo's `.claude/settings.json`:
   ```json
   { "enabledPlugins": { "dep-audit@zenhive": true } }
   ```
   The hook no-ops cleanly with zero configuration — it's safe to enable
   before any of the tooling below is installed.
2. **Hex (all seven onchain-stack repos):** `mix hex.audit` needs nothing —
   it runs immediately. To also get Hex CVE scanning, add `mix_audit` as a
   dev/test dep:
   ```elixir
   {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
   ```
   then `mix deps.get`. Until then, the hook silently skips the `mix_audit`
   check and only runs `hex.audit`.
3. **Rust (`onchain_evm` only):** install the `cargo-audit` binary once:
   ```bash
   cargo install cargo-audit
   ```
   Until installed, the hook silently skips the Rust check.
4. **npm_ex (`onchain_js`):** `mix npm.audit` runs automatically once
   `npm.lock` exists at the repo root (npm_ex's own lockfile format — this
   repo does not use a literal `package.json`/`npm audit` CLI flow). No
   extra dep needed beyond the existing `{:npm, ...}` dependency.

## Out of scope

This plugin ships the detector + nag only. It does not triage or fix any
specific advisory, and it does not reimplement mpp's `refs-pull` /
`sdk-delta-watch` machinery (that pattern diffs vendored upstream reference
SDKs; this one just wraps pinned-dependency advisory tools per ecosystem).
