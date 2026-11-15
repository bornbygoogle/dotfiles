#!/usr/bin/env bash
# Claude Code in the dev container: auto mode, and allow rules so everyday commands stop asking.
# Usage: claude-container-settings.sh [--restore] <workspaces dir>   Test: claude-container-settings.test.sh
#
# ~/.claude/settings.json gets defaultMode "auto", the agentics folders as working directories (a team repo with
# blockReadsOutsideWorkingDirectories otherwise asks for every read of a run's log, a brief or a card provider),
# every rule of claude/container-allow.json, and the kernel's run/check/init/list anchored on its own path (a rule
# starting with `*` would match any one command that merely holds the text).
# The list: my computer's rules, kept as they are, knowingly (several of them write files or run code through
# their arguments: curl -o, unzip, msfvenom -o, ...), plus everyday dev commands in both forms (the rtk hook
# rewrites `ls` into `rtk ls` BEFORE the rules are matched). Allow rules skip the auto-mode review, so the dev
# rules are exact or `<cmd> *` (a `*` with no space before it also matches `git difftool`), and leave out what
# writes or runs code through an option (sed, rg, git grep -O, git fetch, git branch -v/-m, sort/uniq/tree with
# arguments). dotnet is allowed bare only: MSBuild takes -p: /p: -property: --property: -P: and @response files,
# so no list of spellings can hold; with options it goes to the classifier. The ask rules below catch the git
# options that write or run code (-c, --output, --upload-pack, clean, reset); they also ask on a harmless line
# that holds the text (`grep 'git reset' f`). Not caught: a quoted `"--output"`, `git --git-dir=x reset`, config
# already in a repo's .git (a diff driver, core.fsmonitor): no command-line rule can see those.
# Ask beats allow: the commit lock of claude-ask-rules.sh still asks. A repo's deny rules still block.
# claude/container-allow.retired.json and retired_asks below: rules an older version put here; they are taken back
# on every run, even one I added by hand that happens to be the same.
#
# Which defaultMode a session gets, measured 2026-11-15 (claude 2.1.325): a team .claude/settings.json with
# disableAutoMode keeps auto mode off whatever anything else says; a team defaultMode other than auto beats my
# user-level auto; a git-ignored .claude/settings.local.json with auto beats the team's defaultMode. So, per repo
# in <workspaces dir>, decided on the COMMITTED team file:
# - it disables auto mode: that line is removed in the working copy only (a hand edit is kept) and git is told to
#   ignore the change (skip-worktree): it never shows in `git status` and no commit can take it;
# - it disables auto mode or sets another defaultMode: settings.local.json gets defaultMode auto, git-ignored
#   (locally excluded when the repo does not ignore it; left alone when the team tracks that file).
# skip-worktree has a price: a pull, checkout, switch, rebase, merge or `reset --hard <ref>` that changes the team
# file stops ("commit your changes or stash them"; a stash does not save it). Run with --restore, do the git
# command, then run again. A worktree made after this ran gets the team file as committed.
set -euo pipefail

restore=
[ "${1:-}" != --restore ] || { restore=1; shift; }
ws=${1:?usage: claude-container-settings.sh [--restore] <workspaces dir>}
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

shared=.claude/settings.json
localf=.claude/settings.local.json
restored=0
for repo in "$ws"/*/; do
  repo=${repo%/}
  git -C "$repo" ls-files --error-unmatch "$shared" > /dev/null 2>&1 || continue
  if [ -n "$restore" ]; then
    if git -C "$repo" ls-files -v "$shared" | grep -q '^S '; then
      git -C "$repo" update-index --no-skip-worktree "$shared"
      git -C "$repo" checkout -- "$shared"
      echo "$repo: team $shared restored, local edits to it discarded (now pull, then run without --restore)."
      restored=$((restored + 1))
    fi
    continue
  fi

  committed=$(git -C "$repo" show "HEAD:$shared" 2> /dev/null) || continue
  mode=$(jq -r '.permissions.defaultMode // ""' <<< "$committed" 2> /dev/null) \
    || { echo "$repo: committed $shared is not a valid settings file, skipped." >&2; continue; }
  disables=
  jq -e '.permissions.disableAutoMode' <<< "$committed" > /dev/null 2>&1 && disables=1
  [ -n "$disables" ] || { [ -n "$mode" ] && [ "$mode" != auto ]; } || continue
  # Both checked before anything is touched: without the local file, hiding the team file would buy nothing.
  if git -C "$repo" ls-files --error-unmatch "$localf" > /dev/null 2>&1; then
    if [ "$(jq -r '.permissions.defaultMode // ""' "$repo/$localf" 2> /dev/null)" = auto ]; then
      echo "$repo: the team tracks $localf, which already says auto: left alone." >&2
    else
      echo "$repo: the team tracks $localf, left alone: auto mode stays off here." >&2
    fi
    continue
  fi
  if [ -f "$repo/$localf" ] && ! jq -e 'type == "object"' "$repo/$localf" > /dev/null 2>&1; then
    echo "$repo: $localf is not a valid settings file, skipped." >&2
    continue
  fi

  # One bad repo must not stop the install: skip it, leave nothing behind.
  if [ -n "$disables" ]; then
    if ! jq 'del(.permissions.disableAutoMode)' "$repo/$shared" > "$repo/$shared.tmp" 2> /dev/null; then
      rm -f "$repo/$shared.tmp"
      echo "$repo: $shared is not a valid settings file, skipped." >&2
      continue
    fi
    mv "$repo/$shared.tmp" "$repo/$shared"
    git -C "$repo" update-index --skip-worktree "$shared"
  fi
  [ -f "$repo/$localf" ] || echo '{}' > "$repo/$localf"
  if ! jq '.permissions.defaultMode = "auto"' "$repo/$localf" > "$repo/$localf.tmp" 2> /dev/null; then
    rm -f "$repo/$localf.tmp"
    echo "$repo: $localf is not a valid settings file, skipped." >&2
    continue
  fi
  mv "$repo/$localf.tmp" "$repo/$localf"
  # Never through the team's .gitignore: a repo that does not ignore the file gets it excluded locally (once: the
  # next run finds it ignored).
  if ! git -C "$repo" check-ignore -q "$localf"; then
    exclude=$(git -C "$repo" rev-parse --git-path info/exclude)
    case $exclude in /*) ;; *) exclude="$repo/$exclude" ;; esac
    mkdir -p "$(dirname "$exclude")"
    printf '\n%s\n' "$localf" >> "$exclude"
  fi
  hidden=
  [ -z "$disables" ] || hidden=" (and git ignores the change to $shared; --restore gives it back)"
  echo "$repo: auto mode here, in the git-ignored $localf$hidden."
done
if [ -n "$restore" ]; then
  [ "$restored" -gt 0 ] || echo "Nothing to restore: no team $shared is hidden from git in $ws."
  exit 0
fi

settings="$HOME/.claude/settings.json"
mkdir -p "$(dirname "$settings")"
[ -f "$settings" ] || echo '{}' > "$settings"
dirs=$(printf '%s\n' agentics agentics-reports secondbrain .claude/card-providers .claude/commands \
  | jq -R --arg h "$HOME" '$h + "/" + .' | jq -s .)
kernel=$(printf '%s\n' run check init list \
  | jq -R --arg h "$HOME" '"Bash(" + $h + "/agentics/agentics " + . + " *)"' | jq -s .)
# Narrow on purpose: `*git * -c *` would also ask for `git log -c`, `*--output*` for `--output-format`.
asks='["Bash(*git -c *)", "Bash(*git -C * -c *)", "Bash(*--output *)", "Bash(*--output=*)",
  "Bash(*--upload-pack*)", "Bash(*--receive-pack*)", "Bash(*--ext-diff*)", "Bash(*git clean*)",
  "Bash(*git -C * clean*)", "Bash(*git reset*)", "Bash(*git -C * reset*)"]'
# Ask rules of older versions, taken back: broad git ones asked on `git log -c` and `--output-format`; the dotnet
# ones could not hold (dotnet is now allowed bare only).
retired_asks='["Bash(*git * -c *)", "Bash(*--output*)", "Bash(*git * clean*)", "Bash(*git * reset*)",
  "Bash(*dotnet * -p:*)", "Bash(*dotnet * /p:*)", "Bash(*dotnet * -o *)", "Bash(*dotnet * -bl*)",
  "Bash(*dotnet * -flp*)", "Bash(*dotnet * --source*)", "Bash(*dotnet * --configfile*)",
  "Bash(*dotnet * --report*)"]'
# Existing entries keep their order; new ones go after them. Two lines, not `&&`: set -e ignores a failure on the
# left of `&&`, and a broken settings.json must stop the script.
jq --slurpfile list "$here/claude/container-allow.json" \
  --slurpfile retired "$here/claude/container-allow.retired.json" --argjson dirs "$dirs" --argjson asks "$asks" \
  --argjson kernel "$kernel" --argjson retired_asks "$retired_asks" '
  def add($new): reduce ($new[]) as $x (.; if index($x) then . else . + [$x] end);
  .permissions.defaultMode = "auto"
  | .permissions.allow = ((.permissions.allow // []) - $retired[0] | add($list[0]) | add($kernel))
  | .permissions.ask = ((.permissions.ask // []) - $retired_asks | add($asks))
  | .permissions.additionalDirectories = ((.permissions.additionalDirectories // []) | add($dirs))' \
  "$settings" > "$settings.tmp" || { rm -f "$settings.tmp"; exit 1; }
mv "$settings.tmp" "$settings"
