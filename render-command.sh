#!/usr/bin/env bash
# Writes the container's copy of the /dev-with-agents command from the one in this repo.
# Usage: render-command.sh <source.md> <target.md> <agentics dir> <secondbrain dir>
# The source names the paths of my own computer: point them at the container copies, and at the container's own
# profile name (agentics-profiles.sh explains why it is not agentics.yaml). Test: render-command.test.sh.
set -euo pipefail

src=$1 dst=$2 agentics=$3 secondbrain=$4
mkdir -p "$(dirname "$dst")"
sed -e "s#/mnt/data2/DiskG/MEGA/Code/agentics#$agentics#g" \
  -e "s#/mnt/data2/DiskG/MEGA/Code/secondbrain#$secondbrain#g" \
  -e "s#<repo>/agentics\.yaml#<repo>/agentics.container.yaml#g" \
  -e 's#`agentics\.yaml`#`agentics.container.yaml`#g' \
  -e 's#^\*\*Dev container or host?\*\*.*#**This copy is installed in the dev container only:** every paragraph that says "in the dev container" applies to you.#' \
  "$src" > "$dst"
# The copy is only ever installed in the container, so it says so: `docker exec` and Codespaces do not set
# $REMOTE_CONTAINERS, and an agent that guessed "host" would skip the "Commit? yes/no" gate.
