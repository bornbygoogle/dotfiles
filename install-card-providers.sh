#!/usr/bin/env bash
# Installs the card providers and their shortcut commands (/dev-with-agents-<provider>) into ~/.claude.
# Usage: install-card-providers.sh <dotfiles dir>   Test: card-providers.test.sh.
# A provider's MCP server has the provider's name. A missing one is not an error: the connector needs a login
# by hand, so the install prints how to add it (from the provider file) and goes on.
set -euo pipefail

src=$1
shopt -s nullglob  # no provider yet: nothing to copy, not an error
providers=("$src"/claude/card-providers/*.md)
shortcuts=("$src"/claude/commands/dev-with-agents-*.md)
[ ${#providers[@]} -gt 0 ] || exit 0
mkdir -p "$HOME/.claude/commands" "$HOME/.claude/card-providers"
cp "${providers[@]}" "$HOME/.claude/card-providers/"
[ ${#shortcuts[@]} -eq 0 ] || cp "${shortcuts[@]}" "$HOME/.claude/commands/"

servers=$(claude mcp list 2> /dev/null || true)
for f in "${providers[@]}"; do
  p=$(basename "$f" .md)
  if ! grep -q "^$p:" <<< "$servers"; then
    echo "Card provider $p: its MCP server is not set up. Add it once, then log in with /mcp in Claude Code:"
    # A provider file without the line must not stop the container build (set -e).
    grep -m1 'claude mcp add' "$f" | sed 's/^ *//' || echo "  see the Connector part of $f"
  fi
done
