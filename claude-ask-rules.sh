#!/usr/bin/env bash
# No commit without my yes: makes Claude Code ask before any command that creates or publishes a commit.
# Usage: claude-ask-rules.sh   (writes the rules to ~/.claude/settings.json, once)
# Its own script, run early by install-agentic.sh: it needs nothing but jq, so it must not wait for the steps that
# can stop an automatic build (the private repos). A container without it has no commit lock at all.
set -euo pipefail

# An agent never commits on its own: Claude asks first, even in auto mode. I read the change and answer.
# Every git command that creates or publishes a commit, in two forms. Wildcards on both sides: the rules are
# matched AFTER the rtk hook rewrites `git commit` into `rtk git commit`, so a `Bash(git commit:*)` prefix rule
# never fires (measured 2026-11-14, claude 2.1.325). `git * <sub>` covers options before the subcommand:
# `git -C <dir> commit` got through without it. The price, accepted: any git command with " <sub>" later in the
# line asks too (`git log --grep commit`, `git diff -- amount.cs`). Narrowing it would reopen the -C hole.
# push: rtk rewrites it too, so the team repos' own `ask: Bash(git push *)` never fires in this container.
# `agentics* done`: a quoted kernel path (`"$AGENTICS/agentics" done`) has a quote before " done". The same
# price: a run whose task text holds " done" (`--bugs "order never marked done"`) asks too.
rules=$(jq -nc '["Bash(*agentics* done*)", "Bash(*gh pr merge*)"]
  + (["commit", "merge", "cherry-pick", "revert", "am", "rebase", "pull", "push"]
  | map("Bash(*git \(.)*)", "Bash(*git * \(.)*)"))')
settings="$HOME/.claude/settings.json"
mkdir -p "$(dirname "$settings")"
[ -f "$settings" ] || echo '{}' > "$settings"
# Two lines, not `&&`: set -e ignores a failure on the left of `&&`, and a broken settings.json must stop the script.
jq --argjson r "$rules" '.permissions.ask = ((.permissions.ask // []) + $r | unique)' "$settings" > "$settings.tmp"
mv "$settings.tmp" "$settings"
