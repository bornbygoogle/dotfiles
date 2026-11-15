#!/usr/bin/env bash
# Runnable check for the card providers and their shortcut commands, on the real files: no network, no model.
set -u
here=$(cd "$(dirname "$0")" && pwd)
fail=0
check() {  # $1 = label, then the test command
  local label=$1; shift
  if "$@"; then echo "ok   $label"; else echo "FAIL $label"; fail=1; fi
}

providers="$here/claude/card-providers"
commands="$here/claude/commands"
yt="$providers/youtrack.md"
short="$commands/dev-with-agents-youtrack.md"

pairs_ok() {  # every shortcut has its provider, and the reverse; at least one pair
  local n=0 f p
  for f in "$commands"/dev-with-agents-*.md; do
    [ -e "$f" ] || return 1
    p=${f##*/dev-with-agents-}; [ -f "$providers/$p" ] || return 1; n=$((n + 1))
  done
  for f in "$providers"/*.md; do
    [ -e "$f" ] || return 1
    [ -f "$commands/dev-with-agents-${f##*/}" ] || return 1
  done
  [ "$n" -gt 0 ]
}
four_parts() {  # the four headings, each once, in this order
  local f
  for f in "$providers"/*.md; do
    [ "$(grep -E '^## (Connector|Id|Fetch|Mapping)$' "$f" | tr '\n' ' ')" \
      = "## Connector ## Id ## Fetch ## Mapping " ] || return 1
  done
}

check "every shortcut has its provider, and every provider its shortcut" pairs_ok
check "each provider has the four parts, in order" four_parts
check "the youtrack provider names its tools" \
  bash -c "grep -q 'get_issue\`' '$yt' && grep -q 'get_issue_comments' '$yt' && grep -q 'links: ' '$yt'"
check "the youtrack provider sets ERP as the default project" grep -qi 'default project key.*ERP' "$yt"
check "the youtrack provider maps a Bug card to --bugs, others to --feature" \
  bash -c "grep -q 'Bug.*--bugs' '$yt' && grep -q -- '--feature' '$yt'"
# get_issue's totalComments and recentComments still hold DELETED comments, with no marker (ERP-134,
# 2026-11-15): a brief built from them shows a deleted question as open. get_issue_comments is the only source.
check "the youtrack provider pages the linked cards" grep -q 'offset` by 20' "$yt"
check "the youtrack provider reads comments from get_issue_comments only" \
  grep -q 'only from `get_issue_comments`' "$yt"
check "the youtrack provider never resurrects a deleted comment" \
  bash -c "grep -q 'never use .*recentComments' '$yt' && ! grep -qi 'take the missing ones' '$yt'"
check "the shortcut expands to the full form" grep -q -- '--card-provider youtrack --card' "$short"
# /dev-with-agents-youtrack ERP-196 must not become ERP-ERP-196.
check "the shortcut keeps a full id as it is" grep -qi 'already.*-.*as it is' "$short"
# The repo is public: no tracker host name in any tracked file (this pattern names none).
check "no tracker host name in the dotfiles (public repo)" \
  bash -c "git -C '$here' rev-parse --git-dir > /dev/null && ! git -C '$here' grep --untracked -qiIE \
    'https?://[a-z0-9-]+\\.(youtrack\\.cloud|myjetbrains\\.com)' -- . ':!.superpowers'"

# install-card-providers.sh, on a throwaway $HOME with a fake `claude` that prints a canned `mcp list`.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home"
cat > "$tmp/bin/claude" << 'EOF'
#!/usr/bin/env bash
cat "$FAKE_MCP_LIST"
EOF
chmod +x "$tmp/bin/claude"
echo 'claude-mem: node … - ✔ Connected' > "$tmp/no-youtrack.txt"
printf 'youtrack: https://example.test/mcp (HTTP) - ✔ Connected\n' > "$tmp/with-youtrack.txt"
install() {  # $1 = the canned mcp list
  HOME="$tmp/home" PATH="$tmp/bin:$PATH" FAKE_MCP_LIST="$1" \
    bash "$here/install-card-providers.sh" "$here" > "$tmp/out.log" 2>&1
}
check "the installer runs when the connector is missing" install "$tmp/no-youtrack.txt"
check "it installs the shortcut command" test -f "$tmp/home/.claude/commands/dev-with-agents-youtrack.md"
check "it installs the provider file" test -f "$tmp/home/.claude/card-providers/youtrack.md"
check "a missing connector prints how to add it" \
  grep -q 'claude mcp add --transport http --scope user youtrack' "$tmp/out.log"
echo stale > "$tmp/home/.claude/card-providers/youtrack.md"  # the copy before a `git pull` of the dotfiles
check "a second run, connector present, succeeds" install "$tmp/with-youtrack.txt"
check "a present connector prints no hint" bash -c "! grep -q 'claude mcp add' '$tmp/out.log'"
check "a second run replaces a stale copy with the dotfiles version" \
  cmp -s "$yt" "$tmp/home/.claude/card-providers/youtrack.md"
check "install-agentic.sh calls the installer" grep -q 'install-card-providers.sh' "$here/install-agentic.sh"
# YouTrack is a choice now: an install that left it out of card-providers.conf must still pass its self-check.
check "the install self-check does not require one provider" \
  bash -c "! grep -q 'card-providers/youtrack.md' '$here/install-agentic.sh'"

# A dotfiles tree of our own: a provider whose Connector part has no `claude mcp add` line, and an empty tree.
mkdir -p "$tmp/df/claude/card-providers" "$tmp/df/claude/commands" "$tmp/empty/claude/card-providers" \
  "$tmp/empty/claude/commands" "$tmp/home2" "$tmp/home3"
printf '# Card provider: Jira\n\n## Connector\n\nThe MCP server named `jira`.\n' \
  > "$tmp/df/claude/card-providers/jira.md"
echo '# jira shortcut' > "$tmp/df/claude/commands/dev-with-agents-jira.md"
echo jira > "$tmp/df/card-providers.conf"
install_from() {  # $1 = dotfiles dir, $2 = home
  HOME="$2" PATH="$tmp/bin:$PATH" FAKE_MCP_LIST="$tmp/no-youtrack.txt" \
    bash "$here/install-card-providers.sh" "$1" > "$tmp/out.log" 2>&1
}
check "a provider without an add command still installs, and says where to look" \
  bash -c "$(declare -f install_from); tmp='$tmp' here='$here' install_from '$tmp/df' '$tmp/home2' \
    && grep -q 'Connector' '$tmp/out.log'"
check "no provider files at all is not an error" \
  bash -c "$(declare -f install_from); tmp='$tmp' here='$here' install_from '$tmp/empty' '$tmp/home3'"

# Choosing the providers: names on the command line, else CARD_PROVIDERS, else card-providers.conf;
# `--choose` shows a menu. Two providers of our own, alpha and beta, and card-providers.conf picks alpha.
check "the dotfiles ship a card-providers.conf that picks youtrack" \
  bash -c "grep -v '^ *#' '$here/card-providers.conf' | grep -qx youtrack"
two="$tmp/two"; h="$tmp/h"
mkdir -p "$two/claude/card-providers" "$two/claude/commands" "$h/.claude/commands"
for p in alpha beta; do
  printf '# %s\n\n## Connector\n\n    claude mcp add %s\n' "$p" "$p" > "$two/claude/card-providers/$p.md"
  echo "# $p shortcut" > "$two/claude/commands/dev-with-agents-$p.md"
done
printf '# my card providers\n\nalpha\n' > "$two/card-providers.conf"
echo mine > "$h/.claude/commands/other.md"
mkdir -p "$tmp/cwd" && touch "$tmp/cwd/a-file"  # a glob in a menu answer would expand to it
pick() {  # pick [VAR=value…] -- [installer args…]: runs the installer on $two into $h
  local envs=()
  while [ "$1" != -- ]; do envs+=("$1"); shift; done; shift
  (cd "$tmp/cwd" && env HOME="$h" PATH="$tmp/bin:$PATH" FAKE_MCP_LIST="$tmp/no-youtrack.txt" "${envs[@]}" \
    bash "$here/install-card-providers.sh" "$two" "$@") > "$tmp/out.log" 2>&1 < "${MENU_INPUT:-/dev/null}"
}
installed() {  # the providers installed in $h, space-separated, sorted
  (cd "$h/.claude/card-providers" 2> /dev/null && ls) | sed 's/\.md$//' | sort | tr '\n' ' ' | sed 's/ $//'
}
shortcuts() {
  (cd "$h/.claude/commands" && ls dev-with-agents-*.md 2> /dev/null) | sort | tr '\n' ' ' | sed 's/ $//'
}
menu() { printf '%s\n' "$1" > "$tmp/menu"; MENU_INPUT="$tmp/menu" pick -- --choose; }
pick --
check "card-providers.conf decides, comments and blank lines skipped" test "$(installed)" = alpha
check "...with only the chosen provider's shortcut" test "$(shortcuts)" = dev-with-agents-alpha.md
pick CARD_PROVIDERS=beta --
check "CARD_PROVIDERS wins over the file" test "$(installed)" = beta
check "a provider no longer chosen is removed, shortcut too" test "$(shortcuts)" = dev-with-agents-beta.md
check "a command the installer did not write is left alone" test "$(cat "$h/.claude/commands/other.md")" = mine
pick CARD_PROVIDERS=beta -- alpha
check "names on the command line win over CARD_PROVIDERS" test "$(installed)" = alpha
# Each block below starts from a known state: conf "alpha", alpha installed. A failure stays in its block.
cp "$two/card-providers.conf" "$tmp/conf.orig"
reset() {
  chmod 644 "$two/card-providers.conf" 2> /dev/null || true
  cp "$tmp/conf.orig" "$two/card-providers.conf"; pick -- alpha
}

reset; pick -- beta jira; rc=$?
check "an unknown provider is refused" test "$rc" != 0
check "...with the list of the available ones" grep -q 'alpha beta' "$tmp/out.log"
check "...and nothing changes, before any file is touched" \
  bash -c "test \"\$1\" = alpha && test \"\$2\" = dev-with-agents-alpha.md" _ "$(installed)" "$(shortcuts)"

# A name is a plain word, each kept once.
reset; pick -- 'alpha beta'; rc=$?
check "a name with a space is refused" bash -c "test $rc != 0 && test \"\$1\" = alpha" _ "$(installed)"
reset; pick -- alpha alpha
check "a name given twice is installed once, one hint" \
  test "$(grep -c 'claude mcp add alpha' "$tmp/out.log")" = 1
reset; pick CARD_PROVIDERS=beta --; pick CARD_PROVIDERS=' ' --
check "a blank CARD_PROVIDERS counts as unset: the conf decides" test "$(installed)" = alpha

# The conf as an editor may save it, or cannot save it.
reset; printf 'beta\r\n' > "$two/card-providers.conf"; pick --; rc=$?
check "a conf with Windows line endings still works" bash -c "test $rc = 0 && test \"\$1\" = beta" _ "$(installed)"
reset; printf '\xef\xbb\xbfbeta\n' > "$two/card-providers.conf"; pick --; rc=$?
check "a conf with a byte order mark still works" bash -c "test $rc = 0 && test \"\$1\" = beta" _ "$(installed)"
if [ "$(id -u)" != 0 ]; then  # root reads a mode-000 file: the case cannot be built
  reset; chmod 000 "$two/card-providers.conf"; pick --; rc=$?
  check "an unreadable conf is an error, not 'nothing chosen'" \
    bash -c "test $rc != 0 && grep -q 'cannot read' '$tmp/out.log' && test \"\$1\" = alpha" _ "$(installed)"
  pick -- beta; rc=$?
  check "...but a run that does not use the conf is not blocked by it" \
    bash -c "test $rc = 0 && test \"\$1\" = beta" _ "$(installed)"
else
  echo "skip the unreadable-conf checks: running as root"
fi
reset; rm "$two/card-providers.conf"; mkdir "$two/card-providers.conf"; pick --; rc=$?
rmdir "$two/card-providers.conf"
check "a conf that is a directory is an error" \
  bash -c "test $rc != 0 && grep -q 'cannot read' '$tmp/out.log' && test \"\$1\" = alpha" _ "$(installed)"
reset; rm "$two/card-providers.conf"; ln -s "$tmp/nowhere" "$two/card-providers.conf"; pick --; rc=$?
rm "$two/card-providers.conf"
check "a conf that is a dangling link is an error, not 'no conf'" \
  bash -c "test $rc != 0 && grep -q 'cannot read' '$tmp/out.log' && test \"\$1\" = alpha" _ "$(installed)"
reset; pick CARD_PROVIDERS=$'beta\nalpha' --
check "CARD_PROVIDERS over several lines keeps every name" test "$(installed)" = "alpha beta"

# The menu takes numbers only, base 10, each once; a refusal names the input and has no bash noise in it.
for bad in x 0 3 '*' 08 18446744073709551617; do
  reset; menu "$bad"; rc=$?
  check "--choose refuses '$bad' cleanly" bash -c "test $rc != 0 \
    && grep -qF 'no provider number $bad.' '$tmp/out.log' && ! grep -q 'line [0-9]*:' '$tmp/out.log' \
    && test \"\$1\" = alpha" _ "$(installed)"
done
reset; menu '2 2'
check "--choose keeps a number given twice once" test "$(installed)" = beta
reset; printf '\n' > "$tmp/menu-empty"
MENU_INPUT="$tmp/menu-empty" pick -- --choose beta; rc=$?
check "--choose with a name is refused, not half-read" test "$rc" != 0
reset; menu 2
check "--choose shows a numbered menu" grep -q '2) beta' "$tmp/out.log"
check "--choose installs the providers picked by number" test "$(installed)" = beta
check "...and says which names to put in the conf to keep them" grep -q 'put "beta" in' "$tmp/out.log"
check "--choose shows the conf's choice as the Enter default" grep -q 'Enter = keep: alpha' "$tmp/out.log"
reset; pick -- beta; menu ''
check "--choose with Enter keeps card-providers.conf's choice" test "$(installed)" = alpha
reset; printf '\n' > "$tmp/menu-empty"; MENU_INPUT="$tmp/menu-empty" pick CARD_PROVIDERS=beta -- --choose
check "--choose ignores CARD_PROVIDERS: Enter keeps the conf" test "$(installed)" = alpha
reset; menu 1
check "--choose of the conf's own choice has nothing to keep" bash -c "! grep -q 'put \"' '$tmp/out.log'"
reset; printf 'alpha\nbeta\nalpha\n' > "$two/card-providers.conf"; menu '2 1'
check "--choose compares the set, not the order or repeats" bash -c "! grep -q 'put \"' '$tmp/out.log'"
check "...and the Enter default lists each name once" grep -q 'Enter = keep: alpha beta)' "$tmp/out.log"
reset; rm "$two/card-providers.conf"; menu 1
check "--choose without a conf says Enter means none" grep -q 'Enter = none' "$tmp/out.log"
reset; rm "$two/card-providers.conf"; pick --; rc=$?
check "no card-providers.conf: not an error" test "$rc" = 0
check "...nothing chosen, so nothing installed, and it says so" \
  bash -c "test -z \"\$(cd '$h/.claude/card-providers' && ls)\" && grep -q 'card-providers.conf' '$tmp/out.log'"

# --check: the install self-check. It resolves the choice exactly as an install does.
reset; pick -- --check; rc=$?
check "--check passes when the chosen providers are installed" test "$rc" = 0
pick CARD_PROVIDERS=beta --; pick CARD_PROVIDERS=beta -- --check; rc=$?
check "--check follows CARD_PROVIDERS, as the install does" test "$rc" = 0
pick -- --check; rc=$?
check "--check fails when a chosen provider is missing, and names it" \
  bash -c "test $rc != 0 && grep -q 'alpha' '$tmp/out.log'"
check "--check installs and removes nothing" test "$(installed)" = beta
rm "$two/card-providers.conf"; pick -- --check
check "--check does not repeat the install's 'nothing chosen' line" \
  bash -c "! grep -q 'No card provider' '$tmp/out.log'"
reset; pick -- alpha --check; rc=$?
check "a mode after a name is refused as a misplaced option" \
  bash -c "test $rc != 0 && grep -q 'must come first' '$tmp/out.log'"
reset; pick -- --check beta; rc=$?
check "--check takes no provider name" test "$rc" != 0
check "the install self-check is --check" \
  grep -qF 'install-card-providers.sh" "$HERE" --check' "$here/install-agentic.sh"

# No provider file at all: any request for one is an error; a plain run with nothing asked is not.
run_empty() { HOME="$tmp/home3" PATH="$tmp/bin:$PATH" "$@" bash "$here/install-card-providers.sh" "$tmp/empty" \
  > "$tmp/out.log" 2>&1; }
for how in "env CARD_PROVIDERS=jira" "env -- jira" "conf"; do
  if [ "$how" = conf ]; then
    echo jira > "$tmp/empty/card-providers.conf"; run_empty env; rc=$?; rm "$tmp/empty/card-providers.conf"
  elif [ "$how" = "env -- jira" ]; then
    HOME="$tmp/home3" bash "$here/install-card-providers.sh" "$tmp/empty" jira > "$tmp/out.log" 2>&1; rc=$?
  else
    run_empty env CARD_PROVIDERS=jira; rc=$?
  fi
  check "a provider asked for in an empty tree is refused ($how)" \
    bash -c "test $rc != 0 && grep -q 'no card provider in' '$tmp/out.log'"
done
bash "$here/install-card-providers.sh" > "$tmp/out.log" 2>&1; rc=$?
check "no argument: a usage line and exit 2, not a bash error" \
  bash -c "test $rc = 2 && head -1 '$tmp/out.log' | grep -q '^usage: install-card-providers.sh'"

exit $fail
