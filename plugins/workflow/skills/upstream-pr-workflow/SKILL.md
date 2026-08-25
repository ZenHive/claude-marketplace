---
name: upstream-pr-workflow
description: Contributing PRs back to forked external libraries without leaking your personal dev tooling stack into the diff and without letting your project-scoped Claude hooks enforce your standards on their code. Use when working in a fork clone (or worktree off `upstream/main`), preparing an upstream PR, deciding which of your tools (`ex_unit_json`, `dialyzer_json`, `credo`, `tidewave`, `ex_dna`, etc.) are safe to layer in locally vs which would pollute the PR, or scoping a contribution so upstream's conventions win. Covers worktree vs separate-clone setup, the additive-vs-mandate distinction for tooling, and isolating hooks so they don't fire on upstream code.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/upstream-pr-workflow.md — do not edit manually -->

## Upstream PR Workflow (Forked Libraries)

How to contribute back to a forked external library without leaking your personal tooling stack into the PR diff — and without letting your project-scoped Claude hooks enforce *your* standards on *their* code.

### 1. When This Applies

You forked an external library on GitHub, cloned your fork, and want to land a PR upstream. This is the opposite of greenfield work in your own repos: **their conventions win**. Your full dev stack (`ex_unit_json`, `dialyzer_json`, `credo`, `tidewave`, `ex_dna`, etc.) is for *your* feedback loop, not a mandate to impose on maintainers who never opted into it.

### 2. Setup

Two shapes, pick by isolation need.

**Worktree off `upstream/main`** — fastest, reuses the existing fork clone:

```bash
cd /path/to/your-fork
git remote add upstream <upstream-url>    # one-time
git fetch upstream
git worktree add -b feat/<feature> ../upstream-<feature> upstream/main
cd ../upstream-<feature>
```

**Separate clone** — cleaner isolation when upstream's stack diverges heavily (different Elixir/OTP major, Erlang-only, polyglot repo where your Elixir tooling is just noise):

```bash
git clone <your-fork-url> ~/_DATA/code/upstream-<project>
cd ~/_DATA/code/upstream-<project>
git remote add upstream <upstream-url>
git fetch upstream
git checkout -b feat/<feature> upstream/main
```

The "no branches/worktrees without explicit permission" rule in `critical-rules.md` still governs — contributing upstream is itself the explicit task, so that permission is scoped to the contribution and nothing else.

### 3. Your Stack Works There (Mostly)

Your personal tooling is **additive** — it runs locally, produces reports, and doesn't touch upstream's code. Layer these into the clone's `mix.exs` under `only: [:dev, :test], runtime: false` and use them normally:

| Tool | Command | Safe upstream? |
|------|---------|----------------|
| ex_unit_json | `mix test.json --quiet` | ✅ read-only |
| dialyzer_json | `mix dialyzer.json --quiet` | ✅ read-only |
| credo | `mix credo --strict --format json` | ✅ read-only |
| dialyxir | `mix dialyzer` | ✅ read-only |
| ex_dna | `mix ex_dna` | ✅ read-only |
| ex_ast | `mix ex_ast.search 'pattern'` | ✅ `search` only — `ex_ast.replace` **rewrites files** |
| doctor | `mix doctor` | ✅ read-only |
| tidewave | `iex -S mix tidewave` + MCP | ✅ runtime-only |
| **styler** | — | **🚨 DO NOT ENABLE** |

Coverage thresholds, complexity KPIs, and Credo strictness are **your** standards — treat their output as advisory. Upstream's bar is upstream's bar.

**🚨 Styler is the exception — do NOT enable it unless upstream already uses it.** Every other tool in the stack is read-only relative to upstream's source. Styler is a `mix format` plugin: the moment `plugins: [Styler]` lands in `.formatter.exs`, every subsequent `mix format` — editor-on-save, PostToolUse hook, CI — aggressively restyles whatever file it touches to Styler conventions. That produces a PR diff full of unrelated reformatting that maintainers will (correctly) refuse. **Leave `.formatter.exs` exactly as upstream ships it.** If your muscle-memory includes adding Styler, actively resist.

### 4. Don't Leak Personal Tooling into the PR Diff

The tools run locally; their fingerprints stay local. Concrete "keep out of the staged diff" list:

- **`mix.exs`** — entries for `ex_unit_json`, `dialyzer_json`, `credo`, `dialyxir`, `doctor`, `tidewave`, `bandit` (if you added it for Tidewave), `ex_dna`, `ex_ast`, `descripex`, `api_toolkit`. Also `styler` — but per §3 you shouldn't have added it in the first place.
- **`cli/0`** — `preferred_envs` additions for `test.json` / `dialyzer.json`.
- **`.formatter.exs`** — must match upstream byte-for-byte. If you slipped and added a plugin, revert it *before* running `mix format` again, or the plugin's last run is already baked into your diff.
- **`.credo.exs`** — your strict/custom config.
- **`CLAUDE.md`** — your project instructions (checked-in files show up in diff).
- **`.mcp.json`** — your Tidewave port mapping.
- **`.ex_dna.exs`, `.dialyzer_ignore.exs`, `.doctor.exs`** — tool configs.
- **Inline pragmas** — `@no_clone true` (ex_dna), `sobelow_skip`, `@moduledoc false` stamped by Doctor workflows, etc.
- **`TODO:` comments** you added during exploration — Credo-visible for you, noise for them.

Run these before every commit:

```bash
git diff --cached --name-only        # what am I about to commit
git diff --cached | grep -E 'ex_unit_json|dialyzer_json|tidewave|styler|ex_dna|ex_ast|credo|doctor|@no_clone|TODO:'
```

If upstream ships its own `mix.exs` / `.credo.exs` / `.formatter.exs`, the clean pattern is:

1. Do the work with your local tooling edits present.
2. `git checkout upstream/main -- mix.exs .formatter.exs .credo.exs` to restore their versions.
3. Stage only your actual code changes.

### 5. Bypass Project Hooks with Your Shell Aliases

Claude Code's project-scoped hooks (`post-edit-check.sh`, `pre-commit-unified.sh`, dialyzer wrapper) match on the **literal command string** Claude sends via the Bash tool — `mix test`, `mix dialyzer`, `git commit`. Aliases expand inside zsh *after* the hook matcher has already decided to pass, so Claude invoking `mt` via the Bash tool bypasses the project's format/test hook even though the expanded form (`mix format && time mix test`) would have matched.

| Alias | Expands to | Why it bypasses |
|-------|------------|-----------------|
| `gc -m "msg"` | `git commit --verbose -m "msg"` | Hook matches `git commit`, not `gc` |
| `mt` | `mix format && time mix test` | Hook matches `mix test`, not `mt` |
| `mdlzer` | `mix dialyzer` | Hook matches `mix dialyzer`, not `mdlzer` |

`gc` takes the same flags as `git commit` (so `gc -m "msg"` or `gc -am "msg"` both work). Use a HEREDOC for multi-line messages exactly as you would with `git commit`.

**Use these directly via Bash** — `mt` for the suite, `mdlzer` for a dialyzer run, `gc -m "msg"` to commit. Claude running them is fine; the alias indirection does the work. Reserve `!` shell-escape for cases where you explicitly want the user to do the typing (e.g. interactive auth flows), not as a workaround for hooks the aliases already handle.

**When bypassing is appropriate (not just upstream contributions):** any forked or ported-in codebase where `pre-commit-unified.sh` flags pre-existing issues in files your current commit didn't touch — Credo style drift, Doctor spec-coverage gaps, Sobelow flags in legacy code, etc. The hook runs against the full project, not just the staged diff; a flagged issue is only load-bearing when it's *in your diff*. Before using `gc`, confirm with `git diff --cached --name-only` that the flagged files aren't yours. If they are, fix the issue instead.

**Still do not bypass** when the flag is inside your staged diff, when tests actually fail (that's a correctness failure, not a style artifact), or when the user asks you to fix the issue instead of bypass it. The default remains global `critical-rules.md`: "never skip hooks without explicit request" — these aliases are that explicit request, configured once in the shell.

### 🚨 NEVER open an issue or a PR yourself — the human presses send

Fork, branch, commit, push to **your own fork**: all fine, all reversible, all invisible
to the upstream project. **`gh pr create` and `gh issue create` are where it stops.**
Prepare the branch and the body, hand both to the user, and let them open it.

The instruction "make a PR for this" authorizes the *work*, not the *publication*. Those
are different acts: the branch is private until the moment a PR exists, and from that
moment on the text is public, attributed to the user's GitHub identity, visible to the
maintainers, and mailed to every watcher. It cannot be unsent — closing a PR leaves it in
the record.

**What this actually prevents is not rudeness, it's acting on stale context.** Worked
example (muex, 2026-08-24): a PR was opened against an issue the user had filed, without
reading the maintainer's reply on that issue. The reply said "Expect it to be fixed" —
they were taking it — and prescribed a *different* implementation than the one being
shipped. Every fact needed to not do that was one `gh issue view --comments` away. The
agent had queried the issue, but read only the metadata.

So, before handing any upstream contribution to the user:

- **Read the full thread**, not the metadata. `gh issue view <n> --repo <o/r> --comments`
  and `gh pr list --repo <o/r> --state all`. A comment count is not a comment.
- **Check whether a maintainer has claimed it or prescribed an approach.** Contributing an
  implementation they already ruled against wastes their review and looks like not reading.
- **Show the user the PR/issue body before it goes out.** It is published under their name.
- Their decision is the gate even when they asked for the PR. Re-confirm at publish time.

### 6. Cleanup

After the PR merges or is abandoned:

- **Worktree:** from the main fork clone, `git worktree remove <path>` then `git branch -D feat/<feature>`. Removing the worktree is part of completing the task — orphan worktrees are the failure mode that earned the "no worktrees without permission" rule in `critical-rules.md`.
- **Separate clone:** `rm -rf <clone-dir>` (or move it to `~/.Trash` if you'd rather keep it recoverable) — double-check the path first per `critical-rules.md` shell-safety.
- **Keep your fork current:** on the main clone, `git fetch upstream && git merge upstream/main && git push origin main`, so the next contribution starts from a clean base.
