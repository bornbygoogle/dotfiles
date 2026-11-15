#!/usr/bin/env bash
# Runnable check for claude-container-settings.sh, on a throwaway $HOME and throwaway git repos: no network, no model.
set -u
here=$(cd "$(dirname "$0")" && pwd)
fail=0
check() {  # $1 = label, then the test command
  local label=$1; shift
  if "$@" > /dev/null; then echo "ok   $label"; else echo "FAIL $label"; fail=1; fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL="$tmp/gitconfig" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t \
  GIT_COMMITTER_EMAIL=t@t
mkdir -p "$tmp/home/.claude" "$tmp/ws"
settings="$tmp/home/.claude/settings.json"
list="$here/claude/container-allow.json"
# What earlier install steps left: the rtk hook and the commit lock.
echo '{"hooks":{"x":1},"permissions":{"ask":["Bash(*git commit*)"]}}' > "$settings"

# A team repo whose shared settings disable auto mode, like gmao-referential.
team() {  # team <dir> [disable]: a repo with .claude/settings.json committed
  mkdir -p "$1/.claude"
  git -C "$1" init -q
  if [ "${2:-}" = disable ]; then
    echo '{"permissions":{"defaultMode":"default","disableAutoMode":"disable","deny":["Read(.env)"]}}' \
      > "$1/.claude/settings.json"
  else
    echo '{"permissions":{"defaultMode":"default"}}' > "$1/.claude/settings.json"
  fi
  echo '.claude/settings.local.json' > "$1/.gitignore"
  git -C "$1" add -A && git -C "$1" commit -qm team
}
team "$tmp/ws/strict" disable
team "$tmp/ws/open"
run() { HOME="$tmp/home" bash "$here/claude-container-settings.sh" "$tmp/ws" > "$tmp/out.log" 2>&1; }

check "the allow list is valid JSON, an array of strings" jq -e 'type == "array" and all(type == "string")' "$list"
check "it holds the 74 rules of my computer" jq -e 'index("Bash(nmap:*)") and index("Bash(lsof:*)")' "$list"
check "it holds the dev rules, plain and rewritten by rtk" \
  jq -e 'index("Bash(git status*)") and index("Bash(rtk git status*)") and index("Bash(dotnet test*)")' "$list"
# Rewrites measured in the container (2026-11-15): cat/head/tail -> `rtk read`, curl -> `rtk curl`, ls -> `rtk ls`.
check "cat, head and tail are allowed as the hook rewrites them (rtk read)" jq -e 'index("Bash(rtk read *)")' "$list"
check "no rtk form the hook never produces" bash -c "! jq -r '.[]' '$list' | grep -qE '^Bash\\(rtk (cat|head|tail)'"
check "each rule of my computer is also allowed in its rtk form" \
  jq -e '. as $all | [.[] | select(test("^Bash\\([a-z0-9-]+:\\*\\)$"))]
    | length > 0 and all(.[]; sub("^Bash\\("; "Bash(rtk ") as $t | $all | index($t) != null)' "$list"
check "it allows no blanket rtk, no rm, no find, no sed -i, no python, no env" \
  bash -c "! jq -r '.[]' '$list' \
    | grep -qE '^Bash\((rtk \*|rtk proxy|(rtk )?(rm|find|python3?|env)( |:|\*|\))|(rtk )?sed( \*|\*| -i))'"

check "the script runs" run
run  # second run: nothing may be added twice
check "Claude starts in auto mode" test "$(jq -r '.permissions.defaultMode' "$settings")" = auto
check "every rule of the list is allowed, once" \
  test "$(jq --slurpfile l "$list" '[.permissions.allow[] | select(. as $r | $l[0] | index($r))] | length' \
    "$settings")" = "$(jq 'unique | length' "$list")"
check "the commit lock is kept (ask beats allow)" jq -e '.permissions.ask | index("Bash(*git commit*)")' "$settings"
check "the earlier settings are kept" jq -e '.hooks.x == 1' "$settings"

f="$tmp/ws/strict/.claude/settings.json"
check "a repo that disables auto mode no longer does, here" jq -e '.permissions | has("disableAutoMode") | not' "$f"
check "...the rest of its settings is kept" jq -e '.permissions.deny == ["Read(.env)"]' "$f"
check "...auto mode is its default, in the git-ignored local file" \
  test "$(jq -r '.permissions.defaultMode' "$tmp/ws/strict/.claude/settings.local.json")" = auto
check "...git sees no change" test -z "$(git -C "$tmp/ws/strict" status --porcelain)"
git -C "$tmp/ws/strict" add -A && git -C "$tmp/ws/strict" commit -qam work --allow-empty
check "...and a commit never takes it" \
  bash -c "! git -C '$tmp/ws/strict' show --name-only --format= HEAD | grep -q 'settings.json'"
check "...the committed file still disables auto mode" \
  bash -c "git -C '$tmp/ws/strict' show HEAD:.claude/settings.json \
    | jq -e '.permissions.disableAutoMode == \"disable\"'"
check "a repo that does not disable auto mode is left alone" \
  bash -c "test -z \"\$(git -C '$tmp/ws/open' status --porcelain)\" \
    && ! git -C '$tmp/ws/open' ls-files -v | grep -q '^S '"

# The team changes its settings: --restore gives back the team file, so a pull goes through; a run re-applies.
git clone -q "$tmp/ws/strict" "$tmp/upstream"
jq '.permissions.deny += ["Read(secrets/**)"]' "$tmp/upstream/.claude/settings.json" > "$tmp/s" \
  && mv "$tmp/s" "$tmp/upstream/.claude/settings.json" && git -C "$tmp/upstream" commit -qam "team change"
git -C "$tmp/ws/strict" remote add origin "$tmp/upstream" 2> /dev/null
HOME="$tmp/home" bash "$here/claude-container-settings.sh" --restore "$tmp/ws" > "$tmp/out.log" 2>&1
check "--restore gives back the team file" \
  bash -c "git -C '$tmp/ws/strict' diff --quiet && ! git -C '$tmp/ws/strict' ls-files -v | grep -q '^S '"
check "...so a pull of a team change goes through" git -C "$tmp/ws/strict" pull -q --no-rebase origin HEAD
run
check "...and a run re-applies on the new file" \
  jq -e '(.permissions | has("disableAutoMode") | not) and (.permissions.deny | index("Read(secrets/**)"))' "$f"

# A repo that does not ignore settings.local.json gets it excluded locally, never through its .gitignore.
team "$tmp/ws/noignore" disable
git -C "$tmp/ws/noignore" rm -q --cached .gitignore && rm "$tmp/ws/noignore/.gitignore" \
  && git -C "$tmp/ws/noignore" commit -qm "no ignore"
run
check "a repo that does not ignore the local file: git still sees nothing" \
  test -z "$(git -C "$tmp/ws/noignore" status --porcelain)"

# The repo as found today: someone already removed disableAutoMode by hand, uncommitted. It must be hidden too,
# decided from the committed file, and the local edit kept, not thrown away.
team "$tmp/ws/handedit" disable
jq 'del(.permissions.disableAutoMode) | .permissions.defaultMode = "auto"' "$tmp/ws/handedit/.claude/settings.json" \
  > "$tmp/s" && mv "$tmp/s" "$tmp/ws/handedit/.claude/settings.json"
run
check "a hand edit that already removed the line: git sees nothing either" \
  test -z "$(git -C "$tmp/ws/handedit" status --porcelain)"
check "...and the hand edit is kept" \
  jq -e '.permissions.defaultMode == "auto"' "$tmp/ws/handedit/.claude/settings.json"

echo 'not json' > "$settings"
run; rc=$?
check "a broken settings file makes the script fail" test "$rc" != 0
check "install-agentic.sh runs it" grep -q 'claude-container-settings.sh' "$here/install-agentic.sh"

exit $fail
