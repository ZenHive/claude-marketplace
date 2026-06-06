---
name: npm-security-audit
description: npm_ex security auditing and supply chain assessment. Use when evaluating dependency security, checking for CVEs, scanning licenses for compliance (GPL contamination, AGPL, unlicensed), finding deprecated packages, or assessing supply chain risk. Covers mix npm.audit, npm.licenses, npm.deprecations, and the programmatic NPM.Audit/NPM.License/NPM.Deprecation/NPM.SupplyChain APIs with correct argument orders and input types.
allowed-tools: Read, Bash
---

<!-- Auto-synced from ~/.claude/includes/npm-security-audit.md — do not edit manually -->

## npm_ex Security Auditing & Supply Chain Assessment

CVE scanning, license compliance, deprecation detection, supply chain risk scoring, OSV-backed compromised-package checks.

**Min version: `{:npm, "~> 0.7.4"}`.**

**Default-deny on exotic dep specs.** Direct `git`, GitHub-shorthand, URL, and `file:` specs are blocked. Allowlist with `config :npm, exotic_deps: ["github:owner/repo#sha"]`. Transitive exotic deps from published package metadata are always blocked. See § "Exotic Deps & Registry Policy".

### Quick Check

```bash
mix npm.audit              # CVEs
mix npm.audit --osv        # also query OSV for malicious-package advisories
mix npm.audit --compromised # offline check against the bundled compromised cache
mix npm.licenses           # license compliance
mix npm.deprecations       # stale/deprecated packages
```

### CVE Audit (`NPM.Security.Audit`)

```elixir
{:ok, lockfile} = NPM.Lockfile.read()

findings = NPM.Security.Audit.check(lockfile, advisories)       # advisories = list of maps
NPM.Security.Audit.filter_by_severity(findings, :critical)
NPM.Security.Audit.fixable?(finding)
NPM.Security.Audit.summary(findings)                            # %{total:, critical:, high:, moderate:, low:, fixable:}
NPM.Security.Audit.compare_severity(:critical, :high)           # :gt
```

Severity levels (high → low): `:critical`, `:high`, `:moderate`, `:low`, `:info`.

### Compromised Packages (`NPM.Security.Compromised`)

Malicious-package detection backed by a bundled cache (auto-merged with OSV advisory writes). Use offline-first; `mix npm.audit --osv` fails the audit on OSV query errors so transient network issues don't silently hide findings.

```elixir
{:ok, lockfile} = NPM.Lockfile.read()
NPM.Security.Compromised.check(lockfile)               # against bundled cache
NPM.Security.Compromised.OSV.query("eslint", "9.0.0")  # online OSV lookup
```

### License Compliance (`NPM.Package.License`)

```elixir
licenses = NPM.Package.License.scan("node_modules")    # PATH string, not lockfile
# => [%{package:, version:, license:}, ...]

NPM.Package.License.summary(licenses)                  # %{total:, permissive:, non_permissive:, unknown:, unique_licenses:}
NPM.Package.License.non_permissive(licenses)           # GPL, AGPL, SSPL, BSD, compound
NPM.Package.License.permissive?("MIT")                 # true
NPM.Package.License.group_by_license(licenses)
NPM.Package.License.extract(%{"license" => "MIT"})
```

### Deprecation (`NPM.Deprecation`)

`NPM.DeprecationAnalysis` exposes batch analysis over the same data.

```elixir
NPM.Deprecation.scan("node_modules")                   # PATH string
NPM.Deprecation.deprecated?(entry)
NPM.Deprecation.extract(pkg_json_map)
```

### Supply Chain Risk (`NPM.Security.SupplyChain`)

Non-obvious argument order — **pkg_json first, lockfile second**:

```elixir
{:ok, lockfile} = NPM.Lockfile.read()
{:ok, pkg_json} = NPM.Package.JSON.read()

assessment = NPM.Security.SupplyChain.assess(pkg_json, lockfile)
# %{total_packages:, phantom_deps:, integrity_coverage:, risk_level: :low | :medium | :high}

NPM.Security.SupplyChain.risk_score(assessment)        # 0-100, lower is better
NPM.Security.SupplyChain.format(assessment)
```

**Risk thresholds:** `:low` = integrity ≥ 90% + zero phantom · `:medium` = integrity ≥ 50% + phantom < 5 · `:high` = everything else.

**Phantom deps** count packages in lockfile but not in `package.json` deps — transitive deps are normal, so high phantom count alone isn't alarming. Becomes meaningful combined with low integrity coverage.

### Exotic Deps & Registry Policy

Direct `git`, GitHub-shorthand, URL, and `file:` specs are blocked by default. Allow specific ones via `config :npm, exotic_deps: ["github:owner/repo#sha"]`. Transitive exotic deps from published package metadata are always blocked (no allowlist).

Policy knobs (all via `config :npm`):

```elixir
config :npm,
  registry: "https://registry.npmjs.org",
  registry_token: System.get_env("NPM_TOKEN"),
  registry_mirror: "https://npm-mirror.internal",
  cache_dir: "~/.cache/npm",
  install_dir: "node_modules",
  registry_policy: :allowlist,                # enforce registry origin allowlist
  package_age_warnings: true,                 # warn on freshly-published versions
  exotic_deps: []                              # exact-spec allowlist
```

The dependency security policy is recorded in `npm.lock`. Lockfiles written under a weaker policy are treated as stale by `mix npm.ci` / `--frozen`.

### Gotchas

- `Package.License.scan/1`, `Deprecation.scan/1`: path strings, not lockfile maps. Passing a map causes `IO.chardata_to_string` errors.
- `Security.SupplyChain.assess/2`: `(pkg_json, lockfile)`. Passing a single entry makes everything count as phantom.
- `Security.Audit.check/2`: `(lockfile, advisories)`. Each advisory **must** include `:patched_versions` or `summary/1` raises `KeyError`.
- `Security.Audit.format_finding/1`: atom severity (`:high`), not strings.
- `Package.License.permissive?/1`: license string (`"MIT"`), not entry map. Use `permissive?(entry.license)`.
- `Diagnostics.Health.grade/1` vs `Diagnostics.Health.format_report/1`: may disagree — trust `grade/1`.
- BSD is flagged non-permissive (conservative) — review manually.
- `Lockfile.get_package/1`: reads file. If already in memory, use `Map.get(lockfile, "name")`.
- `mix npm.audit --osv` fails on query errors by design — wrap CI calls with retry, don't suppress.

### Decision Framework

| Risk Score | Action |
|---|---|
| 0-19 (low) | Safe to proceed |
| 20-49 (medium) | Review phantom deps + integrity gaps |
| 50+ (high) | Investigate before production |

### Module Namespace Map

Top-level namespaces and what lives in each:

| Namespace | Modules |
|---|---|
| `NPM.Security.*` | `Audit`, `CVE`, `ExoticDeps`, `Provenance`, `SupplyChain`, `Compromised`, `Compromised.OSV`, `RegistryPolicy`, `Age`, `TaskReporter` |
| `NPM.Package.*` | `JSON`, `Manifest`, `Files`, `Quality`, `Spec`, `License`, `Funding`, `Fund`, `People`, `Keywords`, `Repository`, `PublishConfig` |
| `NPM.Dependency.*` | `Graph`, `Tree`, `Sort`, `Range`, `Conflict`, `Freshness`, `Stats`, `UsageCheck`, `Dedupe`, `Outdated`, `Phantom`, `Peer`, `Peer.Check` |
| `NPM.Lockfile.*` | `Check`, `Stats`, `Merge`, `PackageLock`, `Shrinkwrap` (plus `NPM.Lockfile` root: `read/0`, `get_package/1`, `has_package?/1,2`, `package_names/0`) |
| `NPM.Diagnostics.*` | `Health`, `Doctor`, `EngineCheck`, `EnvCheck` |
| `NPM.Install.*` | `CI` |
| `NPM.NodeModules.*` | `Path` |
| Root | `NPM.Why`, `NPM.Deprecation`, `NPM.DeprecationAnalysis`, `NPM.Size`, `NPM.JSON` |
