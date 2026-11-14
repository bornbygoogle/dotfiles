#!/usr/bin/env bash
# Personal setup for a dev container: installs the agentics pipeline and the /dev-with-agents command.
# VS Code runs this from my dotfiles repo each time a container is built. Nothing here is shared with the team.
# No secret in this file: log in to Claude by hand once (`claude`), inside the container.
set -euo pipefail

AGENTICS_REPO="${AGENTICS_REPO:-https://github.com/bornbygoogle/agentics.git}"
AGENTICS_DIR="$HOME/agentics"
SECONDBRAIN_REPO="${SECONDBRAIN_REPO:-https://github.com/bornbygoogle/secondbrain.git}"
SECONDBRAIN_DIR="$HOME/secondbrain"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"

echo "== 1/7 Claude Code"
if ! command -v claude > /dev/null; then
  npm install -g @anthropic-ai/claude-code
fi

echo "== 2/7 rtk (shorter command output for Claude)"
if ! command -v rtk > /dev/null; then
  # The installer checks the release checksum and refuses an unverified binary.
  curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
fi
# -g: for every project in this container, not just one.
rtk init -g --auto-patch

# rtk does not shorten `dotnet test` by itself: my wrapper hook adds it (it calls `rtk hook claude` first).
if ! command -v jq > /dev/null; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq jq
fi
mkdir -p "$HOME/.claude/hooks"
cp "$HERE"/claude/hooks/rtk-hook "$HERE"/claude/hooks/rtk-dotnet-test-rewrite "$HOME/.claude/hooks/"
chmod +x "$HOME/.claude/hooks/rtk-hook" "$HOME/.claude/hooks/rtk-dotnet-test-rewrite"
# Swap rtk's own hook for the wrapper, so each command goes through rtk once.
settings="$HOME/.claude/settings.json"
jq '(.hooks.PreToolUse[].hooks[] | select(.command == "rtk hook claude") | .command) = "~/.claude/hooks/rtk-hook"' \
  "$settings" > "$settings.tmp" && mv "$settings.tmp" "$settings"

echo "== 3/7 bun (claude-mem runs on it)"
if ! command -v bun > /dev/null; then
  curl -fsSL https://bun.sh/install | bash
fi

echo "== 4/7 Claude plugins: claude-mem and ponytail"
claude plugin marketplace add thedotmack/claude-mem || true      # already added: not an error
claude plugin marketplace add DietrichGebert/ponytail || true
claude plugin install --scope user claude-mem@thedotmack
claude plugin install --scope user ponytail@ponytail
mkdir -p "$HOME/.config/ponytail"
echo '{ "defaultMode": "ultra" }' > "$HOME/.config/ponytail/config.json"

echo "== 5/7 agentics kernel and secondbrain (private repos)"
# The kernel looks for the secondbrain next to itself (../secondbrain): keep both in $HOME.
# The token stays in memory for 15 minutes so it is typed once for both repos, and is never written to disk.
GIT_LOGIN=(-c credential.helper= -c "credential.helper=cache --timeout=900")
get_repo() {  # get_repo <url> <dir>
  if [ -d "$2/.git" ]; then
    git "${GIT_LOGIN[@]}" -C "$2" pull --ff-only || echo "Warning: could not update $2, keeping the current copy." >&2
  elif ! git "${GIT_LOGIN[@]}" clone "$1" "$2"; then
    # During the automatic build there is no terminal, so git cannot ask for a login: run it again by hand.
    echo "Error: could not clone $1 (private repo, no GitHub login in the container)." >&2
    echo "Open a terminal in the container and run: bash $HERE/install-agentic.sh" >&2
    echo "Git asks a username and a password: the password is a GitHub token, not your account password." >&2
    exit 1
  fi
}
get_repo "$AGENTICS_REPO" "$AGENTICS_DIR"
get_repo "$SECONDBRAIN_REPO" "$SECONDBRAIN_DIR"

echo "== 6/7 Python packages the kernel imports (yaml, markdown, pytest, pytest-xdist for its own tests)"
if ! python3 -c "import yaml, markdown, pytest, xdist" 2> /dev/null; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq python3-yaml python3-markdown python3-pytest python3-pytest-xdist
fi

echo "== 7/7 /dev-with-agents command"
# The command file names the paths of my own computer: point them at the container copies.
mkdir -p "$HOME/.claude/commands"
sed -e "s#/mnt/data2/DiskG/MEGA/Code/agentics#$AGENTICS_DIR#g" \
  -e "s#/mnt/data2/DiskG/MEGA/Code/secondbrain#$SECONDBRAIN_DIR#g" \
  "$HERE/claude/commands/dev-with-agents.md" > "$HOME/.claude/commands/dev-with-agents.md"

# Self-check: fail loudly now rather than in the middle of a run.
claude --version
rtk --version
echo "dotnet test" | "$HOME/.claude/hooks/rtk-dotnet-test-rewrite" | grep -q "^rtk dotnet test"
claude plugin list | grep -E "claude-mem|ponytail"
"$AGENTICS_DIR/agentics" list > /dev/null
test -f "$SECONDBRAIN_DIR/tools/promote.py"  # without it, the last stage of a run crashes
echo "Done. Next: run 'claude' once to log in."
