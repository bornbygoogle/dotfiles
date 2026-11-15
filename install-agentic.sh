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
# 1 or true, and Claude Code reads it too. Step 6 makes it last beyond this script. It comes before step 8:
# the private repos are cloned with a login, so an automatic build stops there unless gh is logged in (step 7).
export DISABLE_TELEMETRY=1

echo "== 1/11 Claude Code"
if ! command -v claude > /dev/null; then
  npm install -g @anthropic-ai/claude-code
fi

echo "== 2/11 rtk (shorter command output for Claude)"
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

echo "== 3/11 no commit without my yes (ask rules), then auto mode and allow rules"
# Early on purpose: the private repos further down stop an automatic build with no gh login, and a container without
# these rules has no commit lock at all.
bash "$HERE/claude-ask-rules.sh"
# Auto mode and allow rules for everyday commands. After the ask rules on purpose: ask beats allow.
bash "$HERE/claude-container-settings.sh" /workspaces

echo "== 4/11 bun (claude-mem runs on it)"
if ! command -v bun > /dev/null; then
  curl -fsSL https://bun.sh/install | bash
fi

echo "== 5/11 Claude plugins: claude-mem and ponytail"
claude plugin marketplace add thedotmack/claude-mem || true      # already added: not an error
claude plugin marketplace add DietrichGebert/ponytail || true
claude plugin install --scope user claude-mem@thedotmack
claude plugin install --scope user ponytail@ponytail
mkdir -p "$HOME/.config/ponytail"
echo '{ "defaultMode": "ultra" }' > "$HOME/.config/ponytail/config.json"

echo "== 6/11 modern-web-guidance skill, and telemetry off for good"
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

echo "== 7/11 GitHub CLI (gh): pull requests from the container, and git's login for github.com"
# Before the private repos on purpose: their clone ends every automatic build, and gh needs no terminal to install.
# From GitHub's own apt repo, as cli.github.com documents for Debian and Ubuntu: the distro's gh lags far behind.
# The keyring's primary keys, as cli/cli's docs/install_linux.md lists them (checked 2026-11-15): the first expired
# in 2026, the second signs the packages since. The keyring may hold only these, and must hold the signing one, so
# GitHub dropping the expired key changes nothing. When GitHub rotates again, step 7 says so and skips gh.
GH_KEY_FPRS="2C6106201985B60E6C7AC87323F3D4EA75716059 7F38BBB59D064DBCB3D84D725612B36462313325"
GH_SIGNING_FPR=7F38BBB59D064DBCB3D84D725612B36462313325
# gh is optional: any problem installing it is said, and the install goes on without it.
gh_problem=""
if ! command -v gh > /dev/null; then
  if ! command -v gpg > /dev/null; then
    gh_problem="gpg is needed to check its apt key (sudo apt-get install gnupg, then run this again)"
  else
    # Nothing below can end the script before the rm: each command that may fail is a condition or has its ||.
    key=$(mktemp)
    # The keyring signs the gh that apt installs under sudo: a swapped key must stop here, not be trusted. One key
    # more than the published ones, and apt would trust that one too.
    # gpg's listing is read whole, then by awk: `gpg | grep -q` under pipefail fails when grep stops first (SIGPIPE).
    # gpg failing is told apart from a wrong key: a cut download or a gpg without --show-keys (older than 2.2.8)
    # is not a swapped keyring, and must not raise that alarm.
    primaries="" gpg_read=1
    if curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o "$key"; then
      listing=$(gpg --show-keys --with-colons "$key" 2> /dev/null) || gpg_read=0
      primaries=$(awk -F: '/^pub:/ { want = 1; next } want && /^fpr:/ { print $10; want = 0 }' <<< "${listing:-}")
    fi
    if [ ! -s "$key" ]; then
      gh_problem="could not download its apt key from cli.github.com"
    elif [ "$gpg_read" = 0 ]; then
      gh_problem="gpg could not read its downloaded apt key (a cut download, or a gpg older than 2.2.8)"
    elif ! grep -qx "$GH_SIGNING_FPR" <<< "$primaries" \
        || grep -qvxF -e "${GH_KEY_FPRS// /$'\n'}" <<< "$primaries"; then
      gh_problem="its apt keyring is not the published one (keys allowed: $GH_KEY_FPRS)"
    elif ! { sudo mkdir -p -m 755 /etc/apt/keyrings \
        && sudo install -m 644 "$key" /etc/apt/keyrings/githubcli-archive-keyring.gpg \
        && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg]" \
          "https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
        && sudo apt-get update -qq && sudo apt-get install -y -qq gh; }; then
      gh_problem="apt could not install it (its own message is above)"
      # A source left behind would make the next `apt-get update` (step 9, or any later one) trip on it.
      sudo rm -f /etc/apt/sources.list.d/github-cli.list /etc/apt/keyrings/githubcli-archive-keyring.gpg || true
    fi
    rm -f "$key"
  fi
fi
if [ -n "$gh_problem" ]; then
  echo "Warning: gh is not installed: $gh_problem. The install goes on without it." >&2
fi
# The login asks questions and shows a code to copy: only with a terminal on both ends; the automatic build has none.
# gh keeps its token in ~/.config/gh/hosts.yml (a container has no keyring); `gh auth logout` removes it.
# Logged in or not is read once, locally: `gh auth status` checks the token over the network, so a slow GitHub made
# a logged-in user look logged out. Step 8 reuses the answer.
GH_LOGIN_CMD="gh auth login --hostname github.com --git-protocol https --web && gh auth setup-git --hostname github.com"
gh_login_hint() {
  echo "gh is not logged in. For pull requests from the container, in a VS Code terminal there, run:" >&2
  echo "  $GH_LOGIN_CMD" >&2
  echo "gh then keeps its token in ~/.config/gh/hosts.yml; 'gh auth logout' removes it." >&2
}
# A GH_TOKEN or GITHUB_TOKEN in the environment (a Codespace's, scoped to one repo) is not a login of mine.
gh_logged_in=0
if ! command -v gh > /dev/null; then
  :  # not installed: said above
elif env -u GH_TOKEN -u GITHUB_TOKEN gh auth token --hostname github.com > /dev/null 2>&1; then
  gh_logged_in=1
elif [ -t 0 ] && [ -t 1 ]; then
  # Optional: a cancelled or failed login must not end the install. A container may have no browser to open.
  # Ctrl-C reaches bash too: with a handler (not ignored, so gh still gets it) bash outlives it and goes on.
  echo "gh shows a one-time code: if no browser opens, enter it at https://github.com/login/device"
  trap 'echo' INT
  if env -u GH_TOKEN -u GITHUB_TOKEN gh auth login --hostname github.com --git-protocol https --web; then
    gh_logged_in=1
  else
    gh_login_hint
  fi
  trap - INT
else
  gh_login_hint
fi
# setup-git makes git use gh's login for github.com, in place of the empty `store` copied from the host. Run even
# when the login just offered it: a session's `git push` depends on it, whatever was answered there.
if [ "$gh_logged_in" = 1 ] && ! gh auth setup-git --hostname github.com; then
  echo "Warning: could not point git at gh's login (gh auth setup-git); git push from a session will ask." >&2
fi

echo "== 8/11 agentics kernel and secondbrain (private repos)"
# The kernel looks for the secondbrain next to itself (../secondbrain): keep both in $HOME.
# `credential.helper=` first: the host's `store`, copied into the container, would write a typed token to disk.
# Logged in to gh (step 7): its login. Otherwise a token typed by hand stays in memory for 15 minutes, once for both.
# With gh's login, git runs without GH_TOKEN/GITHUB_TOKEN: gh's helper would hand git that token first.
TYPED_LOGIN=(-c credential.helper= -c "credential.helper=cache --timeout=900")
if [ "$gh_logged_in" = 1 ]; then
  GIT_ENV=(env -u GH_TOKEN -u GITHUB_TOKEN)
  GIT_LOGIN=(-c credential.helper= -c "credential.helper=!gh auth git-credential")
else
  GIT_ENV=(env)
  GIT_LOGIN=("${TYPED_LOGIN[@]}")
fi
# gh's login may not see this repo (another account, a token scoped elsewhere): on a terminal, a typed token.
typed_retry() {  # typed_retry <what failed>: true when git may ask for a typed token instead
  [ "$gh_logged_in" = 1 ] && [ -t 0 ] && [ -t 1 ] \
    && echo "gh's login could not $1: git now asks for a GitHub token instead." >&2
}
get_repo() {  # get_repo <url> <dir>
  if [ -d "$2/.git" ]; then
    "${GIT_ENV[@]}" git "${GIT_LOGIN[@]}" -C "$2" pull --ff-only \
      || { typed_retry "update $2" && git "${TYPED_LOGIN[@]}" -C "$2" pull --ff-only; } \
      || echo "Warning: could not update $2, keeping the current copy." >&2
  elif ! "${GIT_ENV[@]}" git "${GIT_LOGIN[@]}" clone "$1" "$2" \
      && ! { typed_retry "clone $1" && git "${TYPED_LOGIN[@]}" clone "$1" "$2"; }; then
    if [ "$gh_logged_in" = 1 ]; then
      # gh holds a token, read locally: it may be stale, revoked, or without access to this repo.
      echo "Error: could not clone $1: git used gh's login, and GitHub refused it or could not be reached." >&2
      echo "Check it with 'gh auth status'. If the token is stale or lacks this repo, log in again:" >&2
      echo "  $GH_LOGIN_CMD" >&2
      echo "then: bash $HERE/install-agentic.sh" >&2
    else
      # During the automatic build there is no terminal, so git cannot ask for a login: run it again by hand.
      echo "Error: could not clone $1 (private repo, no GitHub login in the container)." >&2
      echo "Open a terminal in the container and run: bash $HERE/install-agentic.sh" >&2
      echo "Git asks a username and a password: the password is a GitHub token, not your account password." >&2
      echo "Or log in to gh when step 7 offers it: git then uses that login and asks nothing." >&2
    fi
    exit 1
  fi
}
get_repo "$AGENTICS_REPO" "$AGENTICS_DIR"
get_repo "$SECONDBRAIN_REPO" "$SECONDBRAIN_DIR"

echo "== 9/11 Python packages the kernel imports (yaml, markdown, pytest, pytest-xdist for its own tests)"
if ! python3 -c "import yaml, markdown, pytest, xdist" 2> /dev/null; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq python3-yaml python3-markdown python3-pytest python3-pytest-xdist
fi

echo "== 10/11 /dev-with-agents command, its card providers and their shortcuts"
bash "$HERE/render-command.sh" "$HERE/claude/commands/dev-with-agents.md" \
  "$HOME/.claude/commands/dev-with-agents.md" "$AGENTICS_DIR" "$SECONDBRAIN_DIR"
bash "$HERE/install-card-providers.sh" "$HERE"

echo "== 11/11 agentics profiles for the repos in /workspaces"
AGENTICS_DIR="$AGENTICS_DIR" bash "$HERE/agentics-profiles.sh" /workspaces

# Self-check: fail loudly now rather than in the middle of a run.
jq -e '.permissions.ask | index("Bash(*git commit*)")' "$HOME/.claude/settings.json" > /dev/null
jq -e '.env.DISABLE_TELEMETRY == "1"' "$HOME/.claude/settings.json" > /dev/null
test -f "$HOME/.claude/skills/modern-web-guidance/SKILL.md"
bash "$HERE/install-card-providers.sh" "$HERE" --check  # the chosen card providers are installed
claude --version
rtk --version
if command -v gh > /dev/null; then gh --version; fi
echo "dotnet test" | "$HOME/.claude/hooks/rtk-dotnet-test-rewrite" | grep -q "^rtk dotnet test"
claude plugin list | grep -E "claude-mem|ponytail"
"$AGENTICS_DIR/agentics" list > /dev/null
test -f "$SECONDBRAIN_DIR/tools/promote.py"  # without it, the last stage of a run crashes
echo "Done. Next: run 'claude' once to log in, and log in to gh if step 7 says so."
