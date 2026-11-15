#!/usr/bin/env bash
# Gives each repo of the container its agentics profile. The commit lock is claude-ask-rules.sh.
# Usage: agentics-profiles.sh [workspaces folder, default /workspaces]
# A profile is agentics/profiles/<repo>.yaml in this dotfiles repo. It is copied to the repo root once, as
# agentics.container.yaml, and hidden from git through .git/info/exclude: a file of this clone (the host's
# clone too, as the folder is shared), never committed, so the team's .gitignore is untouched. Its own name, because the repo folder is shared with the host: its paths
# (/home/vscode/...) are the container's, and a host agentics.yaml with host paths must not be mixed up with it.
set -euo pipefail

workspaces="${1:-/workspaces}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
profiles="${AGENTICS_PROFILES:-$here/agentics/profiles}"
kernel="${AGENTICS_DIR:-$HOME/agentics}/agentics"
name=agentics.container.yaml

exclude_in() {  # exclude_in <repo> <pattern>...: add each pattern to the repo's own info/exclude, once
  local repo=$1 exclude path; shift
  exclude="$(git -C "$repo" rev-parse --git-path info/exclude)"
  case "$exclude" in /*) ;; *) exclude="$repo/$exclude" ;; esac
  mkdir -p "$(dirname "$exclude")"
  # A last line without its newline would swallow the first pattern appended.
  if [ -s "$exclude" ] && [ -n "$(tail -c1 "$exclude")" ]; then echo >> "$exclude"; fi
  for path in "$@"; do
    grep -qxF "$path" "$exclude" 2> /dev/null || echo "$path" >> "$exclude"
  done
}

# One repo git cannot read (a host worktree whose .git points to a host path, a folder another user owns)
# must not stop the whole install: it is skipped, and git's own reason is printed, not hidden.
declare -A skipped=()
usable() {  # usable <repo>: the repo's own root (a plain folder inside a parent repo passes
            # `rev-parse --is-inside-work-tree`), and git can read it
  local repo=$1 why
  [ -e "$repo/.git" ] || return 1
  [ -z "${skipped[$repo]:-}" ] || return 1
  if ! why="$(git -C "$repo" rev-parse --git-dir 2>&1 > /dev/null)"; then
    echo "   warning: skipped $repo: ${why:-git cannot read it}" >&2
    skipped[$repo]=1
    return 1
  fi
}

# Every repo, with a profile here or not: a container profile made by hand must never reach a team commit,
# nor what it writes in the repo. .agentics/: role rules (`roles.<role>.rules`, as in the kernel's demos);
# .agentic/ and agentic-reports/: knowledge base and reports of the starter profile `agentics init` writes.
# The .git folder is the host's too: these patterns also disappear from `git status` on the host. Intended.
for repo in "$workspaces"/*/; do
  repo="${repo%/}"
  if usable "$repo"; then exclude_in "$repo" "$name" .agentics/ .agentic/ agentic-reports/; fi
done

failed=()
for profile in "$profiles"/*.yaml; do
  [ -e "$profile" ] || continue
  repo="$workspaces/$(basename "$profile" .yaml)"
  usable "$repo" || continue
  echo "-- agentics profile for $repo"

  # The profiles say /home/vscode, the remoteUser of the team's dev containers: make it this container's $HOME.
  rendered="$(mktemp)"
  sed "s#/home/vscode#$HOME#g" "$profile" > "$rendered"
  # Never overwrite: the copy in the repo may hold a local edit. Say so, or a fix to the profile here is lost silently.
  if [ ! -e "$repo/$name" ]; then
    cp "$rendered" "$repo/$name"
  elif ! cmp -s "$rendered" "$repo/$name"; then
    echo "   note: $repo/$name differs from $profile; the repo copy is kept"
  fi
  rm -f "$rendered"

  # One repo the kernel refuses must not leave the repos after it unset: carry on, and fail at the end.
  if ! { "$kernel" init --project "$repo/$name" && "$kernel" check --project "$repo/$name"; }; then
    failed+=("$repo")
  fi
done
if [ ${#failed[@]} -gt 0 ]; then
  echo "error: agentics init/check failed for: ${failed[*]}" >&2
  exit 1
fi
