# marketplace-hygiene

Two marketplace-integrity hooks for the `deltahedge` plugin marketplace. Self-contained — no plugin-internal dependencies, no shared-lib sourcing.

## Hooks

### `block-skill-edits.sh` (PreToolUse / Edit|Write|MultiEdit)

Denies any direct edit to a `plugins/*/skills/*/SKILL.md` file that is registered in `scripts/skill-include-map.sh`. Those bodies are auto-synced from `~/.claude/includes/<name>.md` and would be overwritten on the next `./scripts/sync-skills-from-includes.sh` run.

The deny message names the canonical include file. Unmapped SKILL.md files (legitimately hand-edited skills like `workflow-generator`, `tidewave-guide`, etc.) pass through.

Example deny when editing `plugins/elixir/skills/elixir-setup/SKILL.md`:

```
This SKILL.md is auto-synced from ~/.claude/includes/elixir-setup.md — direct edits will be overwritten by ./scripts/sync-skills-from-includes.sh on the next run.

Edit the canonical include instead:
  ~/.claude/includes/elixir-setup.md

Then run the sync script to regenerate the SKILL.md body:
  ./scripts/sync-skills-from-includes.sh
```

### `validate-marketplace-json.sh` (PostToolUse / Edit|Write|MultiEdit)

After an edit to any file basenamed `marketplace.json`, `plugin.json`, or `hooks.json`, runs `jq -e . "$FILE" >/dev/null` and surfaces parse errors as `additionalContext`. Replaces the manual `cat … | jq .` step documented in CLAUDE.md.

Example output on a broken edit:

```
=== Invalid JSON in marketplace.json ===
jq could not parse /…/marketplace.json after this edit. The marketplace will fail to load until this is fixed.

jq error:
parse error: Expected another key-value pair at line 12, column 3
```

Silent on valid JSON and on non-matching files.

## Install

```
/plugin install marketplace-hygiene@deltahedge
```

## Tests

```bash
./test/plugins/marketplace-hygiene/test-marketplace-hygiene-hooks.sh
```
