#!/usr/bin/env bash
# Runnable check for agentics-profiles.sh, on throwaway folders: no network, no model, no real kernel.
set -u
here=$(cd "$(dirname "$0")" && pwd)
fail=0
check() {  # $1 = label, then the test command
  local label=$1; shift
  if "$@"; then echo "ok   $label"; else echo "FAIL $label"; fail=1; fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A profile for "app" and "notes", none for "other". "notes" is a plain folder, not a repository of its own,
# though the workspaces folder above it is one: git answers "inside a work tree" for it all the same.
mkdir -p "$tmp/profiles" "$tmp/ws/notes" "$tmp/home/.claude"
printf 'name: app\n' > "$tmp/profiles/app.yaml"
printf 'name: notes\n' > "$tmp/profiles/notes.yaml"
for r in . app other; do git init -q "$tmp/ws/$r"; done
# The repo folder is shared with the host, which may have its own agentics.yaml with host paths.
printf 'name: app on the host\n' > "$tmp/ws/app/agentics.yaml"
# A kernel stand-in that records how it was called.
mkdir -p "$tmp/kernel"
printf '#!/bin/sh\necho "$@" >> "%s/kernel.log"\n' "$tmp" > "$tmp/kernel/agentics"
chmod +x "$tmp/kernel/agentics"
# Existing settings that must survive: the rtk hook written by an earlier step.
echo '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"~/.claude/hooks/rtk-hook"}]}]}}' \
  > "$tmp/home/.claude/settings.json"

run() {
  HOME="$tmp/home" AGENTICS_DIR="$tmp/kernel" AGENTICS_PROFILES="$tmp/profiles" \
    bash "$here/agentics-profiles.sh" "$tmp/ws" > "$tmp/out.log" 2>&1
}
settings="$tmp/home/.claude/settings.json"
profile_in_repo="$tmp/ws/app/agentics.container.yaml"

settings_before=$(cat "$settings")
check "the script runs" run
run  # second run: nothing may be added twice
check "the Claude settings are left alone (the commit lock is claude-ask-rules.sh)" test "$(cat "$settings")" = "$settings_before"

check "the profile is copied into the repo it names, under the container name" cmp -s "$tmp/profiles/app.yaml" "$profile_in_repo"
check "the host's own agentics.yaml is left untouched" test "$(cat "$tmp/ws/app/agentics.yaml")" = "name: app on the host"
check "a repo without a profile gets none" test ! -e "$tmp/ws/other/agentics.container.yaml"
check "a folder that is not a git repo is left alone" test -z "$(ls -A "$tmp/ws/notes")"
check "agentics.container.yaml is excluded once" test "$(grep -cx 'agentics.container.yaml' "$tmp/ws/app/.git/info/exclude")" = 1
# A profile made by hand in a repo with no dotfiles profile must not show up as untracked either.
check "a repo without a profile still excludes agentics.container.yaml, once" \
  test "$(grep -cx 'agentics.container.yaml' "$tmp/ws/other/.git/info/exclude" 2> /dev/null)" = 1
check ".agentics/ is excluded once" test "$(grep -cx '.agentics/' "$tmp/ws/app/.git/info/exclude")" = 1
# What a hand-made profile writes in the repo: the demos' rules folder, `agentics init`'s starter knowledge base and reports.
for p in .agentics/ .agentic/ agentic-reports/; do
  check "a repo without a profile excludes $p, once" \
    test "$(grep -cxF "$p" "$tmp/ws/other/.git/info/exclude" 2> /dev/null)" = 1
done
check "git lists no container file as untracked" test -z "$(git -C "$tmp/ws/app" status --porcelain -- agentics.container.yaml .agentics)"
check "the kernel ran init on the container profile" grep -qx "init --project $profile_in_repo" "$tmp/kernel.log"
check "the kernel ran check on the container profile" grep -qx "check --project $profile_in_repo" "$tmp/kernel.log"
check "the kernel never ran for the repo without a profile" bash -c "! grep -q '/other/' '$tmp/kernel.log'"

# A local edit to the profile in the repo is never overwritten.
echo "# my local edit" >> "$profile_in_repo"
run
check "a profile already in the repo is not overwritten" grep -q "my local edit" "$profile_in_repo"
check "a repo copy that differs from the dotfiles profile is reported" \
  grep -q "differs from $tmp/profiles/app.yaml" "$tmp/out.log"

# An exclude file whose last line has no newline: the appended patterns still get lines of their own.
printf '*.log' > "$tmp/ws/app/.git/info/exclude"
run
check "a last exclude line without newline is kept apart" grep -qx '\*\.log' "$tmp/ws/app/.git/info/exclude"
check "the profile is excluded after such a line" grep -qx 'agentics.container.yaml' "$tmp/ws/app/.git/info/exclude"

# Container paths: /home/vscode in a profile becomes this container's $HOME when it is copied.
printf 'name: homed\nknowledge_base: /home/vscode/secondbrain\n' > "$tmp/profiles/homed.yaml"
git init -q "$tmp/ws/homed"
# A repo git cannot read (a host worktree whose .git points to a host path) is skipped with a warning,
# and the repos after it are still set up. "broken" comes before "homed" in both loops.
mkdir -p "$tmp/ws/broken" && echo "gitdir: /nowhere" > "$tmp/ws/broken/.git"
printf 'name: broken\n' > "$tmp/profiles/broken.yaml"
run; rc=$?
check "a repo git cannot read does not stop the script" test "$rc" = 0
check "a repo git cannot read is reported" grep -q "skipped $tmp/ws/broken" "$tmp/out.log"
check "the repo after it is still set up, with \$HOME in its paths" \
  grep -qx "knowledge_base: $tmp/home/secondbrain" "$tmp/ws/homed/agentics.container.yaml"
run
check "a substituted copy is not reported as a local edit" bash -c "! grep -q 'homed.*differs' '$tmp/out.log'"
rm -rf "$tmp/ws/broken" "$tmp/profiles/broken.yaml"

# A kernel that fails on one repo ("app", first in the loop): the repos after it are still set up,
# and the script still fails at the end, naming the repo.
mkdir -p "$tmp/badkernel"
printf '#!/bin/sh\necho "$@" >> "%s/badkernel.log"\ncase "$*" in */app/*) exit 1 ;; esac\n' "$tmp" > "$tmp/badkernel/agentics"
chmod +x "$tmp/badkernel/agentics"
HOME="$tmp/home" AGENTICS_DIR="$tmp/badkernel" AGENTICS_PROFILES="$tmp/profiles" \
  bash "$here/agentics-profiles.sh" "$tmp/ws" > "$tmp/bad.log" 2>&1; rc=$?
check "a kernel failure on one repo makes the script fail" test "$rc" != 0
check "a kernel failure on one repo does not stop the next" grep -qx "check --project $tmp/ws/homed/agentics.container.yaml" "$tmp/badkernel.log"
check "a kernel failure names its repo" grep -q "failed.*$tmp/ws/app" "$tmp/bad.log"

# The real profiles: the kernel runs test commands as argv and refuses shell operators
# (kernel.execute._FORBIDDEN_TOKENS: && || ; | > < ` $().
for profile in "$here"/agentics/profiles/*.yaml; do
  check "$(basename "$profile"): no shell operator in a test command" \
    bash -c "! grep -E '^\s*(authoritative|fast):' '$profile' | grep -qE '&&|[;|<>\`]|\\\$\('"
done

[ "$fail" = 0 ] || { echo "--- output of the last run:"; cat "$tmp/out.log"; }
exit $fail
