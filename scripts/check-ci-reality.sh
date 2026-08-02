#!/usr/bin/env bash
# check-ci-reality.sh — does the CI you think you have actually run?
#
# Three defect classes that all look fine in the YAML and all fail silently:
#
#   1. DEAD BRANCH FILTER  a `branches:` filter naming a branch that does not
#      exist. GitHub matches nothing, the workflow never fires on push/PR, and
#      nothing warns. Renaming a default branch leaves these behind.
#   2. NEVER RAN           a repo with workflow files and zero runs, ever.
#   3. TESTS THAT NEVER RUN  `:integration`-tagged tests that no workflow
#      executes. They are excluded by default in test_helper.exs and only ever
#      run when a human types `--include integration` locally — i.e. never.
#
# Class 3 is the expensive one. Integration tests against a live service are the
# only evidence a mock cannot fake; written-but-never-executed they are worse
# than absent, because they read as coverage.
#
# Observed 2026-08: 29 repos had :integration tests, 2 had CI that ran them.
#
# Usage:  check-ci-reality.sh [root-dir]      (default: ~/_DATA/code)
#         Needs: git, rg, jq, gh (authenticated). Read-only — changes nothing.

set -uo pipefail

ROOT="${1:-$HOME/_DATA/code}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v rg >/dev/null || { echo "need ripgrep (rg)" >&2; exit 1; }
command -v jq >/dev/null || { echo "need jq" >&2; exit 1; }

have_gh=1
gh auth status >/dev/null 2>&1 || have_gh=0

echo "== CI reality check: $ROOT"
echo

# ---------------------------------------------------------------- class 1
echo "--- Dead branch filters (workflow never fires on push/PR)"
python3 - "$ROOT" <<'PY'
import re, subprocess, sys
from pathlib import Path

root = Path(sys.argv[1])

def git(repo, *a):
    r = subprocess.run(["git", "-C", str(repo), *a], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""

def filters(path):
    """Yield (line_no, [branches]) per branches:/branches-ignore: filter."""
    text = path.read_text(errors="replace").splitlines()
    for i, line in enumerate(text, 1):
        m = re.match(r"\s*(branches|branches-ignore)\s*:\s*\[(.*)\]", line)
        if m:
            got = [b.strip().strip("\"'") for b in m.group(2).split(",")]
            yield i, [b for b in got if b]
            continue
        if re.match(r"\s*(branches|branches-ignore)\s*:\s*$", line):
            indent = len(line) - len(line.lstrip())
            got = []
            for j in range(i, len(text)):
                nxt = text[j]
                if not nxt.strip():
                    continue
                if len(nxt) - len(nxt.lstrip()) <= indent or not nxt.lstrip().startswith("-"):
                    break
                b = nxt.lstrip()[1:].strip().strip("\"'")
                if b:
                    got.append(b)
            if got:
                yield i, got

dead = stale = 0
for repo in sorted(p for p in root.iterdir() if (p / ".git").exists()):
    wf = repo / ".github/workflows"
    if not wf.is_dir():
        continue
    known = {
        b.removeprefix("origin/")
        for b in git(repo, "for-each-ref", "--format=%(refname:short)",
                     "refs/heads", "refs/remotes/origin").split()
        if b and not b.endswith("/HEAD")
    }
    if not known:
        continue
    for f in sorted([*wf.glob("*.yml"), *wf.glob("*.yaml")]):
        for ln, names in filters(f):
            literal = [b for b in names if not any(c in b for c in "*?![]")]
            missing = [b for b in literal if b not in known]
            if not missing:
                continue
            # Still fires if any listed branch is live, or a glob is present.
            if len(literal) - len(missing) > 0 or len(names) > len(literal):
                stale += 1
            else:
                dead += 1
                print(f"  DEAD   {repo.name}/{f.name}:{ln}  {names}  -> matches nothing")

print(f"  ({dead} dead, {stale} stale-but-harmless entries)")
PY
echo

# ---------------------------------------------------------------- classes 2+3
echo "--- Workflows that never ran, and integration tests no CI executes"
printf '  %-22s %-8s %-10s %-8s %s\n' REPO WF RUNS/GREEN ITESTS "CI runs them"

for d in "$ROOT"/*/; do
  repo="${d%/}"
  name="$(basename "$repo")"
  [ -d "$repo/.git" ] || continue
  # A repo with tests but NO workflows at all is the strongest form of this
  # defect, so it must not be filtered out here.
  [ -d "$repo/.github/workflows" ] || [ -d "$repo/test" ] || continue

  nwf=0
  [ -d "$repo/.github/workflows" ] && nwf=$(find "$repo/.github/workflows" -maxdepth 1 \( -name '*.yml' -o -name '*.yaml' \) | wc -l | tr -d ' ')

  # :integration-tagged test files, and whether any workflow actually runs them
  itest=0
  [ -d "$repo/test" ] && itest=$(rg -lI --no-messages ':integration' "$repo/test" 2>/dev/null | wc -l | tr -d ' ')
  ici=$(rg -lI --no-messages -- '--include[ =]integration' "$repo/.github/workflows" 2>/dev/null | wc -l | tr -d ' ')

  runs="-" green="-"
  if [ "$have_gh" = 1 ]; then
    slug=$(git -C "$repo" remote get-url origin 2>/dev/null | sed -E 's|.*github.com[:/]||; s|\.git$||')
    if [ -n "$slug" ]; then
      json=$(gh run list -R "$slug" --limit 100 --json conclusion 2>/dev/null)
      if [ -n "$json" ] && [ "$json" != "[]" ]; then
        runs=$(echo "$json" | jq 'length')
        green=$(echo "$json" | jq '[.[]|select(.conclusion=="success")]|length')
      else
        runs=0 green=0
      fi
    fi
  fi

  flag=""
  [ "$nwf" = "0" ] && [ "$itest" != "0" ] && flag="  <- NO WORKFLOWS AT ALL"
  [ "$nwf" != "0" ] && [ "$runs" = "0" ] && flag="  <- NEVER RAN"
  [ "$itest" != "0" ] && [ "$ici" = "0" ] && flag="$flag  <- $itest integration files, no CI runs them"
  [ -z "$flag" ] && continue

  printf '  %-22s %-8s %-10s %-8s %s%s\n' "$name" "$nwf" "$runs/$green" "$itest" "$ici" "$flag"
done

echo
echo "Fix pattern for the third class: see mpp/.github/workflows/integration.yml"
echo "(nightly cron + workflow_dispatch, secrets documented in the header, tests"
echo " flunk loudly on missing credentials rather than skipping)."
