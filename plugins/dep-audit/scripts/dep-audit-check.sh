#!/usr/bin/env bash
# SessionStart hook: ecosystem-detecting dependency-advisory nag.
#
# Detects which package manifests are present in the current repo and runs
# the matching advisory check:
#   mix.lock              -> `mix hex.audit` (retired packages, always available)
#                             + `mix mix_audit` (Hex CVEs, only if the dep is installed)
#   native/*/Cargo.toml    -> `cargo audit` (RustSec, only if cargo-audit is installed)
#   package.json           -> `npm audit` (only if npm is on PATH)
#   npm.lock (npm_ex)      -> `mix npm.audit` (only if the npm_ex mix task is available)
#
# Watermark-gated (mirrors mpp's .sdk-watch.json checked_at pattern): only
# re-runs every THRESHOLD_DAYS, not every session. Fails open everywhere —
# any missing tool, any command error, any unexpected state -> silent.
# Never blocks a session.

set -uo pipefail

STATE=".dep-audit-watch.json"
THRESHOLD_DAYS=7

silent() {
  jq -n '{"suppressOutput": true}' 2>/dev/null || printf '{"suppressOutput": true}\n'
  exit 0
}

command -v jq >/dev/null 2>&1 || silent

if [[ -f "$STATE" ]]; then
  last=$(grep -o '"checked_at"[[:space:]]*:[[:space:]]*"[0-9-]\{10\}"' "$STATE" 2>/dev/null \
          | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}' | head -1)
  if [[ -n "${last:-}" ]]; then
    last_s=$(date -j -f "%Y-%m-%d" "$last" +%s 2>/dev/null || echo 0)
    now_s=$(date +%s)
    days=$(( (now_s - last_s) / 86400 ))
    if [[ "$last_s" != "0" && "$days" -lt "$THRESHOLD_DAYS" ]]; then
      silent
    fi
  fi
fi

findings=()

# --- Hex (uniform across all onchain-stack repos) ---
if [[ -f mix.lock ]]; then
  if mix help mix_audit >/dev/null 2>&1; then
    out=$(mix mix_audit 2>/dev/null)
    if [[ -n "$out" ]] && ! grep -qi "no vulnerabilities found" <<<"$out"; then
      findings+=("mix_audit: possible Hex CVE(s) — run \`mix mix_audit\` for detail")
    fi
  fi
  hex_out=$(mix hex.audit 2>/dev/null)
  if [[ -n "$hex_out" ]] && ! grep -qi "no retired packages found" <<<"$hex_out"; then
    findings+=("hex.audit: retired Hex package(s) — run \`mix hex.audit\` for detail")
  fi
fi

# --- Rust (onchain_evm's native/ NIF crates) ---
shopt -s nullglob
cargo_manifests=(native/*/Cargo.toml)
shopt -u nullglob
if [[ ${#cargo_manifests[@]} -gt 0 ]] && command -v cargo-audit >/dev/null 2>&1; then
  if ! cargo audit 2>/dev/null | grep -qi "no vulnerabilities found"; then
    findings+=("cargo-audit: possible RustSec advisory in native/ crates — run \`cargo audit\` for detail")
  fi
fi

# --- npm (plain Node package.json, if any repo ever adds one) ---
if [[ -f package.json ]] && command -v npm >/dev/null 2>&1; then
  npm_out=$(npm audit --json 2>/dev/null)
  vuln_total=$(jq -r '.metadata.vulnerabilities // {} | to_entries | map(.value) | add // 0' <<<"$npm_out" 2>/dev/null)
  if [[ "${vuln_total:-0}" != "0" ]]; then
    findings+=("npm audit: possible advisories in package.json deps — run \`npm audit\` for detail")
  fi
fi

# --- npm_ex (onchain_js's JS-on-BEAM deps, tracked via npm.lock not package.json) ---
if [[ -f npm.lock ]] && mix help npm.audit >/dev/null 2>&1; then
  out=$(mix npm.audit 2>/dev/null)
  if [[ -n "$out" ]] && ! grep -qiE "no (vulnerabilities|findings) found" <<<"$out"; then
    findings+=("mix npm.audit (npm_ex): possible advisories in npm.lock deps — run \`mix npm.audit\` for detail")
  fi
fi

today=$(date +%Y-%m-%d)
printf '{"checked_at": "%s"}\n' "$today" > "$STATE" 2>/dev/null

if [[ ${#findings[@]} -eq 0 ]]; then
  silent
fi

joined=$(printf '%s; ' "${findings[@]}")
joined="${joined%; }"
msg="Dependency-advisory watch: ${joined}. Triage under the repo's disclosure policy — file a SANITIZED rmap task (no exploit mechanism/trigger detail); an open, undisclosed vuln goes to a private GitHub Security Advisory, never a committed file (see critical-rules.md § \"NEVER BROADCAST AN UNPATCHED VULNERABILITY\")."

jq -n --arg msg "$msg" '{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": $msg
  }
}' 2>/dev/null || silent
