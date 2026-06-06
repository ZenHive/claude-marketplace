#!/usr/bin/env bash
# PreToolUse hook: deny direct Edit|Write|MultiEdit on any plugin SKILL.md
# that is listed in scripts/skill-include-map.sh — those bodies are
# auto-synced from ~/.claude/includes/ and would be overwritten on the next
# `./scripts/sync-skills-from-includes.sh` run.
#
# Unmapped SKILL.md files (legitimate hand-edited skills) pass through.

set -eo pipefail

emit_suppress() { jq -n '{"suppressOutput": true}'; exit 0; }

emit_deny() {
  local reason="$1"
  local msg="$2"
  jq -n --arg reason "$reason" --arg msg "$msg" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    },
    systemMessage: $msg
  }'
  exit 0
}

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[[ -z "$FILE" || "$FILE" == "null" ]] && emit_suppress

# Derive REPO_ROOT from the EDITED file's directory, NOT from the hook
# script's own location. The hook ships inside the plugin install (typically
# ~/.claude/plugins/cache/<marketplace>/<plugin>/<ver>/) which is outside any
# git repo and has no access to scripts/skill-include-map.sh. The rule is
# about the user's working tree — that's where the canonical mapping lives.
FILE_ABS=$(realpath "$FILE" 2>/dev/null || echo "$FILE")
FILE_DIR=$(dirname "$FILE_ABS")
REPO_ROOT="$(git -C "$FILE_DIR" rev-parse --show-toplevel 2>/dev/null || echo "")"
MAP_FILE="$REPO_ROOT/scripts/skill-include-map.sh"

# Without a mapping file we cannot enforce the rule precisely — pass through.
# (Also true when the user edits a SKILL.md in a different repo that has no
# auto-sync setup of its own — the rule shouldn't fire there.)
[[ -z "$REPO_ROOT" || ! -f "$MAP_FILE" ]] && emit_suppress

# Normalize FILE to a path relative to REPO_ROOT (the mapping entries are
# stored repo-relative).
REL="$FILE_ABS"
case "$FILE_ABS" in
  "$REPO_ROOT"/*) REL="${FILE_ABS#"$REPO_ROOT"/}" ;;
esac

# Source the mapping (defines MAPPINGS array).
# shellcheck source=/dev/null
source "$MAP_FILE"

for entry in "${MAPPINGS[@]}"; do
  skill_path="${entry%%:*}"
  include="${entry##*:}"
  if [[ "$REL" == "$skill_path" ]]; then
    emit_deny \
      "This SKILL.md is auto-synced from ~/.claude/includes/$include — direct edits will be overwritten by ./scripts/sync-skills-from-includes.sh on the next run.

Edit the canonical include instead:
  ~/.claude/includes/$include

Then run the sync script to regenerate the SKILL.md body:
  ./scripts/sync-skills-from-includes.sh" \
      "marketplace-hygiene: SKILL.md is auto-synced from ~/.claude/includes/$include"
  fi
done

emit_suppress
