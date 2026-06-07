#!/usr/bin/env bash
# Sync the canonical .coderabbit.yaml from claude-marketplace/templates/ into
# the cwd (a target repo's root). Comments-only mode: no orphan autofix
# branches, no racing UTG PRs.
#
# Idempotent. Refuses to overwrite a customized local file unless --force is
# passed. The template carries a 'Synced from claude-marketplace' marker line;
# if that marker is present locally, the file is treated as previously synced
# and overwritten silently. If the marker is missing AND content diverges from
# the template, the script refuses (to avoid clobbering an intentional
# repo-specific customization).
#
# Usage:
#   ./sync-coderabbit-yaml.sh             # write .coderabbit.yaml
#   ./sync-coderabbit-yaml.sh --dry-run   # print what would be written
#   ./sync-coderabbit-yaml.sh --force     # overwrite regardless of marker

set -euo pipefail

DRY_RUN=false
FORCE=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --force) FORCE=true ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../templates/.coderabbit.yaml"
TARGET="./.coderabbit.yaml"
MARKER="Synced from claude-marketplace"

if [[ ! -f "$TEMPLATE" ]]; then
  echo "ERROR: template not found at $TEMPLATE" >&2
  exit 1
fi

if [[ -f "$TARGET" ]] && [[ "$FORCE" != true ]]; then
  if ! grep -qF "$MARKER" "$TARGET"; then
    if ! diff -q "$TEMPLATE" "$TARGET" >/dev/null 2>&1; then
      echo "ERROR: $TARGET exists, lacks the sync marker, and diverges from the template." >&2
      echo "Refusing to overwrite an intentional customization. Diff:" >&2
      diff -u "$TARGET" "$TEMPLATE" >&2 || true
      echo >&2
      echo "Re-run with --force to overwrite anyway." >&2
      exit 1
    fi
  fi
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "--- Would write to $TARGET ---"
  cat "$TEMPLATE"
  echo "--- Dry run, no file changes ---" >&2
  exit 0
fi

cp "$TEMPLATE" "$TARGET"
echo "Wrote $TARGET (synced from $TEMPLATE)"
