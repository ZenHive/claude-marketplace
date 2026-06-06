#!/usr/bin/env bash
# PostToolUse hook: regenerate AGENTS.md when CLAUDE.md or imported includes change.
#
# Trigger set:
#   - $USER_CLAUDE_ROOT/CLAUDE.md           → portfolio walk
#   - $USER_CLAUDE_ROOT/includes/*.md       → portfolio walk (direct children only)
#   - $PORTFOLIO_ROOT/<repo>/CLAUDE.md      → single-repo sync
#   - anything else                         → suppress, exit 0
#
# Repos without an existing AGENTS.md are skipped (don't auto-create).
# No git operations — user controls staging/commit.

set -eo pipefail

PORTFOLIO_ROOT="${AGENTS_SYNC_PORTFOLIO_ROOT:-$HOME/_DATA/code}"
USER_CLAUDE_ROOT="${AGENTS_SYNC_USER_CLAUDE_ROOT:-$HOME/.claude}"
SYNC_SCRIPT="${AGENTS_SYNC_SCRIPT:-${CLAUDE_PLUGIN_ROOT%/plugins/cloud-delegation}/scripts/sync-agents-md.sh}"

# Normalize roots so comparisons survive symlinks (e.g. macOS /tmp → /private/tmp)
PORTFOLIO_ROOT=$(realpath "$PORTFOLIO_ROOT" 2>/dev/null || echo "$PORTFOLIO_ROOT")
USER_CLAUDE_ROOT=$(realpath "$USER_CLAUDE_ROOT" 2>/dev/null || echo "$USER_CLAUDE_ROOT")

emit_suppress() { jq -n '{"suppressOutput": true}'; exit 0; }

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[[ -z "$FILE" || "$FILE" == "null" ]] && emit_suppress
FILE=$(realpath "$FILE" 2>/dev/null || echo "$FILE")

[[ -x "$SYNC_SCRIPT" ]] || emit_suppress

TOUCHED=()
FAILED=()

run_sync() {
  local repo="$1"
  if ( cd "$repo" && "$SYNC_SCRIPT" >/dev/null 2>&1 ); then
    TOUCHED+=("$repo")
  else
    FAILED+=("$repo")
  fi
}

walk_portfolio() {
  shopt -s nullglob
  local repo
  for repo in "$PORTFOLIO_ROOT"/*/; do
    repo="${repo%/}"
    [[ -f "$repo/CLAUDE.md" && -f "$repo/AGENTS.md" ]] || continue
    run_sync "$repo"
  done
}

# Path classification (first match wins)
if [[ "$FILE" == "$USER_CLAUDE_ROOT/CLAUDE.md" ]]; then
  walk_portfolio
elif [[ "$FILE" == "$USER_CLAUDE_ROOT/includes/"*.md && "$FILE" != *"/includes/"*"/"*".md" ]]; then
  # direct children of includes/ only — exclude nested subdirs
  walk_portfolio
elif [[ "$FILE" == "$PORTFOLIO_ROOT/"*"/CLAUDE.md" ]]; then
  rel="${FILE#$PORTFOLIO_ROOT/}"
  # exactly one path segment under portfolio root
  if [[ "$rel" == */CLAUDE.md && "$rel" != */*/CLAUDE.md ]]; then
    repo_dir="${FILE%/CLAUDE.md}"
    if [[ -f "$repo_dir/AGENTS.md" ]]; then
      run_sync "$repo_dir"
    fi
  fi
fi

if (( ${#TOUCHED[@]} == 0 && ${#FAILED[@]} == 0 )); then
  emit_suppress
fi

body=""
if (( ${#TOUCHED[@]} > 0 )); then
  body="🔄 AGENTS.md regenerated:"
  for r in "${TOUCHED[@]}"; do body+=$'\n'"  - $r"; done
fi
for f in "${FAILED[@]}"; do
  if [[ -n "$body" ]]; then body+=$'\n'; fi
  body+="⚠️ failed: $f"
done

jq -n --arg ctx "$body" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $ctx
  }
}'
exit 0
