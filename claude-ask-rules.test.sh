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
mkdir -p "$tmp/home/.claude"
settings="$tmp/home/.claude/settings.json"
# Existing settings that must survive: the rtk hook written by an earlier step.
echo '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"~/.claude/hooks/rtk-hook"}]}]}}' \
  > "$settings"
run() { HOME="$tmp/home" bash "$here/claude-ask-rules.sh" > "$tmp/out.log" 2>&1; }

check "the script runs" run
run  # second run: nothing may be added twice

# Every git command that creates or publishes a commit, bare and with options before it (`git -C <dir> merge`),
# and a PR merged on GitHub. `agentics* done`: the kernel path quoted (`"$AGENTICS/agentics" done`) must ask too.
rules=('Bash(*agentics* done*)' 'Bash(*gh pr merge*)')
for sub in commit merge cherry-pick revert am rebase pull push; do
  rules+=("Bash(*git $sub*)" "Bash(*git * $sub*)")
done
for rule in "${rules[@]}"; do
  check "settings ask before $rule, once" \
    test "$(jq --arg r "$rule" '[.permissions.ask[] | select(. == $r)] | length' "$settings")" = 1
done
check "the earlier hook settings are kept" \
  test "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$settings")" = "~/.claude/hooks/rtk-hook"

# No settings file yet (fresh container): it is created with the ask rules.
rm "$settings"
run
check "a missing settings file is created with all the ask rules" \
  test "$(jq '.permissions.ask | length' "$settings")" = "${#rules[@]}"

# A broken settings file stops the script, on the settings error itself, with no ask rule written.
echo 'not json' > "$settings"
run; rc=$?
check "a broken settings file makes the script fail" test "$rc" != 0
check "...because of the settings file" grep -qi "parse error" "$tmp/out.log"

[ "$fail" = 0 ] || { echo "--- output of the last run:"; cat "$tmp/out.log"; }
exit $fail
