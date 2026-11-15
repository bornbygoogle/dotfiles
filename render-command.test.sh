#!/usr/bin/env bash
# Runnable check for render-command.sh, on the real claude/commands/dev-with-agents.md: no network, no model.
set -u
here=$(cd "$(dirname "$0")" && pwd)
fail=0
check() {  # $1 = label, then the test command
  local label=$1; shift
  if "$@"; then echo "ok   $label"; else echo "FAIL $label"; fail=1; fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
src="$here/claude/commands/dev-with-agents.md"
out="$tmp/commands/dev-with-agents.md"

check "the script runs" bash "$here/render-command.sh" "$src" "$out" /home/u/agentics /home/u/secondbrain
check "no path of my computer is left" bash -c "! grep -q '/mnt/data2' '$out'"
check "the kernel path is the container's" grep -q '/home/u/agentics' "$out"
# Any agentics.yaml left, other than the kernel's demo profiles, would point the container agent at the host profile.
check "every profile reference is the container's" \
  bash -c "! grep -o '[^ ]*agentics\.yaml[^ ]*' '$out' | grep -v '/demo/' | grep -q ."
check "the container profile is named" grep -q 'agentics.container.yaml' "$out"
# The source is shared with the host: the container-only paragraphs must say where they apply.
check "the source says how to tell the dev container" grep -q 'REMOTE_CONTAINERS' "$src"
check "no paragraph says 'this container' without saying which" bash -c "! grep -qi 'this container' '$src'"
# The rendered copy is only ever installed in the container: it says so, instead of relying on an env variable
# that `docker exec` or Codespaces do not set.
check "the container copy states it is in the dev container" grep -q 'This copy is installed in the dev container' "$out"
check "the container copy does not ask the agent to guess" bash -c "! grep -q 'REMOTE_CONTAINERS' '$out'"
check "the doc gives the container path of the profile script" grep -q '~/dotfiles/agentics-profiles.sh' "$src"

# Starting from a card (docs/superpowers/specs/2026-11-15-dev-with-agents-card-design.md).
card=$(sed -n '/^## Start from a card/,/^## [^S]/p' "$out")
has() { grep -q -- "$1" <<< "$card"; }
check "the usage block shows the card flags" grep -q -- '^    /dev-with-agents --card-provider <provider> --card <id>' "$out"
check "the card section exists in the container copy" test -n "$card"
check "one card flag alone is refused with the usage line" has 'Both flags or neither'
check "a missing provider says how to install it" has 'card-providers.conf'
check "an unknown provider lists the providers and stops" has 'list the files in `~/.claude/card-providers/`'
check "the card flow stops on the exact question" has '\*\*"Run? go / answers"\*\*'
check "only go starts the run" has 'Only an explicit "go"'
check "the analysis reads only" has 'nothing is built, run or edited before "go"'
check "the two brief files" \
  bash -c "grep -q 'briefs/<id>.decision.md' <<< \"\$1\" && grep -q 'briefs/<id>.reference.md' <<< \"\$1\"" _ "$card"
# The bugfix workflow gives `--reference` and `--answer` to no role (only pentest roles take reference_doc):
# the approved brief must BE the description. Read from the file, so card text never meets the shell parser.
check "the run's description is the approved reference file" has '--feature "$(cat <reports>/briefs/<id>.reference.md)"'
nothing_else() {  # $1 = a string the card section must not hold
  ! grep -qF -- "$1" <<< "$card"
}
check "no --reference: no bugfix role reads it" nothing_else '--reference '
check "no --answer: no bugfix role reads it, and a second one replaces the first" nothing_else '--answer '
check "the card title is never pasted into a shell command" nothing_else '"<card title>"'
order() {  # the nine parts of the decision file, in the spec's order
  local prev=0 n h
  for h in "In short" "Decisions for you" "What the card asks" "Analysis" "Proposed design" "Risks" \
    'How "done" is checked' "Effort" "Sources"; do
    n=$(grep -n -m1 -- "^ *[0-9]\. \*\*$h" <<< "$card" | cut -d: -f1)
    [ -n "$n" ] && [ "$n" -gt "$prev" ] || return 1
    prev=$n
  done
}
check "the decision file has its nine parts, in order" order
check "no tracker detail in the main command" bash -c "! grep -qE 'get_issue|search_issues|subtask of|youtrack\\.cloud|Fait quand' '$src'"
check "a card flow before go is not a run" grep -q 'a card flow until the user says "go"' "$src"
# Final review minors, 2026-11-15.
check "the card pair is the named exception to one flag per invocation" grep -q 'The card pair is the one exception' "$src"
check "--worktree with a card is stated" has 'Add `--worktree` to a card'
check "a mixed reply is an answer, not a go" has '"go, but …" is an answer'
check "the brief has a home when the repo has no profile yet" has 'no profile yet'
check "the mission slug follows the kernel's rule" has 'at most 60 characters'
check "the reference cap is in bytes" has 'at most 6000 bytes'
check "the stated budget floor is the kernel's smallest (ui-designer, 10000)" has 'budgets start at 10 KB'
check "the question is bold on its own" has '^ *[0-9]\. Show the decision file in full, then ask exactly: \*\*"Run? go / answers"\*\*, and stop\.$'
check "the clean-tree check expects the brief" grep -q 'A brief under `<reports>/briefs/` is expected' "$src"

exit $fail
