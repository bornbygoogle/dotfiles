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

exit $fail
