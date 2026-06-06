#!/usr/bin/env bash
# Migrate a repo's .claude/settings.json from the old `deltahedge` marketplace
# to `zenhive`. Safe for the 10 app repos whose only deltahedge refs are
# elixir / elixir-workflows / phoenix (plugin NAMES are identical across the two
# marketplaces — only the @marketplace suffix changes), so a blanket
# s/@deltahedge/@zenhive/ is correct there.
#
# DO NOT run this on crypto_bridge: that repo's enabledPlugins are the retired
# per-check micro-plugins (credo@ / dialyzer@ / sobelow@ / ex_unit@ / git@ /
# doctor@ / core@ / mix_audit@ / precommit@ / ash@ / claude-md-includes@).
# Those plugins DO NOT EXIST in zenhive — they consolidated into `elixir`.
# crypto_bridge needs a hand-authored enabledPlugins (likely just
# elixir@zenhive + ash via elixir), not a rename. The guard below refuses it.
#
# Usage:
#   migrate-repos-deltahedge-to-zenhive.sh                 # dry-run ALL repos under ~/_DATA/code
#   migrate-repos-deltahedge-to-zenhive.sh --apply         # apply to ALL eligible repos
#   migrate-repos-deltahedge-to-zenhive.sh <repo> [--apply]# single repo by path or name
#
# Dry-run is the default; nothing is written without --apply.

set -euo pipefail

CODE_ROOT="${CODE_ROOT:-$HOME/_DATA/code}"
APPLY=0
TARGET=""

for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    *) TARGET="$arg" ;;
  esac
done

# Resolve the target list.
if [[ -n "$TARGET" ]]; then
  if [[ -d "$TARGET" ]]; then
    REPOS=("$TARGET")
  else
    REPOS=("$CODE_ROOT/$TARGET")
  fi
else
  # All repos whose settings reference @deltahedge (bash 3.2-safe; no mapfile).
  REPOS=()
  while IFS= read -r f; do
    [[ -n "$f" ]] && REPOS+=("$(cd "$(dirname "$f")/.." && pwd)")
  done < <(grep -rl "@deltahedge" "$CODE_ROOT"/*/.claude/settings*.json 2>/dev/null | sort)
fi

# Retired micro-plugin ids that have NO zenhive equivalent — presence ⇒ refuse.
STALE_RE='(credo|dialyzer|sobelow|ex_unit|git|doctor|core|mix_audit|precommit|ash|claude-md-includes)@deltahedge'

changed=0 skipped=0
for repo in "${REPOS[@]}"; do
  for sf in "$repo/.claude/settings.json" "$repo/.claude/settings.local.json"; do
    [[ -f "$sf" ]] || continue
    grep -q "@deltahedge" "$sf" || continue

    if grep -Eq "$STALE_RE" "$sf"; then
      echo "SKIP  $sf — retired micro-plugin ids (no zenhive equivalent); remap by hand to elixir@zenhive"
      skipped=$((skipped + 1))
      continue
    fi

    n=$(grep -c "@deltahedge" "$sf")
    if [[ "$APPLY" -eq 1 ]]; then
      sed -i '' 's/@deltahedge/@zenhive/g' "$sf"
      echo "APPLY $sf — $n ref(s) renamed @deltahedge → @zenhive"
    else
      echo "DRY   $sf — would rename $n ref(s) @deltahedge → @zenhive"
      grep -o '"[a-zA-Z0-9_-]*@deltahedge"' "$sf" | sort | uniq -c | sed 's/^/        /'
    fi
    changed=$((changed + 1))
  done
done

echo "--- $( [[ $APPLY -eq 1 ]] && echo applied || echo would-change ): $changed file(s); skipped (manual): $skipped ---"
[[ "$APPLY" -eq 0 ]] && echo "(dry-run — re-run with --apply to write)"
exit 0
