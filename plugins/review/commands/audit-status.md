---
description: Show unaudited commit count per branch / repo. Read-only — no mutations.
argument-hint: "[--all]"
allowed-tools: Bash, Read, Glob
---

Snapshot of how far each repo / branch has drifted from its last `audit(...)` ancestor. Answers "is this repo current?" without running a full audit.

**Arguments:**
- (no arg) → current repo only
- `--all` → walk `~/_DATA/code/*` and aggregate across every repo with `audit(` history or a `.audit/` directory

**Implementation:**

The shared helper `${CLAUDE_PLUGIN_ROOT}/scripts/unaudited-commits.sh` does the ancestor-walk and prints TSV:

```
count<TAB>last_audit_sha<TAB>last_audit_date<TAB>range
```

Exit 0 in a git repo (TSV may be empty if `count < threshold`); exit 2 outside a git repo. Default threshold is 1, so any non-clean repo emits a row.

**Single-repo flow:**
1. Run the helper with `--threshold 1 --short-sha` from the current directory.
2. If exit 2 → print `Not in a git repo.` and stop.
3. If output is empty → print `✅ Current — no unaudited commits.` and stop.
4. Otherwise parse TSV and print a one-line table:
   ```
   | branch | unaudited | last audit | range |
   |--------|-----------|------------|-------|
   | <branch-from-`git branch --show-current`> | <count> | <last_audit_sha> (<last_audit_date>) or `none yet` | <range> |
   ```

**`--all` flow:**
1. Glob `~/_DATA/code/*` (one level deep, directories only).
2. For each entry that is a git repo (`git -C <dir> rev-parse --git-dir` succeeds), run the helper with `git -C <dir> ...` style — the helper uses the current working directory, so use a subshell: `(cd "$dir" && "${CLAUDE_PLUGIN_ROOT}/scripts/unaudited-commits.sh" --threshold 1 --short-sha)`.
3. Collect `(repo-name, branch, count, last_audit_sha, last_audit_date, range)` rows.
4. Skip repos that emit no row (clean) when reporting; print one summary line at the end: `<N> repos clean (omitted)`.
5. Sort the dirty rows by `count` descending and print the table.

**Constraints:**
- Read-only. No `git fetch`, no `git pull`, no commits, no writes outside stdout.
- Don't run any audits, don't invoke any other skill — this command exists exactly so the user can decide whether to.
- If the helper script is missing or non-executable, print a clear error pointing to `${CLAUDE_PLUGIN_ROOT}/scripts/unaudited-commits.sh` and stop.
