---
name: building-blocks
description: building-blocks — the elixir-vibe AI-verifiable BEAM stack thesis. Use when reasoning about why the elixir-vibe libraries exist and how they compose: the AI-generated vs AI-verifiable distinction, the eleven boundary layers (design, time, causality, build, runtime, one-program, quality, knowledge, agent, deploy, surface), and how a portfolio maps onto them. Conceptual orientation, not an API.
allowed-tools: Read
---

<!-- Auto-synced from ~/.claude/includes/building-blocks.md — do not edit manually -->

## building-blocks — the AI-verifiable BEAM stack thesis

The `elixir-vibe` org's design manifesto: a map of *why* its ~23 libs exist and how they compose. Read this to understand the org's intent before reaching for any single lib.

**Source: `github.com/elixir-vibe/building-blocks` — a spec/manifesto repo, NOT a Hex package.** Nothing to depend on; this include is the thesis, the per-lib includes are the API.
**Author: `dannote` (the whole org). Status: Early — individual `layers/*.md` are marked `settled` or `draft` per-section.**
**Core claim:** *"Don't wait for smarter models — build the environment that pushes back."* The fix for AI-written software isn't a better model; it's removing the boundaries where AI-generated parts silently contradict each other, so code can be **verified, not just generated.**

Caveat: this is a moving target — layer docs change and libs are renamed/merged. Treat the lib list below as "as of mid-2026"; confirm a lib still exists before citing it.
Does NOT cover: any actual API. For that, see the per-lib includes (linked in the table).

### The central distinction (the one idea to remember)

| | AI-**generated** surface | AI-**verifiable** structure |
|---|---|---|
| What it is | Designs / frontends / APIs that *look* plausible | Systems that catch disagreement with a precise failure location |
| Failure mode | Silent contradiction across a boundary (design↔code, client↔server, build↔runtime) | Loud, located, replayable |
| The org's bet | not enough on its own | the actual deliverable |

The boundaries are the enemy: every seam (design vs code, client vs server, build vs runtime) is a place two AI-generated halves can disagree without anyone noticing. The eleven layers each *erase one boundary*.

### The eleven layers (boundary → building block → the lib that implements it)

| Boundary | Building block | Reference lib / project | Per-lib include |
|---|---|---|---|
| Design | Node-tree model, not pictures | OpenPencil (Figma-compatible editor) | — (external) |
| Time | Session replay | `phoenix_replay` | `phoenix-replay.md` |
| Causality | Dependency proof | `reach` (whole-program dependence) | `reach.md` |
| Build | Toolchain inside the app | Volt (no-Node frontend) | — |
| Runtime | JS in an observable VM | QuickBEAM (JS runtime on BEAM) | — |
| One Program | No client/server split | phoenix_vapor (Vue→LiveView) | — |
| Quality | Machine-checked generation | `ex_slop` (AI-aware linters), `ex_dna` | `ex-slop.md`, `ex-dna.md` |
| Knowledge | Search ecosystem by *shape* | `exograph` (structural search) | `exograph.md` |
| Agent | Supervised worker systems | `pi-elixir` / `vibe` (agents inside the running app) | `pi-elixir.md`, `vibe.md` |
| Deploy | Supervised Linux deployment | `systemdkit` / `host_kit` / `gatehouse` | `systemdkit.md`, `host-kit.md`, `gatehouse.md` |
| Surface | Unified queryable operational state | (emerging) | — |

"Settled vs draft" lives per-file in the upstream `layers/*.md` — don't assume any layer is final. The **Quality**, **Causality**, and **Deploy** layers are the most lib-backed (and the ones this portfolio already touches); **Surface** and **One Program** are the most speculative.

### Portfolio fit (where you already implement this thesis)

You're building the org's thesis from the other direction — bare-metal up. **Deploy layer:** `servernodes`/`ethnode` hand-roll exactly what `systemdkit`+`host_kit`+`gatehouse` formalize (the single highest-fit cluster). **Quality + Causality layers:** `harness`/`descripex` already dev-dep `reach`/`ex_ast`/`ex_dna` and run `ex_dna` via a PostToolUse hook — `ex_slop` and `exograph` are the natural next adoptions. **Agent layer:** `harness`/`rmap` are your supervised-worker substrate, the same niche as `pi-elixir`/`vibe`.

### DO NOT

1. **Don't treat this as a dependency.** It's prose; there's no `{:building_blocks, ...}`.
2. **Don't cite a layer→lib mapping as stable.** Libs get renamed/merged (the org is one maintainer, all 0.x). Re-fetch the repo before relying on a specific name.
3. **Don't conflate the manifesto's ambition with a lib's maturity.** A layer being "settled" in the thesis says nothing about whether its lib is production-ready — check the per-lib include's version pin.

### Dependencies

None — read-only conceptual reference. Companion map: `elixir-vibe.md` (the per-lib roster + adopt/skip verdicts).
