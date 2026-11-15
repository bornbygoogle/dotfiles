#!/usr/bin/env bash
# No commit without my yes: makes Claude Code ask before any command that creates or publishes a commit, before
# every gh command, and before a read of the GitHub token gh keeps (install step 7).
# Usage: claude-ask-rules.sh   (writes the rules to ~/.claude/settings.json, once)
# Its own script, run early by install-agentic.sh: it needs nothing but jq, so it must not wait for the steps that
# can stop an automatic build (the private repos). A container without it has no commit lock at all.
set -euo pipefail

# What these rules are: a stop before an agent's ORDINARY commands, so I read the change and answer. Not a sandbox:
# a text pattern cannot see through `git c"ommit"`, `git \commit`, a tab, an alias, `git-commit` or `git send-pack`,
# and an agent set on getting round them can. Every rule below is matched as a glob on the command line.
# git: every command that creates or publishes a commit. Wildcards on both sides: the rules are matched AFTER the
# rtk hook rewrites `git commit` into `rtk git commit`, so a `Bash(git commit:*)` prefix rule never fires (measured
# 2026-11-14, claude 2.1.325). `git * <sub>` covers options before the subcommand: `git -C <dir> commit` got through
# without it. The price, accepted: any git command with " <sub>" later in the line asks too (`git log --grep
# commit`, `git diff -- amount.cs`). Narrowing it would reopen the -C hole. No form for a quoted subcommand
# (`git "commit"`): it also caught every quoted argument starting the same way (`git log --author "amy"`).
# `credential`: `git credential fill` prints the GitHub token that gh hands git (install step 7), and so do the
# helpers run as programs of their own (`git-credential-store get`).
# push: rtk rewrites it too, so the team repos' own `ask: Bash(git push *)` never fires in this container.
# gh: install step 7 logs it in to GitHub. Every gh command asks, reads too (`gh pr view`): a list of the write verbs
# had holes -- a flag before the verb (`gh pr -R o/r merge`), an alias, an extension, and the ways to print the
# token (`gh auth status -t`, `gh auth git-credential get`). `gh` as a word of its own: at the start, after a space,
# a tab, a path, `$(`, a backtick, `;`, `|` or `&`, or quoted -- not inside one (`high`, `through`). Not after a
# line break: a rule holds no newline. Its token file asks too: the Read rule, which Claude Code also applies to
# Grep and Glob as best it can, and any shell line naming gh's config folder (not `ghostty`, `gh-dash`) or the
# token's field name.
# The token is still a file the agent's user can read: these rules make reading it ask, nothing more. A gh login
# with a fine-grained token, scoped to the repos the container needs, is what limits the damage.
# mcp__youtrack__*: a card flow (/dev-with-agents --card-provider youtrack) reads the tracker only. Its prose says
# so; these rules make a write ask anyway. The read tools stay free. The list is explicit (an `mcp__youtrack`
# catch-all would also catch the reads, and ask beats allow): a write tool the server adds later is not in it.
# Container only, like this whole install. Ask in auto mode was measured for Bash rules, not yet for MCP tools.
# `agentics* done`: a quoted kernel path (`"$AGENTICS/agentics" done`) has a quote before " done". The same
# price: a run whose task text holds " done" (`--bugs "order never marked done"`) asks too.
rules=$(jq -nc '["Bash(*agentics* done*)", "Read(~/.config/gh/**)", "Bash(*config/gh/*)", "Bash(*config/gh)", "Bash(*config/gh *)",
    "Bash(*oauth_token*)",
    "Bash(*git-credential*)"]
  + (["gh *", "* gh *", "*\tgh *", "*/gh *", "*(gh *", "*`gh *", "*;gh *", "*|gh *", "*&gh *", "*\"gh\" *",
      "*'"'"'gh'"'"' *"] | map("Bash(\(.))"))
  + (["commit", "merge", "cherry-pick", "revert", "am", "rebase", "pull", "push", "credential"]
  | map("Bash(*git \(.)*)", "Bash(*git * \(.)*)"))
  + (["add_issue_comment", "update_issue", "change_issue_assignee", "log_work", "manage_issue_tags", "link_issues",
      "create_issue", "create_draft_issue", "create_article", "update_article"] | map("mcp__youtrack__\(.)"))')
# The one rule a committed version wrote and this one replaces (every gh command asks now). The merge below only
# adds, so it is taken out by name: the same rule written by hand goes too, and `gh *` still covers it.
retired='["Bash(*gh pr merge*)"]'
settings="$HOME/.claude/settings.json"
mkdir -p "$(dirname "$settings")"
[ -f "$settings" ] || echo '{}' > "$settings"
# Written beside the REAL file, then moved over it in one step: a link into my dotfiles stays a link, and the file
# is never half-written (a full disk or a kill mid-write leaves the old one whole). It keeps its permissions (it may
# be private: env can hold tokens). Rules already there keep their place; new ones go at the end, once.
target=$(readlink -f "$settings")
trap 'rm -f "$target.tmp"' EXIT  # jq failing on a broken file must not leave its half-written output behind
# Two lines, not `&&`: set -e ignores a failure on the left of `&&`, and a broken settings.json must stop the script.
jq --argjson r "$rules" --argjson old "$retired" \
  '.permissions.ask = reduce $r[] as $x ((.permissions.ask // []) - $old; if index([$x]) then . else . + [$x] end)' \
  "$settings" > "$target.tmp"
chmod --reference="$target" "$target.tmp"
mv "$target.tmp" "$target"
