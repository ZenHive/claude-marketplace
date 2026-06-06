---
name: elixir-volt
description: Elixir-Volt ecosystem — JavaScript on the BEAM without Node.js, via Rust and Zig NIFs. Use when choosing between OXC (parse/transform/bundle/minify JS/TS), QuickBEAM (run JS on the BEAM with browser APIs / DOM / fetch / crypto / WebSocket / WASM), npm_ex (install npm packages), or the Phoenix frontend stack (volt build tool, oxide_ex Tailwind, vize_ex Vue SFC, phoenix_vapor). Provides the ecosystem map and "when to use what" decision table — start here before picking a specific tool.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/elixir-volt.md — do not edit manually -->

## Elixir-Volt: JavaScript on the BEAM Without Node.js

The [elixir-volt](https://github.com/elixir-volt) ecosystem — Node.js replacement via Rust and Zig NIFs.

### Ecosystem

| Package | Hex | Purpose | Detail |
|---|---|---|---|
| `oxc` | `~> 0.15` | Parse, transform, bundle, minify, format, lint JS/TS (Rust NIFs) | `oxc.md` |
| `quickbeam` | `~> 0.10.15` | Run JS on the BEAM — browser APIs, DOM, fetch, crypto, WebSocket, WASM (Zig NIF) | `quickbeam.md` |
| `npm` | `~> 0.7.4` | Install npm packages, resolve deps, verify integrity, supply-chain hardening (OSV checks, exotic-dep allowlist, registry policy, package-age warnings) | Pure Elixir — `npm-*.md` |
| `npm_semver` | `~> 0.1` | npm-compatible semver | Pure Elixir |

**Phoenix frontend packages:** `volt` (build tool / dev server / HMR — replaces Vite), `oxide_ex` (Tailwind Oxide via Rust NIF), `vize_ex` (Vue SFC compiler), `phoenix_vapor` (Vue templates → LiveView rendered structs).

### npm_ex Quick Reference

```bash
mix npm.install lodash                # install
mix npm.install ccxt@^4.5             # version range
mix npm.install eslint --save-dev
mix npm.remove lodash
mix npm.list
mix npm.outdated
mix npm.tree
```

Packages install to `node_modules/`. Browser bundles (`dist/*.browser.min.js`) load into QuickBEAM.

**Specialized npm skills:**
- `elixir:npm-ci-verify` — CI, lockfile verification, reproducible builds
- `elixir:npm-security-audit` — CVE, license, supply chain
- `elixir:npm-dep-analysis` — size, graph, package quality

### When to Use What

| Need | Tool |
|---|---|
| Parse JS/TS source | OXC |
| Run a JS library (npm) | QuickBEAM + npm_ex |
| Bundle multiple JS/TS | `OXC.bundle` |
| Strip TypeScript types | `OXC.transform` |
| Extract imports | `OXC.imports` / `OXC.collect_imports` |
| Minify for production | `OXC.minify` |
| Web3 signing (ethers.js, noble-curves, starknet.js) | QuickBEAM |
| WebSocket from JS | QuickBEAM (Mint-backed) |
| WebAssembly from JS | QuickBEAM (WAMR-backed) |
| Frontend build + HMR | Volt |
| Tailwind CSS | oxide_ex |
| Vue SFC | vize_ex |

**Good for:** extraction, prototyping, web3 signing, slow-path operations, running npm libraries, DOM manipulation. **Not for:** hot-path HFT (use native Elixir / Rust NIFs for sub-ms).

For API details, usage, recipes, and pitfalls, see `oxc.md` and `quickbeam.md`.
