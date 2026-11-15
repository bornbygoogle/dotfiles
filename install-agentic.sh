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
# First, before any npx or claude: modern-web-guidance sends a usage event during its own install unless this is
# 1 or true, and Claude Code reads it too. Step 6 makes it last beyond this script. It comes before step 7:
# the private repos can only be cloned by hand, so an automatic build always stops there.
export DISABLE_TELEMETRY=1

echo "== 1/10 Claude Code"
if ! command -v claude > /dev/null; then
  npm install -g @anthropic-ai/claude-code
fi

echo "== 2/10 rtk (shorter command output for Claude)"
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
# Two lines, not `&&`: set -e ignores a failure on the left of `&&`.
jq '(.hooks.PreToolUse[].hooks[] | select(.command == "rtk hook claude") | .command) = "~/.claude/hooks/rtk-hook"' \
  "$settings" > "$settings.tmp"
mv "$settings.tmp" "$settings"

echo "== 3/10 no commit without my yes (Claude Code ask rules)"
# Early on purpose: the private repos further down stop every automatic build, and a container without
# these rules has no commit lock at all.
bash "$HERE/claude-ask-rules.sh"

echo "== 4/10 bun (claude-mem runs on it)"
if ! command -v bun > /dev/null; then
  curl -fsSL https://bun.sh/install | bash
fi

echo "== 5/10 Claude plugins: claude-mem and ponytail"
claude plugin marketplace add thedotmack/claude-mem || true      # already added: not an error
claude plugin marketplace add DietrichGebert/ponytail || true
claude plugin install --scope user claude-mem@thedotmack
claude plugin install --scope user ponytail@ponytail
mkdir -p "$HOME/.config/ponytail"
echo '{ "defaultMode": "ultra" }' > "$HOME/.config/ponytail/config.json"

echo "== 6/10 modern-web-guidance skill, and telemetry off for good"
# The export above dies with this script. settings.json `env` keeps it for Claude Code and every command it runs;
# .bashrc for my interactive bash terminals (the container's default shell). A non-interactive `bash -c` or a
# VS Code task reads neither: set it there by hand if one runs npx.
# Leading newline: a .bashrc whose last line has none would swallow the export.
grep -qxF 'export DISABLE_TELEMETRY=1' "$HOME/.bashrc" 2> /dev/null \
  || printf '\nexport DISABLE_TELEMETRY=1\n' >> "$HOME/.bashrc"
jq '.env.DISABLE_TELEMETRY = "1"' "$settings" > "$settings.tmp"
mv "$settings.tmp" "$settings"
# Without a terminal, `install` alone stops on two questions (which agent, proceed?) and installs nothing
# (SKILLS_PROMPT_REQUIRES_TTY, measured 2026-11-14). -g: in ~/.claude/skills, not in the folder this runs from.
(cd "$HOME" && npx -y modern-web-guidance@latest install -g --agent claude-code -y < /dev/null)

echo "== 7/10 agentics kernel and secondbrain (private repos)"
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

echo "== 8/10 Python packages the kernel imports (yaml, markdown, pytest, pytest-xdist for its own tests)"
if ! python3 -c "import yaml, markdown, pytest, xdist" 2> /dev/null; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq python3-yaml python3-markdown python3-pytest python3-pytest-xdist
fi

echo "== 9/10 /dev-with-agents command, its card providers and their shortcuts"
bash "$HERE/render-command.sh" "$HERE/claude/commands/dev-with-agents.md" \
  "$HOME/.claude/commands/dev-with-agents.md" "$AGENTICS_DIR" "$SECONDBRAIN_DIR"
bash "$HERE/install-card-providers.sh" "$HERE"

echo "== 10/10 agentics profiles for the repos in /workspaces"
AGENTICS_DIR="$AGENTICS_DIR" bash "$HERE/agentics-profiles.sh" /workspaces

# Self-check: fail loudly now rather than in the middle of a run.
jq -e '.permissions.ask | index("Bash(*git commit*)")' "$HOME/.claude/settings.json" > /dev/null
jq -e '.env.DISABLE_TELEMETRY == "1"' "$HOME/.claude/settings.json" > /dev/null
test -f "$HOME/.claude/skills/modern-web-guidance/SKILL.md"
bash "$HERE/install-card-providers.sh" "$HERE" --check  # the chosen card providers are installed
claude --version
rtk --version
echo "dotnet test" | "$HOME/.claude/hooks/rtk-dotnet-test-rewrite" | grep -q "^rtk dotnet test"
claude plugin list | grep -E "claude-mem|ponytail"
"$AGENTICS_DIR/agentics" list > /dev/null
test -f "$SECONDBRAIN_DIR/tools/promote.py"  # without it, the last stage of a run crashes
echo "Done. Next: run 'claude' once to log in."
