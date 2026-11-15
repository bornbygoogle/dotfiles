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
# No git setting of this machine may answer for the script: global, system and XDG ignore files all count.
mkdir -p "$tmp/xdg"
export GIT_CONFIG_GLOBAL="$tmp/gitconfig" GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$tmp/xdg" \
  GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$tmp/home/.claude" "$tmp/ws"
settings="$tmp/home/.claude/settings.json"
list="$here/claude/container-allow.json"
# What earlier install steps left: the rtk hook, the commit lock, and allow rules of my own, in my order.
echo '{"hooks":{"x":1},"permissions":{"ask":["Bash(*git commit*)"],"allow":["Bash(zzz)","Bash(aaa)"]}}' \
  > "$settings"

team() {  # team <dir> <committed settings.json> [ignore]: a repo with its team settings committed
  mkdir -p "$1/.claude"
  git -C "$1" init -q
  echo "$2" > "$1/.claude/settings.json"
  [ "${3:-ignore}" != ignore ] || echo '.claude/settings.local.json' > "$1/.gitignore"
  git -C "$1" add -A && git -C "$1" commit -qm team
}
team "$tmp/ws/strict" '{"permissions":{"defaultMode":"default","disableAutoMode":"disable","deny":["Read(.env)"]}}'
team "$tmp/ws/default" '{"permissions":{"defaultMode":"default"}}'
team "$tmp/ws/open" '{"permissions":{"deny":["Read(.env)"]}}'
team "$tmp/ws/teamauto" '{"permissions":{"defaultMode":"auto"}}'
run() { HOME="$tmp/home" bash "$here/claude-container-settings.sh" "$@" "$tmp/ws" > "$tmp/out.log" 2>&1; }

# The list. Allow rules skip the auto-mode review, so none may write files or run code through an option.
check "the allow list is valid JSON, an array of strings" jq -e 'type == "array" and all(type == "string")' "$list"
check "it holds rules of my computer (sampled: nmap, lsof, curl)" \
  jq -e 'index("Bash(nmap:*)") and index("Bash(lsof:*)") and index("Bash(curl:*)")' "$list"
check "it holds the dev rules, plain and rewritten by rtk" \
  jq -e 'index("Bash(git status)") and index("Bash(rtk git status *)") and index("Bash(dotnet test)")' "$list"
# Rewrites measured in the container (2026-11-15): cat/head/tail -> `rtk read`, curl -> `rtk curl`, ls -> `rtk ls`.
check "cat, head and tail are allowed as the hook rewrites them (rtk read)" jq -e 'index("Bash(rtk read *)")' "$list"
check "no rtk cat/head/tail form: the hook never produces one" \
  bash -c "! jq -r '.[]' '$list' | grep -qE '^Bash\\(rtk (cat|head|tail)'"
check "each rule of my computer is also allowed in its rtk form" \
  jq -e '. as $all | [.[] | select(test("^Bash\\([a-z0-9-]+:\\*\\)$"))]
    | length > 0 and all(.[]; sub("^Bash\\("; "Bash(rtk ") as $t | $all | index($t) != null)' "$list"
forbidden='^Bash\((rtk \*|rtk proxy|(rtk )?(rm|find|python3?|env|sed|rg)( |:|\*|\))|(rtk )?(sort|uniq|tree) |'
forbidden+='(rtk )?git (-C \*|fetch|branch -v)|(rtk )?dotnet format\*)|ctx_execute'
check "no rule that deletes, edits or runs code through an option (rm, find, sed, rg, sort/uniq/tree args, ...)" \
  bash -c "! jq -r '.[]' '$list' | grep -qE '$forbidden'"
# A `*` with no space before it also matches a longer command: `git diff*` matches `git difftool -x <cmd>` (docs:
# "Bash(ls*) matches lsof"). Every dev git rule is exact or `<cmd> *`.
check "no dev git rule without a space before its *" \
  bash -c "! jq -r '.[]' '$list' | grep -qE '^Bash\\((rtk )?git [a-z-]+[a-z]\\*\\)'"
check "no git grep (its -O runs a command; grep is allowed)" bash -c "! jq -r '.[]' '$list' | grep -q 'git grep'"
check "no git branch with arguments but --list" \
  bash -c "! jq -r '.[]' '$list' | grep -E '^Bash\\((rtk )?git branch ' \
    | grep -qvE 'git branch (--list( \\*)?|--show-current|-a)\\)$'"
check "no kernel rule that starts with *: it would match any command holding the text" \
  bash -c "! jq -r '.[]' '$list' | grep -q 'agentics/agentics'"
# MSBuild options cannot be blocked one spelling at a time (-p: /p: -property: --property: -P: @rsp ...): dotnet is
# allowed only bare; anything with options goes to the auto-mode classifier.
check "dotnet is allowed only bare: build, test, restore, format --verify-no-changes" \
  test "$(jq -r '.[] | select(test("dotnet"))' "$list" | sort | tr '\n' ' ')" \
    = "$(printf '%s ' 'Bash(dotnet build)' 'Bash(dotnet format --verify-no-changes)' 'Bash(dotnet restore)' \
      'Bash(dotnet test)' 'Bash(rtk dotnet build)' 'Bash(rtk dotnet format --verify-no-changes)' \
      'Bash(rtk dotnet restore)' 'Bash(rtk dotnet test)')"
check "no difftool or mergetool (they run a tool)" bash -c "! jq -r '.[]' '$list' | grep -qE 'difftool|mergetool'"
# Every dev rule has its rtk twin (the hook rewrites before matching), but cd and cat/head/tail (-> rtk read);
# my computer's rules are `X:*`, `impacket-*` and `*2john *`.
check "every dev rule has its rtk form" \
  jq -e '. as $all | [.[] | select(startswith("Bash(") and (startswith("Bash(rtk ") | not)
      and (test(":\\*\\)$") | not) and (test("^Bash\\((cd|cat|head|tail)( |\\))") | not)
      and (test("^Bash\\(/") | not) and (test("^Bash\\(([a-z0-9]+2john \\*|impacket-\\*)\\)$") | not))]
    | all(.[]; sub("^Bash\\("; "Bash(rtk ") as $t | $all | index($t) != null)' "$list"
check "no dev rule repeats one of my computer (file, ps, pgrep, lsof, ss)" \
  bash -c "! jq -r '.[]' '$list' | grep -qE '^Bash\\((rtk )?(file|ps|pgrep|lsof|ss)( \\*)?\\)$'"
check "cd is allowed, so a 'cd dir; cat file' chain does not ask" jq -e 'index("Bash(cd *)")' "$list"

check "the script runs" run
run  # second run: nothing may be added twice
check "Claude starts in auto mode" test "$(jq -r '.permissions.defaultMode' "$settings")" = auto
check "every rule of the list is allowed, once" \
  test "$(jq --slurpfile l "$list" '[.permissions.allow[] | select(. as $r | $l[0] | index($r))] | length' \
    "$settings")" = "$(jq 'unique | length' "$list")"
check "my own allow rules keep their place and order" \
  test "$(jq -c '.permissions.allow[0:2]' "$settings")" = '["Bash(zzz)","Bash(aaa)"]'
for d in agentics agentics-reports secondbrain .claude/card-providers .claude/commands; do
  check "~/$d is a working directory, once" \
    test "$(jq --arg d "$tmp/home/$d" '[.permissions.additionalDirectories[] | select(. == $d)] | length' \
      "$settings")" = 1
done
for v in run check init list; do
  check "the kernel's $v is allowed, anchored on its path" \
    jq -e --arg r "Bash($tmp/home/agentics/agentics $v *)" '.permissions.allow | index($r)' "$settings"
done
check "...but not done, which commits (the ask rule stays alone)" \
  bash -c "! jq -r '.permissions.allow[]' '$settings' | grep -q 'agentics done'"
for r in 'Bash(*git -c *)' 'Bash(*git -C * -c *)' 'Bash(*--output *)' 'Bash(*--output=*)' 'Bash(*--upload-pack*)' \
  'Bash(*--receive-pack*)' 'Bash(*--ext-diff*)' 'Bash(*git clean*)' 'Bash(*git -C * clean*)' 'Bash(*git reset*)' \
  'Bash(*git -C * reset*)'; do
  check "an option that writes or runs code asks: $r" jq -e --arg r "$r" '.permissions.ask | index($r)' "$settings"
done
check "no ask rule that catches read-only options (git log -c, git grep reset, --output-format)" \
  bash -c "! jq -r '.permissions.ask[]' '$settings' \
    | grep -qxE 'Bash\\(\\*git \\* (-c|reset|clean) ?\\*\\)|Bash\\(\\*--output\\*\\)'"
jq '.permissions.ask += ["Bash(*git * -c *)", "Bash(*--output*)", "Bash(*git * clean*)", "Bash(*git * reset*)",
  "Bash(*dotnet * -p:*)", "Bash(*dotnet * --report*)"]' "$settings" > "$tmp/s" && mv "$tmp/s" "$settings"
run
check "the ask rules of older versions are taken back (broad git ones, dotnet ones)" \
  bash -c "! jq -r '.permissions.ask[]' '$settings' \
    | grep -qxE 'Bash\\(\\*git \\* (-c|reset|clean) ?\\*\\)|Bash\\(\\*--output\\*\\)|Bash\\(\\*dotnet .*'"
check "the commit lock is kept first (ask beats allow)" \
  test "$(jq -r '.permissions.ask[0]' "$settings")" = 'Bash(*git commit*)'
check "the earlier settings are kept" jq -e '.hooks.x == 1' "$settings"

f="$tmp/ws/strict/.claude/settings.json"
check "a repo that disables auto mode no longer does, here" jq -e '.permissions | has("disableAutoMode") | not' "$f"
check "...the rest of its settings is kept" jq -e '.permissions.deny == ["Read(.env)"]' "$f"
said='strict: auto mode here, in the git-ignored .claude/settings.local.json (and git ignores the change'
said+=' to .claude/settings.json; --restore gives it back).'
check "...and the run says so in one clean sentence" grep -qF "$said" "$tmp/out.log"
check "...auto mode is its default, in the git-ignored local file" \
  test "$(jq -r '.permissions.defaultMode' "$tmp/ws/strict/.claude/settings.local.json")" = auto
check "...git sees no change" test -z "$(git -C "$tmp/ws/strict" status --porcelain)"
git -C "$tmp/ws/strict" add -A && git -C "$tmp/ws/strict" commit -qam work --allow-empty
check "...and a commit never takes it" \
  bash -c "! git -C '$tmp/ws/strict' show --name-only --format= HEAD | grep -q 'settings'"
check "...the committed file still disables auto mode" \
  bash -c "git -C '$tmp/ws/strict' show HEAD:.claude/settings.json \
    | jq -e '.permissions.disableAutoMode == \"disable\"'"
# A team defaultMode other than auto beats my user-level auto (measured): the local file must win it back.
check "a repo whose team default is another mode gets auto in its local file" \
  test "$(jq -r '.permissions.defaultMode' "$tmp/ws/default/.claude/settings.local.json")" = auto
check "...its team file untouched, git sees nothing" \
  bash -c "test -z \"\$(git -C '$tmp/ws/default' status --porcelain)\" \
    && ! git -C '$tmp/ws/default' ls-files -v | grep -q '^S '"
check "a repo whose team already says auto is left alone (no local file)" \
  test ! -e "$tmp/ws/teamauto/.claude/settings.local.json"
check "a repo that sets no mode and allows auto is left alone" \
  bash -c "test ! -e '$tmp/ws/open/.claude/settings.local.json' \
    && test -z \"\$(git -C '$tmp/ws/open' status --porcelain)\""

# The team changes its settings: --restore gives back the team file, so a pull goes through; a run re-applies.
git clone -q "$tmp/ws/strict" "$tmp/upstream"
jq '.permissions.deny += ["Read(secrets/**)"]' "$tmp/upstream/.claude/settings.json" > "$tmp/s" \
  && mv "$tmp/s" "$tmp/upstream/.claude/settings.json" && git -C "$tmp/upstream" commit -qam "team change"
git -C "$tmp/ws/strict" remote add origin "$tmp/upstream" 2> /dev/null
run --restore
check "--restore gives back the team file" \
  bash -c "git -C '$tmp/ws/strict' diff --quiet && ! git -C '$tmp/ws/strict' ls-files -v | grep -q '^S '"
check "...and says local edits to it are discarded" grep -q 'local edits to it discarded' "$tmp/out.log"
check "...so a pull of a team change goes through" git -C "$tmp/ws/strict" pull -q --no-rebase origin HEAD
check "...and does not also claim there was nothing to restore" \
  bash -c "! grep -q 'Nothing to restore' '$tmp/out.log'"
run --restore
check "--restore with nothing hidden says so" grep -q 'Nothing to restore' "$tmp/out.log"
run
check "...and a run re-applies on the new file" \
  jq -e '(.permissions | has("disableAutoMode") | not) and (.permissions.deny | index("Read(secrets/**)"))' "$f"

# A repo that does not ignore settings.local.json gets it excluded locally, once, never through its .gitignore.
team "$tmp/ws/noignore" '{"permissions":{"disableAutoMode":"disable"}}' no-ignore
run; run
check "a repo that does not ignore the local file: git still sees nothing" \
  test -z "$(git -C "$tmp/ws/noignore" status --porcelain)"
check "...excluded once, however many runs" \
  test "$(grep -cxF '.claude/settings.local.json' "$tmp/ws/noignore/.git/info/exclude")" = 1
# The team tracks its own settings.local.json: never rewritten, never made committable.
team "$tmp/ws/tracked" '{"permissions":{"defaultMode":"default","disableAutoMode":"disable"}}' no-ignore
echo '{"permissions":{"defaultMode":"plan"}}' > "$tmp/ws/tracked/.claude/settings.local.json"
git -C "$tmp/ws/tracked" add -A && git -C "$tmp/ws/tracked" commit -qm "team local"
run
check "...and its team settings.json is neither stripped nor hidden" \
  bash -c "! git -C '$tmp/ws/tracked' ls-files -v | grep -q '^S ' \
    && jq -e '.permissions.disableAutoMode' '$tmp/ws/tracked/.claude/settings.json'"
team "$tmp/ws/trackedauto" '{"permissions":{"defaultMode":"default"}}' no-ignore
echo '{"permissions":{"defaultMode":"auto"}}' > "$tmp/ws/trackedauto/.claude/settings.local.json"
git -C "$tmp/ws/trackedauto" add -A && git -C "$tmp/ws/trackedauto" commit -qm "team local auto"
run
check "a tracked settings.local.json that already says auto is reported as such" \
  grep -q 'trackedauto.*already says auto' "$tmp/out.log"
run
check "a tracked settings.local.json is left alone, and said so" \
  bash -c "test -z \"\$(git -C '$tmp/ws/tracked' status --porcelain)\" \
    && grep -q 'tracks .claude/settings.local.json' '$tmp/out.log'"
# The repo as found today: someone already removed disableAutoMode by hand, uncommitted. It must be hidden too,
# decided from the committed file, and the local edit kept, not thrown away.
team "$tmp/ws/handedit" '{"permissions":{"defaultMode":"default","disableAutoMode":"disable"}}'
jq 'del(.permissions.disableAutoMode) | .permissions.defaultMode = "auto"' "$tmp/ws/handedit/.claude/settings.json" \
  > "$tmp/s" && mv "$tmp/s" "$tmp/ws/handedit/.claude/settings.json"
run
check "a hand edit that already removed the line: git sees nothing either" \
  test -z "$(git -C "$tmp/ws/handedit" status --porcelain)"
check "...and the hand edit is kept" \
  jq -e '.permissions.defaultMode == "auto"' "$tmp/ws/handedit/.claude/settings.json"
# One broken repo must not stop the others, nor the user settings, nor leave a file behind.
team "$tmp/ws/aaa-broken" '{"permissions":{"disableAutoMode":"disable"}}'
echo 'not json' > "$tmp/ws/aaa-broken/.claude/settings.json"
jq '.permissions.allow = ["Bash(zzz)","Bash(aaa)"]' "$settings" > "$tmp/s" && mv "$tmp/s" "$settings"
run; rc=$?
check "a repo whose settings file is broken is skipped, not fatal" \
  bash -c "test $rc = 0 && grep -q 'aaa-broken.*not a valid settings file, skipped' '$tmp/out.log'"
check "...it leaves no temporary file" test ! -e "$tmp/ws/aaa-broken/.claude/settings.json.tmp"
check "...and the user settings were still written" jq -e '.permissions.allow | length > 2' "$settings"
rm -rf "$tmp/ws/aaa-broken"
team "$tmp/ws/aab-badlocal" '{"permissions":{"defaultMode":"default"}}'
echo 'not json' > "$tmp/ws/aab-badlocal/.claude/settings.local.json"
team "$tmp/ws/aac-badcommit" 'not json'
team "$tmp/ws/aad-disable-badlocal" '{"permissions":{"defaultMode":"default","disableAutoMode":"disable"}}'
echo 'not json' > "$tmp/ws/aad-disable-badlocal/.claude/settings.local.json"
run; rc=$?
check "a broken settings.local.json is skipped, and leaves no temporary file" \
  bash -c "test $rc = 0 && grep -q 'aab-badlocal.*skipped' '$tmp/out.log' \
    && test ! -e '$tmp/ws/aab-badlocal/.claude/settings.local.json.tmp'"
check "a committed team file that is not a settings file is skipped" grep -q 'aac-badcommit.*skipped' "$tmp/out.log"
check "a disabling repo with a broken local file: skipped, its team file neither stripped nor hidden" \
  bash -c "grep -q 'aad-disable-badlocal.*skipped' '$tmp/out.log' \
    && jq -e '.permissions.disableAutoMode' '$tmp/ws/aad-disable-badlocal/.claude/settings.json' \
    && ! git -C '$tmp/ws/aad-disable-badlocal' ls-files -v | grep -q '^S '"
rm -rf "$tmp/ws/aab-badlocal" "$tmp/ws/aac-badcommit" "$tmp/ws/aad-disable-badlocal"

# A rule taken out of the list (claude/container-allow.retired.json) is taken back from a container that got it from
# an older version; a rule I added myself never is.
retired="$here/claude/container-allow.retired.json"
check "the retired rules are valid JSON, none of them still in the list" \
  jq -e --slurpfile l "$list" 'type == "array" and length > 0 and all(.[]; . as $r | $l[0] | index($r) | not)' \
    "$retired"
jq '.permissions.allow += ["Bash(sed -n *)", "Bash(git -C * status*)", "Bash(mine-later *)"]' "$settings" > "$tmp/s" \
  && mv "$tmp/s" "$settings"
run
check "a retired rule is taken back (sed -n, git -C *)" \
  jq -e '.permissions.allow | (index("Bash(sed -n *)") or index("Bash(git -C * status*)")) | not' "$settings"
check "...but a rule I added myself stays" jq -e '.permissions.allow | index("Bash(mine-later *)")' "$settings"
check "...and so do my rules from before the first run" \
  jq -e '.permissions.allow | index("Bash(zzz)") and index("Bash(aaa)")' "$settings"

echo 'not json' > "$settings"
run; rc=$?
check "a broken settings file makes the script fail" test "$rc" != 0
check "...and leaves no temporary file" test ! -e "$settings.tmp"
check "install-agentic.sh runs it" grep -q 'claude-container-settings.sh' "$here/install-agentic.sh"

exit $fail
