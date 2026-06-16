---
name: hex-playground
description: hex-playground — run code analyzers across many Hex packages as a corpus. Use when corpus-testing an analyzer or Credo rule such as descripex against real packages, fetching or mirroring Hex.pm packages, or processing NDJSON run results. Not on Hex — clone. Covers mix hex_playground.fetch/mirror/mirror.verify and the run-result schema.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/hex-playground.md — do not edit manually -->

## hex-playground — Corpus Playground for Running Local Tools Against Hex.pm Packages

**Not on Hex — clone, don't pin.** Clone from `github.com/elixir-vibe/hex-playground` (version `0.1.0`, as of June 2026 master; no Hex package published). Use as a standalone dev tool, not a library dep.
**Three Mix tasks:** `hex_playground.fetch`, `hex_playground.mirror`, `hex_playground.mirror.verify`.
**One driver script:** `scripts/run_tool.exs` — runs any shell command across every package in the corpus via `manifest.json`.
**Output artifacts:** `manifest.json` (entry index), `sources/<pkg>-<vsn>/` (extracted source), `tarballs/<pkg>-<vsn>.tar` (cached), `runs/<timestamp>/results.ndjson` + `summary.json` (tool run results).

**Caveat:** This is an early tool with no published Hex package and no hexdocs page. All docs come from the README and source.

**Does NOT cover:** CI-style Mix plugin usage, Hex API authentication, private package corpora, or pushing a mirror back to Hex.pm. The mirror task produces a static-file layout only, not a full Hex.pm replacement.

**Portfolio fit:** Use hex-playground to corpus-test descripex's `api()` macro or a new Credo rule (e.g. in `claude-marketplace`) against the top 300–1000 real Hex packages before shipping. Replaces ad-hoc test sets with reproducible, versioned corpora.

### Setup (clone and run)

```sh
git clone https://github.com/elixir-vibe/hex-playground
cd hex-playground
mix deps.get
```

Two execution modes:

| Mode | Command |
|------|---------|
| Mix task (dev) | `mix hex_playground.fetch [opts]` |
| Escript (portable) | `mix escript.build && ./hex_playground fetch [opts]` |

The escript delegates to `HexPlayground.CLI`; `mix hex_playground.fetch` delegates to the same code via `Mix.Tasks.HexPlayground.Fetch`.

### Fetch a Corpus (`mix hex_playground.fetch`)

```sh
# Latest release of the top 300 packages, 8 parallel downloads
mix hex_playground.fetch --mode latest --limit 300 --concurrency 8

# Every public package version (large: ~150k releases as of 2026)
mix hex_playground.fetch --mode all --concurrency 16

# Top N by download count (uses Hex HTTP API for ranking)
mix hex_playground.fetch --mode top --limit 1000 --concurrency 16

# Latest, drop non-Elixir packages after extraction
mix hex_playground.fetch --mode latest --concurrency 16 --prune-non-elixir
```

`latest` and `all` pull the package list from `https://repo.hex.pm/versions`. `top` calls the Hex HTTP API. Tarballs are fetched from `https://repo.hex.pm/tarballs/<name>-<version>.tar` and unpacked with `hex_core`.

**Fetch flags:**

| Flag | Default | Notes |
|------|---------|-------|
| `--mode latest\|all\|top` | `latest` | Package selection strategy |
| `--limit N` | all (latest/all), 300 (top) | Cap fetched packages |
| `--concurrency N` | `8` | Parallel downloads/extractions |
| `--timeout MS` | `120000` | Per-download timeout |
| `--out DIR` | `sources` | Extracted source root |
| `--tarballs DIR` | `tarballs` | Tarball cache directory |
| `--manifest PATH` | `manifest.json` | Output manifest path |
| `--registry-url URL` | `https://repo.hex.pm` | Registry for `/versions` |
| `--mirror URL` | `https://repo.hex.pm` | Tarball source; may repeat or comma-separate |
| `--mirror-strategy round_robin\|random` | `round_robin` | Mirror selection order |
| `--force` | false | Re-download even if cached |
| `--prune-non-elixir` | false | Remove packages with no `.ex`/`.exs` files |

`manifest.json` structure:

```json
{
  "generated_at": "...",
  "mode": "latest",
  "count": 298,
  "entries": [
    {
      "name": "my_pkg",
      "version": "1.2.3",
      "status": "ok",
      "path": "sources/my_pkg-1.2.3",
      "language_counts": { ".ex": 42, ".exs": 5 },
      "mirror": "https://repo.hex.pm"
    }
  ],
  "mirrors": ["https://repo.hex.pm"],
  "mirror_strategy": "round_robin",
  "registry_url": "https://repo.hex.pm"
}
```

Entries with download or extraction errors have `"status": "error"` and an `"error"` key instead of `"path"`.

### Mirror Building (`mix hex_playground.mirror`)

Builds a static-file Hex.pm-compatible mirror. Useful for offline use or CI isolation.

```sh
mix hex_playground.mirror \
  --out mirror \
  --concurrency 32 \
  --package-concurrency 16 \
  --mirror https://repo.hex.pm \
  --mirror https://cdn.jsdelivr.net/hex

# Small test
mix hex_playground.mirror --out mirror-test --limit 20 --concurrency 4
```

**Mirror flags:** same as fetch plus `--out DIR` (required), `--package-concurrency N` (default 4), `--verify/--no-verify`.

**Output layout:**

```
mirror/names
mirror/versions
mirror/public_key
mirror/packages/<name>
mirror/tarballs/<name>-<version>.tar
mirror/.hex_playground/manifest.ndjson
mirror/.hex_playground/failures.ndjson   # only if downloads fail
mirror/.hex_playground/summary.json
```

Point Hex clients at the served mirror:

```sh
cd mirror && python3 -m http.server 8080

MIX_HOME=/tmp/hex-mirror-mix mix hex.repo set hexpm \
  --url http://localhost:8080 \
  --public-key mirror/public_key
```

If adding a non-`hexpm` repo name, set `HEX_NO_VERIFY_REPO_ORIGIN=1` (signed records still declare origin as `hexpm`).

### Verify a Mirror (`mix hex_playground.mirror.verify`)

```sh
mix hex_playground.mirror.verify --out mirror
```

Checks required registry files, package metadata, tarball presence, and unpacking. Writes `mirror/.hex_playground/verify-summary.json`. Tarballs that exceed `hex_core`'s in-memory safety limit are treated as valid (still serveable and fetchable).

### Run Tools Across the Corpus (`scripts/run_tool.exs`)

The key workflow for testing analyzers at scale. Reads `manifest.json`, iterates only `"status": "ok"` entries, runs a shell command per package, writes NDJSON results.

```sh
# Placeholders: {name} {version} {path} {abs_path}
./scripts/run_tool.exs --limit 20 -- \
  elixir -e 'IO.puts(System.get_env("HEX_PLAYGROUND_PACKAGE"))'

./scripts/run_tool.exs --limit 300 -- \
  bash -lc 'find lib src -type f 2>/dev/null | wc -l'

./scripts/run_tool.exs --limit 300 -- \
  bash -lc 'mix ex_dna --format json 2>/dev/null || true'

# Run a custom Credo rule under review
./scripts/run_tool.exs --limit 500 -- \
  bash -lc 'mix credo --strict --format json 2>/dev/null || true'
```

**run_tool.exs flags:**

| Flag | Default | Notes |
|------|---------|-------|
| `--manifest PATH` | `manifest.json` | Corpus index to read |
| `--runs DIR` | `runs` | Output root for timestamped run dirs |
| `--concurrency N` | `4` | Parallel tool invocations |
| `--timeout MS` | `120000` | Per-package timeout |
| `--limit N` | `300` | Max packages to process |

**Env vars injected per package:** `HEX_PLAYGROUND_PACKAGE`, `HEX_PLAYGROUND_VERSION`. The command runs with `cd: entry["path"]`.

**Output per run (`runs/<timestamp>/`):**

- `results.ndjson` — one JSON object per package: `{status, package, version, path, command, exit_status, duration_ms, log, output_tail, timed_out}`
- `summary.json` — `{generated_at, command, total, passed, failed, results_path}`
- `<name>-<version>.log` — full stdout+stderr per package

**Result object shape:**

```elixir
%{
  status: "ok" | "error" | "runner_error",
  package: "my_pkg",
  version: "1.2.3",
  exit_status: 0,           # nil on error/timeout
  duration_ms: 841,
  output_tail: "...",       # last 4000 bytes of stdout+stderr
  timed_out: false          # or timeout_ms value on timeout
}
```

### Helper Scripts

**`scripts/corpus_stats.exs`** — reads `manifest.json`, tallies file-extension counts across all packages, prints top-30 extensions with totals. Run after fetch to profile corpus composition:

```sh
elixir scripts/corpus_stats.exs
# → {"packages": 298, "files": 84201, "top_extensions": [...]}
```

**`scripts/fetch_top_hex.exs`** — standalone convenience wrapper for `--mode top` fetch.

### Common Issues

| Problem | Cause | Fix |
|---------|-------|-----|
| Mirror fails for some tarballs | CDN doesn't carry all versions | Add `--mirror https://repo.hex.pm` as final fallback; failures land in `failures.ndjson` |
| `hex_core` unpack error on verify | Metadata file exceeds in-memory safety limit | Verify task marks these as valid — ignore; tarball is still serveable |
| `run_tool.exs` exits with "invalid options" | Using `--` separator but wrong syntax | `--` must come after all `run_tool.exs` flags, immediately before the command |
| Packages missing from `manifest.json` | `--prune-non-elixir` removed them, or download failed | Check entries with `"status": "error"` in the manifest |
| Escript not found after build | Built in wrong dir | `mix escript.build` outputs `./hex_playground` in project root |
| Mirror repo rejected by Hex client | Added as non-`hexpm` name | Set `HEX_NO_VERIFY_REPO_ORIGIN=1` or override the `hexpm` repo name directly |

### DO NOT

1. Add `hex_playground` as a Mix dep in another project — it has no Hex package; clone and run in place.
2. Commit the `sources/`, `tarballs/`, or `runs/` directories — corpus data is intentionally data-heavy; `.gitignore` excludes them by convention.
3. Use `--mirror-strategy random` when order-reproducibility matters for debugging — use `round_robin` for deterministic per-index assignment.
4. Run `--mode all` without `--limit` in CI — `~150k` releases can saturate disk quickly.
5. Override `--registry-url` for tarball downloads — registry URL controls `/versions` only; tarball URLs come from `--mirror`.

### Testing Notes

No unit test suite is shipped (the `test/` directory exists but is empty as of current master). Test coverage is effectively integration-level: run `mix hex_playground.fetch --limit 10` and verify `manifest.json` is written with 10 `"status": "ok"` entries.

For CI use, pin the git SHA in a `Makefile` or wrapper script rather than tracking `master` — the repo is early-stage with no semver stability guarantee.

### Dependencies

```elixir
# hex-playground is a standalone dev tool — clone and use in place
# Not a Mix dep. Source: github.com/elixir-vibe/hex-playground

# hex-playground's own deps (from its mix.exs):
{:hex_core, "~> 0.15"}   # registry protocol, tarball download + unpack
{:jason, "~> 1.4"}        # manifest and results JSON serialization
{:req, "~> 0.5"}          # HTTP client for downloads
```
