---
description: Run post-commit / post-merge audit review against an unaudited commit range. Writes .audit/<sha>.md reports, auto-applies hygiene fixes, commits as audit(...). Fully autonomous — no per-finding approval gates.
argument-hint: "[<sha> | <range> | --full <sha>|<range> | (default: tail since last audit commit)]"
allowed-tools: Skill
---

Invoke the audit-review skill against the requested commit range.

**Arguments handling:**
- No argument → default range is `<last-audit-commit-sha>..HEAD` exclusive. If no prior `audit(...)` commit exists, bound to last 20 commits.
- Single SHA → audit that commit only (`<sha>^..<sha>`).
- Range (`A..B` or `A...B`) → audit that range verbatim.
- `--full` flag → suppress the tiny-commit fast-path classification for the rest of the arguments. Use when you want a full audit on tiny commits (typo fix, doc tweak) that would otherwise route to fast-path.

The skill itself decides: it skips already-audited SHAs, classifies each commit as tiny vs full, dispatches Codex in parallel for non-tiny commits, auto-applies rated 3-10 + actionable + `discuss-trivial` findings, auto-resolves `discuss-design` via Claude+Codex dialogue (convergence applies; divergence drops + files as ROADMAP candidate), writes `.audit/<sha>.md` per commit, and commits as `audit(...)`.

The only confirmation gate is range-too-wide (>50 commits). Everything else runs end-to-end without user prompts.

Skill(command="audit-review")
