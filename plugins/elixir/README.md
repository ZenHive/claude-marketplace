# elixir

Essential Elixir development support plugin for Claude Code.

## Installation

```bash
claude
/plugin install elixir@deltahedge
```

### Cursor hooks (Agent)

Claude Code plugins register hooks in Claude’s schema (`PostToolUse`, `hookSpecificOutput`, …). **Cursor** loads hooks from `~/.cursor/hooks.json` or `<repo>/.cursor/hooks.json` with a different JSON schema (`additional_context` on stdout for `postToolUse`). Importing the marketplace into Cursor does **not** translate those shapes automatically—use the adapter scripts in `scripts/`:

| Script | Runs |
|--------|------|
| [`scripts/cursor-post-edit-adapt.sh`](scripts/cursor-post-edit-adapt.sh) | [`scripts/post-edit-check.sh`](scripts/post-edit-check.sh) (format, compile, tests, credo, …) |
| [`scripts/cursor-ash-codegen-adapt.sh`](scripts/cursor-ash-codegen-adapt.sh) | [`scripts/ash-codegen-check.sh`](scripts/ash-codegen-check.sh) (Ash projects only; suppresses otherwise) |

1. Copy [`cursor-hooks.example.json`](cursor-hooks.example.json) to `~/.cursor/hooks.json` (global) or `.cursor/hooks.json` (project). Replace `/ABS/PATH/TO/marketplace/plugins/elixir` with the absolute path to **this** plugin directory on disk (the folder that contains `scripts/`).
2. `chmod +x` both adapter scripts (and ensure `jq` is on `PATH`).
3. Restart Cursor or save `hooks.json`; trigger an Agent **Write** on an `.ex` file and check the Hooks output channel. See [Cursor Hooks](https://cursor.com/docs/hooks) and [Third-party hooks](https://cursor.com/docs/reference/third-party-hooks.md).

**Project hooks:** use paths like `.cursor/hooks/…` relative to the repo root and **copy or symlink** the adapter scripts into `.cursor/hooks/` if you do not want absolute paths to the marketplace clone.

## Requirements

- Elixir installed and available in PATH
- Mix available
- Run from an Elixir project directory (with mix.exs)
- curl and jq (for hex-docs-search skill)

## Features

### Automatic Hooks

Each hook is tagged as **convention** (permanent quality gate) or **model-limitation** (compensates for current model weaknesses — review when models improve). See [workflow philosophy](https://www.anthropic.com/engineering/harness-design-long-running-apps) for rationale.

**PostToolUse - After file edits:**
- ✅ **Auto-format** `[convention]` - Automatically runs `mix format` on edited .ex/.exs files
- ✅ **Compile check** `[convention]` - Runs `mix compile --warnings-as-errors` to catch errors immediately
- ✅ **Hidden test failure detection** `[convention]` - Warns when test files contain patterns that silently pass on errors
- ✅ **Private function docs check** `[convention]` - Warns when `defp` functions are missing `@doc false` or comments
- ✅ **Typespec check** `[convention]` - Warns when public `def` functions are missing `@spec`
- ✅ **Typedoc check** `[convention]` - Warns when type definitions are missing `@typedoc`
- ✅ **Warn on doctest IO + untagged TODOs** `[convention]` - Warns when `IO.puts` / `IO.inspect` appears inside an `@doc` heredoc, or when a `#` comment begins with a deferred-work phrase (`For now,`, `Currently,`, `Temporarily,`, `In production,`, `This is a workaround,`) without a `TODO:` prefix that credo can track

**PostToolUse - After reading files:**
- ✅ **Documentation recommendation on read** `[model-limitation]` - Detects dependency usage in files and suggests documentation lookup

**PreToolUse - Before bash commands:**
- ✅ **Pre-commit validation** `[convention]` - Ensures code is formatted, compiles, and has no unused deps before committing
- ✅ **Block destructive bash** `[convention]` - Blocks `mix phx.server` (server is always already running) and destructive deps/build (`mix deps.clean`, `mix clean`, `mix deps.unlock --all`, `rm -rf _build`, `rm -rf deps`). Allows `mix deps.unlock --check-unused` and `mix deps.compile <dep> --force`. Bare `rm` (ordinary file deletion) is **not** blocked — only the `rm -rf _build` / `rm -rf deps` targets above
- ✅ **Warn shell-eval Elixir** `[model-limitation]` - Warns (non-blocking) when Claude is about to run `mix run -e`, `elixir -e`, `iex -e`, or `mix run X.exs` — suggests `mcp__tidewave__project_eval` for same-BEAM evaluation without fresh-VM startup. Legitimate exceptions named in the warning footer
- ✅ **Warn missing tool flags** `[model-limitation]` - Warns when `mix credo` is invoked without `--strict --format json`, or when `mix compile` is run without a `time` prefix (per `development-commands.md`)

**PreToolUse - Before mix test / dialyzer:**
- ✅ **Suggest --failed** `[model-limitation]` - On 2nd consecutive `mix test`, suggests `--failed --trace` to speed up test-fix cycles
- ✅ **Prefer test.json** `[convention]` - Silently rewrites `mix test` → `mix test.json` (args preserved) for AI-friendly output
- ✅ **Prefer dialyzer.json** `[convention]` - Silently rewrites `mix dialyzer` → `mix dialyzer.json` (args preserved) for AI-friendly output
- ✅ **Suggest --include on test.json** `[model-limitation]` - When `mix test.json` runs without `--include`, reads `test/test_helper.exs` and injects the excluded tags into context so Claude can't falsely claim a full-suite pass. Non-blocking (doesn't force slow integration runs on every iteration).

**UserPromptSubmit - On user input:**
- ✅ **Documentation recommendation** `[model-limitation]` - Suggests using documentation skills when prompt mentions project dependencies

**SessionStart - On session start:**
- ✅ **Branch behind origin/main** `[convention]` - `git fetch origin main` and warns if the working branch is behind. Pairs with the `[CX]` Codex delegation flow (`task-driver` Step 3.5) so Claude rebases before reviewing a PR or claiming a roadmap task that Codex may have advanced. Fails open on no-repo / fetch errors.

### Skills

**hex-docs-search** - Intelligent Hex package documentation search with progressive fetching:
- 🔍 **Local deps search** - Searches installed packages in `deps/` directory for code and docs
- 💾 **Fetched cache** - Checks previously fetched documentation and source in `.hex-docs/` and `.hex-packages/`
- ⬇️ **Progressive fetch** - Automatically fetches missing documentation or source code locally (with version prompting)
- 📚 **Codebase usage** - Finds real-world usage examples from your project
- 🌐 **HexDocs API** - Queries hex.pm API for official documentation
- 🔎 **Web fallback** - Uses web search when other methods don't provide enough information
- 🚀 **Offline-capable** - Once fetched, documentation and source available without network access

See [skills/hex-docs-search/SKILL.md](skills/hex-docs-search/SKILL.md) for details.

**usage-rules** - Package best practices and coding conventions search:
- 🔍 **Local deps search** - Searches installed packages in `deps/` for usage-rules.md files
- 💾 **Fetched cache** - Checks previously fetched rules in `.usage-rules/`
- ⬇️ **Progressive fetch** - Automatically fetches missing usage rules when needed
- 🎯 **Context-aware** - Extracts relevant sections based on coding context (querying, errors, etc.)
- 📝 **Pattern examples** - Shows good/bad code examples from package maintainers
- 🤝 **Integrates with hex-docs-search** - Combine for comprehensive "best practices + API" guidance
- 🚀 **Offline-capable** - Once fetched, usage rules available without network access

See [skills/usage-rules/SKILL.md](skills/usage-rules/SKILL.md) for details.

**elixir-ci-harness** - Copy-ready GitHub Actions workflow for Elixir delegation-target repos:
- ⚙️ **Drift-free version sourcing** - `setup-beam` reads `.tool-versions` directly (no matrix-pin drift between local and CI `mix format`)
- ✅ **Full harness gate** - format / compile (warnings-as-errors) / credo --strict --ignore TagTODO,TagFIXME / doctor --raise / sobelow / test.json with coverage gate / dialyzer
- 🎯 **Closes the Codex-Cloud-no-hex.pm gap** - CI runs the harness Codex's env can't, so reviewers read `gh pr checks` instead of running mix locally
- 📋 **Two template variants** - default single-version (drift-free); forward-compat multi-version addendum (catches dep-version issues at PR-open time during runtime migrations)
- 🎚️ **Threshold tuning documented** - 80% / 85% / 95% with cartouche worked example

See [skills/elixir-ci-harness/SKILL.md](skills/elixir-ci-harness/SKILL.md) for details.

## Hook Timeouts

| Hook | Timeout | Rationale |
|------|---------|-----------|
| auto-format | 15s | Single file formatting is fast |
| compile-check | 20s | Incremental compilation after edit |
| detect-hidden-failures | 10s | Pattern matching in test files |
| private-function-docs-check | 10s | Line-by-line pattern matching |
| typespec-check | 10s | Line-by-line pattern matching |
| typedoc-check | 10s | Line-by-line pattern matching |
| recommend-docs-on-read | 10s | Dependency detection in file |
| pre-commit-check | 45s | Format check + compile + unused deps |
| suggest-test-failed | 5s | Counter check and JSON output |
| reset-test-tracker | 5s | Check output for "0 failures" |
| recommend-docs-lookup | 10s | Dependency matching in user prompt |
| prefer-test-json | 5s | Command pattern matching |
| prefer-dialyzer-json | 5s | Command pattern matching |

## Hooks Behavior

### Auto-format (Non-blocking)
```bash
mix format {{file_path}}
```
- Runs automatically after editing .ex or .exs files
- Non-blocking - just formats and continues
- Fast - only formats the changed file

### Compile Check (Blocking on errors)
```bash
mix compile --warnings-as-errors
```
- Runs after editing .ex or .exs files
- Blocks on compilation errors - Claude must fix before continuing
- Output truncated to 50 lines to avoid overwhelming context

### Hidden Test Failure Detection (Non-blocking)
- Runs after editing `_test.exs` files
- Detects patterns that silently pass on errors:
  - `{:error, _} -> assert true` (makes ALL failures pass)
  - `{:error, _reason} -> :ok` (silent pass on any error)
- Provides warning via `additionalContext` with correct alternatives
- Non-blocking - warns but doesn't prevent edits
- **Why this matters:** Tests should FAIL on unexpected errors. Silent passes hide bugs.

### Private Function Docs Check (Non-blocking)
- Runs after editing `.ex` files (skips test files)
- Warns when `defp` functions are missing:
  - `@doc false` - explicitly marks function as private
  - Explanatory comment - describes what the function does
- Handles multi-clause functions (only checks first clause)
- Exempts one-liner functions from comment requirement
- Non-blocking - provides context via `additionalContext`
- **Why this matters:** `@doc false` signals intent; comments help future readers.

### Typespec Check (Non-blocking)
- Runs after editing `.ex` files (skips test files)
- Warns when public `def` functions are missing `@spec`
- Checks up to 5 lines above for matching `@spec function_name`
- Exempts callback implementations (functions with `@impl true`)
- Handles multi-clause functions (only checks first clause)
- Non-blocking - provides context via `additionalContext`
- **Why this matters:** Specs enable Dialyzer, improve documentation, and clarify types.

### Typedoc Check (Non-blocking)
- Runs after editing `.ex` files (skips test files)
- Warns when type definitions are missing `@typedoc`:
  - `@type` - public types
  - `@typep` - private types
  - `@opaque` - opaque types
- Checks up to 3 lines above for `@typedoc`
- Non-blocking - provides context via `additionalContext`
- **Why this matters:** Typedocs explain what types represent and their structure.

### Pre-commit Validation (Blocking)
```bash
mix format --check-formatted &&
mix compile --warnings-as-errors &&
mix deps.unlock --check-unused
```
- Runs before any `git commit` command (including `git add && git commit`)
- Blocks commit if any check fails
- Inline gate (each optional check gated on the dep being present): format, compile (warnings-as-errors), unused deps, credo, doctor, sobelow, mix_audit, ash.codegen
- **No tests, no dialyzer, no ex_doc** — tests run per-edit via `post-edit-check.sh`; tests/dialyzer/`mix docs` belong in CI / manual `mix precommit` / `mix precommit.full`. This keeps the commit gate fast and free of flaky-test denials and slow doc-builds.
- **Authoritative** — the hook runs its own checks and does **not** defer to a project `mix precommit` alias (that alias is for manual / CI use).
- **Saved output**: each failing check's full untruncated output is written to `/tmp/elixir-precommit/<sha256(project_root)>/<check>.log` and the paths are listed in the deny message — read those instead of re-running the check.

### Suggest --failed for Repeated Tests (Non-blocking)
- Runs before `mix test` commands (without `--failed`)
- On 2nd consecutive run, suggests optimization flags:
  - `mix test --failed` - only runs previously failed tests
  - `mix test --failed --trace` - adds detailed output
  - `mix test --failed --seed 0` - deterministic order for debugging
- Counter resets when:
  - User runs `mix test --failed`
  - Tests pass (0 failures in output)
  - 10 minutes elapse between test runs
- **Why this matters**: Running full test suite repeatedly while fixing failures wastes time

### Prefer test.json (Silent rewrite)
- Intercepts `mix test` commands and silently rewrites them to `mix test.json`, preserving any trailing args (e.g. `mix test --failed` → `mix test.json --failed`)
- Uses Claude Code's PreToolUse `updatedInput` mechanism — `permissionDecision: "allow"` with the rewritten command, so the shell only ever sees `mix test.json`
- Allows `mix test.json` variants to pass through unchanged (exclusion guard)
- If `ex_unit_json` is not installed, the rewritten `mix test.json` will surface mix's own task-not-found error; install hint included in `permissionDecisionReason`
- **Why this matters**: JSON output is easier for AI to parse and analyze; silent rewrite removes the deny→retype feedback loop

### Prefer dialyzer.json (Silent rewrite)
- Intercepts `mix dialyzer` commands and silently rewrites them to `mix dialyzer.json`, preserving any trailing args
- Uses the same `updatedInput` rewrite mechanism as prefer-test-json
- Allows `mix dialyzer.json` variants to pass through unchanged (exclusion guard)
- **Why this matters**: JSON output is easier for AI to parse and analyze

### Documentation Recommendation (Non-blocking)
- Runs when user submits a prompt
- Detects when prompt mentions project dependencies (e.g., "Ash", "Ecto", "Phoenix")
- Recommends using hex-docs-search or usage-rules skills for documentation lookup
- Uses fuzzy matching to handle case variations and naming conventions
- Caches dependency list in `.hex-docs/deps-cache.txt` for performance
- Cache invalidates when `mix.lock` changes

### Documentation Recommendation on Read (Non-blocking)
- Runs when reading .ex or .exs files
- Detects dependency module references in the file (e.g., `Jason.decode()`, `Ecto.Query.from()`)
- Extracts modules from both aliased (`alias Ecto.Query`) and direct usage (`Jason.decode()`)
- Smart matching: Reports both base and specific dependencies (e.g., `Phoenix.LiveView` → `phoenix, phoenix_live_view`)
- Excludes unrelated dependencies with similar names (e.g., won't report `phoenix_html` when only `Phoenix.LiveView` is used)
- Recommends using hex-docs-search or usage-rules skills for matched dependencies
- Shares dependency cache with UserPromptSubmit hook for efficiency
