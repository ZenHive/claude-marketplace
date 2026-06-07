#!/usr/bin/env bash
# Generate AGENTS.md for Codex by inlining @-imports from the project's CLAUDE.md.
#
# Manual tool. Run from inside a target repo. Reads ./CLAUDE.md, recursively
# resolves @-imports (e.g. @~/.claude/includes/critical-rules.md, including
# umbrella includes that themselves @-import other files), inlines their
# content, and writes ./AGENTS.md. Codex doesn't inherit our local Claude Code
# hooks, so AGENTS.md carries the rules those hooks would have enforced.
#
# Note: this used to fire automatically via a PostToolUse hook in the
# `delegation` plugin (`agents-md-sync.sh`). That auto-sync hook was retired in
# the deltahedge→zenhive migration; this standalone generator is the manual
# replacement. Re-add a hook wrapper around it if portfolio-wide auto-sync is
# wanted again.
#
# Recursion depth-limit matches Claude Code's documented @-import behavior
# (https://code.claude.com/docs/en/memory#import-additional-files): 5 levels.
#
# Usage:
#   ./sync-agents-md.sh             # write AGENTS.md
#   ./sync-agents-md.sh --dry-run   # print to stdout instead

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

CLAUDE_MD="./CLAUDE.md"
AGENTS_MD="./AGENTS.md"
MAX_DEPTH=5

if [[ ! -f "$CLAUDE_MD" ]]; then
  echo "ERROR: $CLAUDE_MD not found in current directory" >&2
  echo "Run this script from inside a repo with a CLAUDE.md at its root." >&2
  exit 1
fi

resolve_path() {
  local raw="$1"
  if [[ "$raw" == "~/"* ]]; then
    printf '%s' "$HOME/${raw:2}"
  else
    printf '%s' "$raw"
  fi
}

errors=0
output=""

# inline_file <path> <depth> [<raw_label>]
# Reads <path> line by line; on `@<path>` lines, recursively inlines the target
# (up to MAX_DEPTH levels). Appends to the global $output.
inline_file() {
  local path="$1"
  local depth="$2"
  local raw_label="${3:-$path}"

  if (( depth > MAX_DEPTH )); then
    echo "ERROR: @-import depth exceeded $MAX_DEPTH at $raw_label" >&2
    errors=$((errors + 1))
    return
  fi

  local line nested_raw nested_resolved
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^@([^[:space:]]+)[[:space:]]*$ ]]; then
      nested_raw="${BASH_REMATCH[1]}"
      nested_resolved=$(resolve_path "$nested_raw")

      if [[ ! -r "$nested_resolved" ]]; then
        echo "ERROR: cannot read @-import: $nested_raw (resolved to $nested_resolved)" >&2
        errors=$((errors + 1))
        continue
      fi

      output+="<!-- @-import: ${nested_raw} -->"$'\n'
      inline_file "$nested_resolved" $((depth + 1)) "$nested_raw"
      output+=$'\n'
    else
      output+="${line}"$'\n'
    fi
  done < "$path"
}

output+="<!-- Auto-generated from CLAUDE.md by claude-marketplace/scripts/sync-agents-md.sh — do not edit manually -->"$'\n'
output+=$'\n'

inline_file "$CLAUDE_MD" 1 "./CLAUDE.md"

if [[ "$errors" -gt 0 ]]; then
  echo "Aborting — $errors @-import(s) unreadable." >&2
  exit 1
fi

if [[ "$DRY_RUN" == true ]]; then
  printf '%s' "$output"
  echo ""
  echo "--- Summary ---" >&2
  echo "Dry run — would write to $AGENTS_MD" >&2
else
  printf '%s' "$output" > "$AGENTS_MD"
  echo "Wrote $AGENTS_MD"
fi
