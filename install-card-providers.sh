#!/usr/bin/env bash
# Installs the chosen card providers and their shortcut commands (/dev-with-agents-<provider>) into ~/.claude.
# Usage: install-card-providers.sh <dotfiles dir> [--choose | <provider>...]   Test: card-providers.test.sh.
# The choice, first found: the names given here, else $CARD_PROVIDERS (space-separated), else
# <dotfiles>/card-providers.conf (one name per line, # comments). The container build has no terminal, so the
# file is what survives a rebuild. --choose shows a menu instead (Enter keeps the file's choice).
# A provider no longer chosen is removed (its provider file and its shortcut only). A provider whose file left
# the dotfiles is not: remove its two files from ~/.claude by hand.
# A provider's MCP server has the provider's name. A missing one is not an error: the connector needs a login
# by hand, so the install prints how to add it (from the provider file) and goes on.
set -euo pipefail

src=$1; shift
shopt -s nullglob
available=()
for f in "$src"/claude/card-providers/*.md; do available+=("$(basename "$f" .md)"); done
[ ${#available[@]} -gt 0 ] || exit 0  # no provider yet: nothing to choose, not an error

conf="$src/card-providers.conf"
# tr -d '\r': a conf saved with Windows line endings must not fail the container build.
from_conf() { [ -f "$conf" ] && tr -d '\r' < "$conf" | sed 's/#.*//' | tr -s ' \t' '\n' | grep -v '^$' || true; }

if [ "${1:-}" = --choose ]; then
  [ $# -eq 1 ] || { echo "Error: --choose takes no provider name; pick them in the menu." >&2; exit 1; }
  echo "Card providers to install (numbers, space-separated; Enter = keep card-providers.conf):"
  for i in "${!available[@]}"; do echo "  $((i + 1))) ${available[$i]}"; done
  read -ra numbers || true  # read -a: no glob expansion of the answer (`*` stays `*`)
  answer="${numbers[*]:-}"
  chosen=()
  for n in "${numbers[@]}"; do
    # At most 3 digits, base 10: no octal 08, no integer overflow before the range check.
    [[ $n =~ ^[0-9]{1,3}$ ]] && ((10#$n >= 1 && 10#$n <= ${#available[@]})) \
      || { echo "Error: no provider number $n." >&2; exit 1; }
    chosen+=("${available[$((10#$n - 1))]}")
  done
  [ ${#chosen[@]} -gt 0 ] || mapfile -t chosen < <(from_conf)
  [ -z "$answer" ] || echo "To keep this choice after a rebuild, put it in $conf."
elif [ $# -gt 0 ]; then
  chosen=("$@")
elif [ -n "${CARD_PROVIDERS:-}" ]; then
  read -ra chosen <<< "$CARD_PROVIDERS"
else
  mapfile -t chosen < <(from_conf)
fi
[ ${#chosen[@]} -gt 0 ] || echo "No card provider chosen: list the ones you want in $conf (available: ${available[*]})."

# Every name is checked before any file is touched: exact match against the provider files, each kept once.
unique=()
for p in "${chosen[@]}"; do
  found=
  for a in "${available[@]}"; do [ "$p" = "$a" ] && found=1; done
  [ -n "$found" ] || { echo "Error: no card provider '$p'. Available: ${available[*]}" >&2; exit 1; }
  [[ " ${unique[*]} " == *" $p "* ]] || unique+=("$p")
done
chosen=("${unique[@]}")

mkdir -p "$HOME/.claude/commands" "$HOME/.claude/card-providers"
for p in "${available[@]}"; do
  if [[ " ${chosen[*]} " == *" $p "* ]]; then
    cp "$src/claude/card-providers/$p.md" "$HOME/.claude/card-providers/"
    shortcut="$src/claude/commands/dev-with-agents-$p.md"
    [ ! -f "$shortcut" ] || cp "$shortcut" "$HOME/.claude/commands/"
  else
    rm -f "$HOME/.claude/card-providers/$p.md" "$HOME/.claude/commands/dev-with-agents-$p.md"
  fi
done

[ ${#chosen[@]} -gt 0 ] || exit 0
servers=$(claude mcp list 2> /dev/null || true)
for p in "${chosen[@]}"; do
  if ! grep -q "^$p:" <<< "$servers"; then
    echo "Card provider $p: its MCP server is not set up. Add it once, then log in with /mcp in Claude Code:"
    # A provider file without the line must not stop the container build (set -e).
    grep -m1 'claude mcp add' "$src/claude/card-providers/$p.md" | sed 's/^ *//' \
      || echo "  see the Connector part of $src/claude/card-providers/$p.md"
  fi
done
