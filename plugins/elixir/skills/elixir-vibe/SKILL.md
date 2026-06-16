---
name: elixir-vibe
description: elixir-vibe — roster and adopt/skip verdicts for the whole elixir-vibe org. Use when deciding whether to reach for any elixir-vibe library (systemdkit, ex_slop, ex_ast, ex_dna, exograph, host_kit, gatehouse, quackdb, phoenix_replay, vibe, pi-elixir, and more) or to find which per-lib include to load. The cheap always-on map: every lib with version, maturity, and an adopt/spike/watch/skip verdict.
allowed-tools: Read
---

<!-- Auto-synced from ~/.claude/includes/elixir-vibe.md — do not edit manually -->

## elixir-vibe — org roster + adopt/skip verdicts

The cheap always-on map of the `elixir-vibe` org: one row per lib with maturity + a verdict, so future sessions don't re-research the whole org. Reach for a per-lib include only after this table says the lib is worth it.

**Author: `dannote` (single maintainer). All shipped mid-2026 — ALL past the model's training cutoff, so every lib here is "unknown unless documented."** The linked includes ARE that documentation.
**Most are 0.x, single-maintainer, fast-moving.** Treat versions below as "as of 2026-06"; re-confirm before pinning.
**Companion docs:** `building-blocks.md` = the org's design thesis (the *why*); each per-lib include = the API (the *how*).

Caveat: verdicts are portfolio-relative (crypto/trading + bare-metal Ethereum infra + Phoenix LiveView + AI-agent dev tooling). A `skip` here means "skip *for this portfolio*," not "bad lib."
Does NOT cover: any API. Follow the include link.

### Verdict legend

| Verdict | Meaning |
|---|---|
| **adopt** | In use or clearly worth wiring in now |
| **spike** | Worth a time-boxed trial against a real repo before committing |
| **watch** | Promising but too early / no current need — revisit |
| **skip** | Redundant with what you already have, or no portfolio fit yet |

### Roster

| Lib | Include | Version (2026-06) | Maturity | Verdict | One-line reason |
|---|---|---|---|---|---|
| **systemdkit** | `systemdkit.md` | 0.1.3 (Hex) | usable | **adopt** | Replaces hand-rolled `systemctl` shell-out + unit-file strings in servernodes_agent / ethnode — highest infra fit |
| **ex_slop** | `ex-slop.md` | 0.4.2 (Hex) | usable | **adopt** | Credo plugin for AI-slop antipatterns; slots beside the existing `ex_dna` PostToolUse hook |
| **ex_ast** | `ex-ast.md` | 0.12.0 (Hex) | mature (104k dl) | **adopt** | Already dev-dep'd in harness; structural search/replace/diff is the code-intel workhorse |
| **ex_dna** | `ex-dna.md` | 1.5.3 (Hex) | mature | **adopt** (in use) | Already run via PostToolUse hook; clone detector. Suppress via `# ex_dna:disable-*`, NOT `@no_clone` |
| **reach** | `reach.md` | 2.7.5 (Hex) | mature | **adopt** (in use) | PDG/SDG slicing/taint; already wired. See its own include |
| **host_kit** | `host-kit.md` | 0.1.0-beta.4 | beta (API churn) | **spike** | Generalizes your `recipes/base/` host-config library; trial before committing |
| **exograph** | `exograph.md` | 0.8.0 (Hex) | early | **spike** | CodeQL-style structural search for a harness reviewer step; heavy stack (DuckDB backend) |
| **pi-elixir** | `pi-elixir.md` | 0.6.21 (npm+bridge) | early | **spike** | Agent↔BEAM AST-edit bridge via Tidewave; candidate harness Pi adapter |
| **gatehouse** | `gatehouse.md` | placeholder / clone | early | **watch** | OTP edge proxy + blue-green + ACME; target for servernodes_rpc edge. Hex is a name placeholder — clone, don't pin |
| **safe_rpc** | `safe-rpc.md` | 0.1.3 | prototype | **watch** | Capability-scoped RPC over safe ETF; Unix transport only so far |
| **program_facts** | `program-facts.md` | 0.2.1 (Hex) | early | **watch** | Oracle-fact program generation for testing analyzers (descripex) |
| **vibe** | `vibe.md` | 0.2.4 (escript) | early | **watch** | BEAM-native coding-agent substrate; overlaps your own harness — evaluate as complement |
| **hex-playground** | `hex-playground.md` | 0.1.0 (clone) | early | **watch** | Run analyzers across a Hex corpus; useful for descripex/Credo-rule corpus testing |
| **quackdb** | `quackdb.md` | 0.5.13 (Hex) | usable | **watch** (parked) | DuckDB DBConnection + Ecto adapter; parked until a candle/OLAP backtesting pipeline exists |
| **phoenix_replay** | `phoenix-replay.md` | 0.2.0 (Hex) | early | **watch** | Server-side LiveView replay — but it strips `:streams`/`:uploads`, which your LVs lean on heavily |
| **vibe-actions** | `vibe-actions.md` | `@v1` (Actions) | usable | **watch** | Shared GitHub Actions / reusable CI for Elixir+Rustler; ref-only |
| **unitctl** | `unitctl.md` | 0.1.0-pre | API preview | **skip** | Docker-like process control; systemdkit already covers the real need |
| **vibe_kit** | `vibe-kit.md` | 0.1.5 (Hex) | early | **skip** | Igniter installer for the vibe toolchain; overlaps your `elixir-setup` stack |
| **cringe** | `cringe.md` | 0.5.0 (alpha) | alpha | **skip** | OTP-native TUI; redundant with your own `drafter` framework |
| **fsst** | `fsst.md` | 0.1.2 (Hex) | early | **skip** | FSST string compression; no current portfolio use |
| **ttycast** | `ttycast.md` | 0.1.0 (Hex) | early | **skip** | Seekable terminal recordings; niche |
| **theoria** | `theoria.md` | 0.8.0 | early | **skip** | Elixir-native proof/spec kernel; no current use |
| **building-blocks** | `building-blocks.md` | manifesto | spec | **read** | The org's design thesis, not a package — orientation only |

### Adopt order (if wiring these in)

1. **systemdkit** → pilot in `servernodes_agent` (replace `CommandExecutor`/`Services` shell-outs) and `ethnode` units.
2. **ex_slop** → add to `.credo.exs` plugins beside the existing `ex_dna` hook.
3. **ex_ast** / **ex_dna** / **reach** → already present; just make sure the includes are loaded when working code-intel.
4. Then time-box spikes: **host_kit** (vs `recipes/base/`), **exograph** (harness reviewer), **pi-elixir** (harness Pi adapter).

### DO NOT

1. **Don't pin `gatehouse` or `hex-playground` from Hex** — the Hex entries are placeholders/absent; clone the repo (see their includes).
2. **Don't assume a 0.x version is stable across a minor bump** — single maintainer, fast iteration. Re-check the version before adopting.
3. **Don't reach for `cringe`, `unitctl`, or `vibe_kit`** — each is already covered by something you own (`drafter`, `systemdkit`, `elixir-setup`).
4. **Don't treat a `skip` as permanent** — re-evaluate when the portfolio gains the matching need (e.g. `quackdb`/`fsst` if a candle pipeline lands).

### Dependencies

None — read-only index. Each row links to a per-lib include under `~/.claude/includes/`.
