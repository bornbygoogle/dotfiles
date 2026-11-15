#!/usr/bin/env bash
# Claude Code in the dev container: auto mode, and allow rules so everyday commands stop asking.
# Usage: claude-container-settings.sh [--restore] <workspaces dir>   Test: claude-container-settings.test.sh
# ~/.claude/settings.json gets defaultMode "auto" and every rule of claude/container-allow.json (my computer's
# rules, plus read-only dev commands in both forms: the rtk hook rewrites `ls` into `rtk ls` BEFORE the rules are
# matched). The ask rules of claude-ask-rules.sh still win over these (ask beats allow), so a commit still asks;
# so do a repo's deny rules.
# A team repo whose .claude/settings.json sets disableAutoMode keeps auto mode off whatever the user or a
# settings.local.json says (measured 2026-11-15, claude 2.1.325). So that one line is removed HERE ONLY, and git is
# told to ignore the change (skip-worktree): it never shows in `git status` and no commit can take it. Auto mode as
# the repo's default goes in its git-ignored .claude/settings.local.json.
# A team change to that file makes `git pull` stop: run with --restore, pull, then run again.
set -euo pipefail

restore=
[ "${1:-}" != --restore ] || { restore=1; shift; }
ws=${1:?usage: claude-container-settings.sh [--restore] <workspaces dir>}
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

shared=.claude/settings.json
for repo in "$ws"/*/; do
  repo=${repo%/}
  git -C "$repo" ls-files --error-unmatch "$shared" > /dev/null 2>&1 || continue
  if [ -n "$restore" ]; then
    if git -C "$repo" ls-files -v "$shared" | grep -q '^S '; then
      git -C "$repo" update-index --no-skip-worktree "$shared"
      git -C "$repo" checkout -- "$shared"  # local edits to it go too: that is what lets the pull through
      echo "$repo: team $shared restored (pull, then run without --restore)."
    fi
    continue
  fi
  # Decided on the COMMITTED file: a hand edit may already have removed the line from the working copy, and that
  # edit must be hidden from git too. The working copy is patched in place, so a hand edit is kept.
  git -C "$repo" show "HEAD:$shared" 2> /dev/null | jq -e '.permissions.disableAutoMode' > /dev/null 2>&1 || continue

  jq 'del(.permissions.disableAutoMode)' "$repo/$shared" > "$repo/$shared.tmp"
  mv "$repo/$shared.tmp" "$repo/$shared"
  git -C "$repo" update-index --skip-worktree "$shared"

  local_file="$repo/.claude/settings.local.json"
  [ -f "$local_file" ] || echo '{}' > "$local_file"
  jq '.permissions.defaultMode = "auto"' "$local_file" > "$local_file.tmp"
  mv "$local_file.tmp" "$local_file"
  # Never through the team's .gitignore: a repo that does not ignore the file gets it excluded locally.
  if ! git -C "$repo" check-ignore -q .claude/settings.local.json; then
    exclude="$(git -C "$repo" rev-parse --git-path info/exclude)"
    case $exclude in /*) ;; *) exclude="$repo/$exclude" ;; esac
    mkdir -p "$(dirname "$exclude")"
    printf '\n.claude/settings.local.json\n' >> "$exclude"
  fi
  echo "$repo: auto mode allowed here only (git ignores the change to $shared; --restore gives it back)."
done
[ -z "$restore" ] || exit 0

settings="$HOME/.claude/settings.json"
mkdir -p "$(dirname "$settings")"
[ -f "$settings" ] || echo '{}' > "$settings"
# Two lines, not `&&`: set -e ignores a failure on the left of `&&`, and a broken settings.json must stop the script.
jq --slurpfile list "$here/claude/container-allow.json" \
  '.permissions.defaultMode = "auto" | .permissions.allow = ((.permissions.allow // []) + $list[0] | unique)' \
  "$settings" > "$settings.tmp"
mv "$settings.tmp" "$settings"
