#!/usr/bin/env bash
# Installs the chosen card providers and their shortcut commands (/dev-with-agents-<provider>) into ~/.claude.
# Usage: install-card-providers.sh <dotfiles dir> [--choose | --check | <provider>...]   Test: card-providers.test.sh
# The choice, first found: the names given here, else $CARD_PROVIDERS (space-separated; blank counts as unset),
# else <dotfiles>/card-providers.conf (names, # comments). The container build has no terminal and clones the
# dotfiles afresh, so what survives a rebuild is the conf as committed and pushed in the dotfiles repo.
# --choose shows a menu and ignores $CARD_PROVIDERS (Enter keeps the conf's choice). --check installs nothing: it
# fails when a provider of the same choice as an install is not installed (the install self-check).
# A provider no longer chosen is removed (its provider file and its shortcut only). A provider whose file left
# the dotfiles is not: remove its two files from ~/.claude by hand.
# A provider's MCP server has the provider's name. A missing one is not an error: the connector needs a login
# by hand, so the install prints how to add it (from the provider file) and goes on.
set -euo pipefail

usage="usage: install-card-providers.sh <dotfiles dir> [--choose | --check | <provider>...]"
[ $# -ge 1 ] || { echo "$usage" >&2; exit 2; }
src=$1; shift
mode=install
case "${1:-}" in
  --choose | --check)
    mode=${1#--}
    [ $# -eq 1 ] || { echo "Error: $1 takes no provider name." >&2; exit 1; }
    shift ;;
esac
for a in "$@"; do
  [[ $a != -* ]] || { echo "Error: $a must come first, right after the dotfiles dir." >&2; exit 1; }
done
conf="$src/card-providers.conf"

# The conf's names, each once, in order. The conf as an editor may save it: a byte order mark, Windows line
# endings, several names on a line. Read only when the choice comes from it.
conf_names() {
  [ -e "$conf" ] || [ -L "$conf" ] || return 0  # a dangling link is a broken conf, not a missing one
  [ -f "$conf" ] && [ -r "$conf" ] || { echo "Error: cannot read $conf." >&2; return 1; }
  local text
  text=$(sed '1s/^\xEF\xBB\xBF//; s/\r$//; s/#.*//' "$conf") || return 1
  printf '%s\n' "$text" | tr -s ' \t' '\n' | awk 'NF && !seen[$0]++'
}
set_of() { printf '%s\n' "$@" | sort -u | tr '\n' ' '; }

# The choice. A failing conf read stops here, before any file is touched.
if [ $# -gt 0 ]; then
  chosen=("$@")
elif [ "$mode" != choose ] && [[ ${CARD_PROVIDERS:-} =~ [^[:space:]] ]]; then
  read -rd '' -a chosen <<< "$CARD_PROVIDERS" || true  # every line, not just the first
else
  names=$(conf_names)
  mapfile -t conf_chosen <<< "$names"
  [ -n "$names" ] || conf_chosen=()
  chosen=("${conf_chosen[@]}")
fi

shopt -s nullglob
available=()
for f in "$src"/claude/card-providers/*.md; do available+=("$(basename "$f" .md)"); done
if [ ${#available[@]} -eq 0 ]; then
  [ ${#chosen[@]} -eq 0 ] || { echo "Error: no card provider in $src/claude/card-providers/." >&2; exit 1; }
  exit 0  # nothing to choose from, and nothing asked for: not an error
fi

if [ "$mode" = choose ]; then
  if [ ${#chosen[@]} -gt 0 ]; then default="keep: ${chosen[*]}"; else default="none (no name in $conf)"; fi
  echo "Card providers to install (numbers, space-separated; Enter = $default):"
  for i in "${!available[@]}"; do echo "  $((i + 1))) ${available[$i]}"; done
  read -ra numbers || true  # read -a: no glob expansion of the answer (`*` stays `*`)
  picked=()
  for n in "${numbers[@]}"; do
    # At most 3 digits, base 10: no octal 08, no integer overflow before the range check.
    [[ $n =~ ^[0-9]{1,3}$ ]] && ((10#$n >= 1 && 10#$n <= ${#available[@]})) \
      || { echo "Error: no provider number $n." >&2; exit 1; }
    picked+=("${available[$((10#$n - 1))]}")
  done
  [ ${#picked[@]} -eq 0 ] || chosen=("${picked[@]}")
fi
[ ${#chosen[@]} -gt 0 ] || [ "$mode" = check ] \
  || echo "No card provider chosen: list the ones you want in $conf (available: ${available[*]})."

# Every name is checked before any file is touched: exact match against the provider files, each kept once.
unique=()
for p in "${chosen[@]}"; do
  found=
  for a in "${available[@]}"; do [ "$p" = "$a" ] && found=1; done
  [ -n "$found" ] || { echo "Error: no card provider '$p'. Available: ${available[*]}" >&2; exit 1; }
  [[ " ${unique[*]} " == *" $p "* ]] || unique+=("$p")
done
chosen=("${unique[@]}")

if [ "$mode" = check ]; then
  missing=()
  for p in "${chosen[@]}"; do [ -f "$HOME/.claude/card-providers/$p.md" ] || missing+=("$p"); done
  [ ${#missing[@]} -eq 0 ] || { echo "Error: card provider not installed: ${missing[*]}" >&2; exit 1; }
  exit 0
fi
if [ "$mode" = choose ] && [ "$(set_of "${chosen[@]}")" != "$(set_of "${conf_chosen[@]}")" ]; then
  echo "To keep this choice after a rebuild, put \"${chosen[*]}\" in card-providers.conf of your dotfiles repo," \
    "then commit and push it."
fi

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
