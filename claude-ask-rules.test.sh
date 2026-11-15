#!/usr/bin/env bash
# Runnable check for claude-ask-rules.sh, on a throwaway $HOME: no network, no model.
set -u
here=$(cd "$(dirname "$0")" && pwd)
fail=0
check() {  # $1 = label, then the test command
  local label=$1; shift
  if "$@"; then echo "ok   $label"; else echo "FAIL $label"; fail=1; fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
has() { jq -e "$@" > /dev/null; }  # a jq test whose output is not wanted; `check ... > /dev/null` hid the verdict
mkdir -p "$tmp/home/.claude"
settings="$tmp/home/.claude/settings.json"
# Existing settings that must survive: the rtk hook written by an earlier step, and a rule of my own.
echo '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"~/.claude/hooks/rtk-hook"}]}]},
  "permissions":{"ask":["Bash(*my own rule*)","Bash(*gh api*)","Bash(*gh pr merge*)"]}}' > "$settings"
run() { HOME="$tmp/home" bash "$here/claude-ask-rules.sh" > "$tmp/out.log" 2>&1; }

check "the script runs" run
first=$(jq -c '.permissions.ask' "$settings")
run  # second run: nothing may be added twice
check "no rule is written twice" \
  test "$(jq '.permissions.ask | length' "$settings")" = "$(jq '.permissions.ask | unique | length' "$settings")"
check "the earlier hook settings are kept" \
  test "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$settings")" = "~/.claude/hooks/rtk-hook"
check "a second run changes nothing" test "$(jq -c '.permissions.ask' "$settings")" = "$first"
check "rules of my own keep their place, first" \
  test "$(jq -c '.permissions.ask[:2]' "$settings")" = '["Bash(*my own rule*)","Bash(*gh api*)"]'
check "rules of my own are kept, a gh one included" \
  has '.permissions.ask | index("Bash(*my own rule*)") and index("Bash(*gh api*)")' "$settings"
check "the rule an earlier version wrote, and this one no longer does, is removed" \
  has '.permissions.ask | index("Bash(*gh pr merge*)") == null' "$settings"
check "reading gh's token file asks" has '.permissions.ask | index("Read(~/.config/gh/**)")' "$settings"

# What matters is which command lines ask, not which strings are written: each line is matched against the Bash
# rules the way this test assumes Claude Code matches them, `*` any text and every other character itself, on the
# whole line. Not as a bash glob: bash reads `*(gh *` as an extglob group. Assumed, not measured: Claude Code may
# split a compound line (`cd x; gh pr create`) before matching; then `gh *` still catches the gh part.
asks() {  # asks <command line>: true when a Bash ask rule matches it
  local rule pattern regex
  while IFS= read -r rule; do
    pattern=${rule#Bash(}; pattern=${pattern%)}
    regex=$(printf '%s' "$pattern" | sed -e 's/[]\/$.^|()+?{}[]/\\&/g' -e 's/\*/.*/g')
    [[ $1 =~ ^$regex$ ]] && return 0
  done < <(jq -r '.permissions.ask[] | select(startswith("Bash("))' "$settings")
  return 1
}
for line in \
  'git commit -m x' 'rtk git commit -m x' 'git -C /w commit -m x' \
  'git push origin main' 'git pull' 'git merge main' 'git rebase main' 'git cherry-pick abc' 'git revert abc' \
  'git am p.patch' 'printf host=github.com | git credential fill' \
  'gh pr create --draft' 'gh pr -R o/r merge 12' 'gh pr "merge" 12' '"gh" pr merge 12' "'gh' pr merge 12" \
  'rtk gh pr merge 12' '/usr/bin/gh pr list' 'echo $(gh auth token)' 'cd x; gh pr create' 'a|gh api x' \
  'cat ~/.config/gh/hosts.yml' 'echo `gh auth token`' 'x=`gh pr merge 12`' "cd x;$(printf '\t')gh auth token" \
  'cat ~/.config/gh/host*' 'grep -r oauth_token ~/.config' 'cd ~/.config/gh && cat hosts.yml' \
  '/usr/lib/git-core/git-credential-store get' 'git-credential-cache get' \
  'gh api -X PUT repos/o/r/pulls/1/merge' 'gh auth token' 'gh auth status -t' \
  'printf host=github.com | gh auth git-credential get' "gh alias set m 'pr merge'" 'gh extension install o/x' \
  'gh repo sync o/fork --force' 'gh pr update-branch 12' 'gh label delete bug' 'gh release create v1' \
  '"$AGENTICS/agentics" done run_1'; do
  check "asks before: $line" asks "$line"
done
not_asks() { ! asks "$1"; }
# What the rules are for: an agent's ordinary commands. Not a sandbox: an agent set on getting round them
# (`git c"ommit"`, `\\commit`, an alias, `git-commit`, `send-pack`) can, and the script says so.
for line in 'ls -la' 'dotnet test' 'git status' 'git diff' 'git log --oneline' 'npm ci' 'jq . f.json' \
  'git log --author "amy"' "git diff 'amount.cs'" 'echo through the high wall' 'agentics run --bugs "high load"' \
  'cat ~/.config/ghostty/config' 'ls ~/.config/gh-dash'; do
  check "does not ask before: $line" not_asks "$line"
done

# A card flow reads the tracker only: every YouTrack tool that writes asks first, even in auto mode.
for tool in add_issue_comment update_issue change_issue_assignee log_work manage_issue_tags link_issues \
  create_issue create_draft_issue create_article update_article; do
  check "asks before mcp__youtrack__$tool" has --arg r "mcp__youtrack__$tool" '.permissions.ask | index($r)' \
    "$settings"
done

# No settings file yet (fresh container): it is created with the ask rules.
all_rules=$(jq -c '.permissions.ask - ["Bash(*my own rule*)", "Bash(*gh api*)"]' "$settings")
rm "$settings"
run
check "a missing settings file is created with every ask rule" \
  test "$(jq -c '.permissions.ask' "$settings")" = "$all_rules"

# A broken settings file stops the script, on the settings error itself, with no ask rule written.
echo 'not json' > "$settings"
run; rc=$?
check "a broken settings file makes the script fail" test "$rc" != 0
check "...because of the settings file" grep -qi "parse error" "$tmp/out.log"
check "...leaving no temporary file beside it" test ! -e "$settings.tmp"
check "...and the file as it was" grep -qx 'not json' "$settings"

# A settings file kept private (it may hold tokens in env) stays private.
echo '{}' > "$settings"; chmod 600 "$settings"
run
check "the file keeps its permissions" test "$(stat -c %a "$settings")" = 600

# settings.json kept as a link into my dotfiles: the rules are written through the link, which stays a link.
echo '{}' > "$tmp/real-settings.json"
rm -f "$settings"; ln -s "$tmp/real-settings.json" "$settings"
run
check "a linked settings file stays a link" test -L "$settings"
check "...and gets the rules" has '.permissions.ask | length > 0' "$tmp/real-settings.json"
check "...leaving no temporary file beside the real one" test ! -e "$tmp/real-settings.json.tmp"

[ "$fail" = 0 ] || { echo "--- output of the last run:"; cat "$tmp/out.log"; }
exit $fail
