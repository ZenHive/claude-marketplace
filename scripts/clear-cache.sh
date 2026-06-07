#!/usr/bin/env bash
# Clear the zenhive plugin cache and registry entries.
# Run this when plugins aren't updating properly or after major changes.
# Also cleans up the legacy deltahedge / claude-code-elixir namespaces if any
# stale entries remain from before the zenhive migration.

set -e

INSTALLED_PLUGINS="$HOME/.claude/plugins/installed_plugins.json"

# Namespaces to clean (current + legacy)
NAMESPACES=("zenhive" "deltahedge" "claude-code-elixir")

# Clear cache directories for all namespaces
for NS in "${NAMESPACES[@]}"; do
  CACHE_DIR="$HOME/.claude/plugins/cache/$NS"
  if [ -d "$CACHE_DIR" ]; then
    rm -rf "$CACHE_DIR"
    echo "Cleared plugin cache: $CACHE_DIR"
  fi
done

# Remove legacy namespaces from known_marketplaces.json (keep zenhive registered)
KNOWN_MARKETPLACES="$HOME/.claude/plugins/known_marketplaces.json"
if [ -f "$KNOWN_MARKETPLACES" ] && command -v jq &> /dev/null; then
  for NS in "deltahedge" "claude-code-elixir"; do
    if jq -e ".[\"$NS\"]" "$KNOWN_MARKETPLACES" > /dev/null 2>&1; then
      jq "del(.[\"$NS\"])" "$KNOWN_MARKETPLACES" > /tmp/known_marketplaces_clean.json && \
        mv /tmp/known_marketplaces_clean.json "$KNOWN_MARKETPLACES"
      echo "Removed $NS from known_marketplaces.json"
    fi
  done
fi

# Remove entries from installed_plugins.json for all namespaces
# This prevents "already installed" errors with stale project paths
if [ -f "$INSTALLED_PLUGINS" ] && command -v jq &> /dev/null; then
  for NS in "${NAMESPACES[@]}"; do
    COUNT=$(jq "[.plugins | keys[] | select(contains(\"$NS\"))] | length" "$INSTALLED_PLUGINS" 2>/dev/null)
    if [ "$COUNT" -gt 0 ]; then
      jq ".plugins = (.plugins | with_entries(select(.key | contains(\"$NS\") | not)))" \
        "$INSTALLED_PLUGINS" > /tmp/installed_plugins_clean.json && \
        mv /tmp/installed_plugins_clean.json "$INSTALLED_PLUGINS"
      echo "Removed $COUNT $NS entries from installed_plugins.json"
    fi
  done
else
  if [ ! -f "$INSTALLED_PLUGINS" ]; then
    echo "installed_plugins.json not found (nothing to clean)"
  elif ! command -v jq &> /dev/null; then
    echo "Warning: jq not installed, skipping installed_plugins.json cleanup"
  fi
fi

# Remove entries from enabledPlugins in settings.json for all namespaces
SETTINGS_FILE="$HOME/.claude/settings.json"
if [ -f "$SETTINGS_FILE" ] && command -v jq &> /dev/null; then
  for NS in "${NAMESPACES[@]}"; do
    COUNT=$(jq "[.enabledPlugins // {} | keys[] | select(contains(\"$NS\"))] | length" "$SETTINGS_FILE" 2>/dev/null)
    if [ "$COUNT" -gt 0 ]; then
      jq ".enabledPlugins = (.enabledPlugins // {} | with_entries(select(.key | contains(\"$NS\") | not)))" \
        "$SETTINGS_FILE" > /tmp/settings_clean.json && \
        mv /tmp/settings_clean.json "$SETTINGS_FILE"
      echo "Removed $COUNT $NS entries from settings.json enabledPlugins"
    fi
  done
fi

echo ""
echo "Cleaned namespaces: ${NAMESPACES[*]}"
echo ""
echo "Next steps:"
echo "  1. Restart Claude Code"
echo "  2. Run: /plugin marketplace add ZenHive/claude-marketplace"
echo "  3. Run: /plugin install elixir@zenhive"
echo ""
echo "Note: Always use GitHub format (owner/repo) instead of local paths for reliable installation."
