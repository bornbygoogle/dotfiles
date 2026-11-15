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
    [ "$(grep -E '^## (Connector|Id|Fetch|Mapping)$' "$f" | tr '\n' ' ')" = "## Connector ## Id ## Fetch ## Mapping " ] || return 1
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
check "the youtrack provider reads comments from get_issue_comments only" grep -q 'only from `get_issue_comments`' "$yt"
check "the youtrack provider never resurrects a deleted comment" bash -c "grep -q 'never use .*recentComments' '$yt' && ! grep -qi 'take the missing ones' '$yt'"
check "the shortcut expands to the full form" grep -q -- '--card-provider youtrack --card' "$short"
# /dev-with-agents-youtrack ERP-196 must not become ERP-ERP-196.
check "the shortcut keeps a full id as it is" grep -qi 'already.*-.*as it is' "$short"
# The repo is public: no tracker host name in any tracked file (this pattern names none).
check "no tracker host name in the dotfiles (public repo)" \
  bash -c "! git -C '$here' grep --untracked -qiIE 'https?://[a-z0-9-]+\\.(youtrack\\.cloud|myjetbrains\\.com)' -- . ':!.superpowers'"

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
check "a missing connector prints how to add it" grep -q 'claude mcp add --transport http --scope user youtrack' "$tmp/out.log"
echo stale > "$tmp/home/.claude/card-providers/youtrack.md"  # the copy before a `git pull` of the dotfiles
check "a second run, connector present, succeeds" install "$tmp/with-youtrack.txt"
check "a present connector prints no hint" bash -c "! grep -q 'claude mcp add' '$tmp/out.log'"
check "a second run replaces a stale copy with the dotfiles version" cmp -s "$yt" "$tmp/home/.claude/card-providers/youtrack.md"
check "install-agentic.sh calls the installer" grep -q 'install-card-providers.sh' "$here/install-agentic.sh"

# A dotfiles tree of our own: a provider whose Connector part has no `claude mcp add` line, and an empty tree.
mkdir -p "$tmp/df/claude/card-providers" "$tmp/df/claude/commands" "$tmp/empty/claude/card-providers" \
  "$tmp/empty/claude/commands" "$tmp/home2" "$tmp/home3"
printf '# Card provider: Jira\n\n## Connector\n\nThe MCP server named `jira`.\n' > "$tmp/df/claude/card-providers/jira.md"
echo '# jira shortcut' > "$tmp/df/claude/commands/dev-with-agents-jira.md"
install_from() {  # $1 = dotfiles dir, $2 = home
  HOME="$2" PATH="$tmp/bin:$PATH" FAKE_MCP_LIST="$tmp/no-youtrack.txt" \
    bash "$here/install-card-providers.sh" "$1" > "$tmp/out.log" 2>&1
}
check "a provider without an add command still installs, and says where to look" \
  bash -c "$(declare -f install_from); tmp='$tmp' here='$here' install_from '$tmp/df' '$tmp/home2' && grep -q 'Connector' '$tmp/out.log'"
check "no provider files at all is not an error" \
  bash -c "$(declare -f install_from); tmp='$tmp' here='$here' install_from '$tmp/empty' '$tmp/home3'"

exit $fail
