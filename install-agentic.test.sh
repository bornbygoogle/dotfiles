#!/usr/bin/env bash
# Runnable check for the GitHub CLI steps of install-agentic.sh: the real step text, run against fake gh, sudo,
# curl, gpg and dpkg on a PATH that holds nothing else. No network, no sudo, no login.
set -u
here=$(cd "$(dirname "$0")" && pwd)
script="$here/install-agentic.sh"
fail=0
check() {  # $1 = label, then the test command
  local label=$1; shift
  if "$@"; then echo "ok   $label"; else echo "FAIL $label"; fail=1; fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
bin="$tmp/bin"
mkdir -p "$bin" "$tmp/t"
# Only these real tools: the host's own gh must not be found.
for tool in bash sed grep mktemp rm cat cp chmod env seq ls awk sort paste; do ln -s "$(command -v "$tool")" "$bin/$tool"; done
# The two primary keys of the real keyring, as cli/cli's docs/install_linux.md lists them (2026-11-15).
good_fpr=2C6106201985B60E6C7AC87323F3D4EA75716059
good_fpr2=7F38BBB59D064DBCB3D84D725612B36462313325
cat > "$tmp/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "$LOG"
case "$1 $2" in
  "auth token") [ "${GH_LOGGED_IN:-0}" = 1 ] || [ -n "${GITHUB_TOKEN:-}${GH_TOKEN:-}" ] ;;
  "auth status") echo "auth status must not decide: it needs the network" >&2; exit 2 ;;
  "auth login") [ "${GH_LOGIN_INT:-0}" = 1 ] && kill -INT 0; [ "${GH_LOGIN_OK:-1}" = 1 ] ;;
  "auth setup-git") [ "${GH_SETUP_OK:-1}" = 1 ] ;;
  *) exit 0 ;;
esac
EOF
cat > "$bin/sudo" <<EOF
#!/usr/bin/env bash
echo "sudo \$*" >> "\$LOG"
[ "\${SUDO_FAIL:-}" = "\$1" ] && exit 1
if [ "\$*" = "apt-get install -y -qq gh" ] && [ "\${APT_NEEDS_FULL:-0}" = 1 ] \\
  && ! grep -qx "sudo apt-get update -qq" "\$LOG"; then exit 100; fi
[ "\$1" = tee ] && cat > /dev/null
[ "\$*" = "apt-get install -y -qq gh" ] && cp "$tmp/gh" "$bin/gh" && chmod +x "$bin/gh"
exit 0
EOF
cat > "$bin/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >> "$LOG"
[ "${CURL_OK:-1}" = 1 ] || exit 22
while [ $# -gt 0 ]; do [ "$1" = -o ] && echo KEY > "$2"; shift; done
EOF
cat > "$bin/gpg" <<'EOF'
#!/usr/bin/env bash
[ "${NEW_KEY_ONLY:-0}" = 1 ] || { echo "pub:e:4096:1:23F3D4EA75716059:1:::-:::scESC::::::23::0:"
  [ "${GPG_FAIL:-0}" = 1 ] && { echo "gpg: invalid option --show-keys" >&2; exit 2; }
echo "fpr:::::::::${KEY_FPR}:"
  echo "sub:e:4096:1:E5FAF19590714157:1662463626::::::e:"
  echo "fpr:::::::::5700BAB26C8DE75F3EE323FEE5FAF19590714157:"; }
[ "${ONE_KEY_ONLY:-0}" = 1 ] || { echo "pub:-:4096:1:5612B36462313325:1775559160:::-:::scESC:"
  echo "fpr:::::::::${KEY_FPR2}:"; }
if [ "${EXTRA_KEY:-0}" = 1 ]; then echo "pub:-:4096:1:EEEEEEEEEEEEEEEE:1:::-:::scESC::::::23::0:"
  echo "fpr:::::::::EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE:"; fi
[ "${GPG_FLOOD:-0}" = 1 ] && for i in $(seq 1 200000); do echo "uid:::::::::filler $i"; done
exit 0
EOF
printf '#!/usr/bin/env bash\necho amd64\n' > "$bin/dpkg"
chmod +x "$tmp/gh" "$bin/sudo" "$bin/curl" "$bin/gpg" "$bin/dpkg"

# The step's own text, cut out of the script between its banner and the next one.
step_gh=$(sed -n '/^echo "== 7\/11 GitHub CLI/,/^echo "== 8\/11/p' "$script" | sed '$d')
step_login=$(sed -n '/^echo "== 8\/11/,/^get_repo() {/p' "$script" | sed '$d')
run() {  # run <step text> [VAR=value ...]: stdin and stdout are no terminal, as in the automatic build
  local text=$1; shift
  : > "$tmp/log"
  env -i PATH="$bin" HOME="$tmp" LOG="$tmp/log" KEY_FPR="$good_fpr" KEY_FPR2="$good_fpr2" "$@" \
    TMPDIR="$tmp/t" bash -euo pipefail -c "$text" < /dev/null > "$tmp/out" 2>&1
}
has_gh() { cp "$tmp/gh" "$bin/gh"; chmod +x "$bin/gh"; }
no_gh() { rm -f "$bin/gh"; }

check "the gh step was found in the script" test -n "$step_gh"
check "gh is installed before the private repos, whose clone ends the automatic build" \
  test "$(grep -n '^echo "== 7/11 GitHub CLI' "$script" | cut -d: -f1)" \
    -lt "$(grep -n '^get_repo "$AGENTICS_REPO"' "$script" | cut -d: -f1)"
check "the self-check runs gh when step 7 installed it, and only then" \
  grep -qx 'if command -v gh > /dev/null; then gh --version; fi' "$script"

no_gh; run "$step_gh"; rc=$?
check "a missing gh is installed" test "$rc" = 0 -a -x "$bin/gh"
check "...from GitHub's apt repo" grep -q "^sudo apt-get install -y -qq gh$" "$tmp/log"
check "...after one apt update" test "$(grep -c '^sudo apt-get update' "$tmp/log")" = 1

no_gh; run "$step_gh" KEY_FPR=0000000000000000000000000000000000000000; rc=$?
check "a key with another fingerprint: gh is skipped, the install goes on" test "$rc" = 0 -a ! -e "$bin/gh"
check "...before anything is installed" bash -c "! grep -q 'apt-get install' '$tmp/log'"
check "...and says why" grep -q "keyring is not the published one" "$tmp/out"

no_gh; run "$step_gh" ONE_KEY_ONLY=1; rc=$?
check "the signing key missing (only the expired one left): gh is skipped, nothing installed" \
  bash -c "[ $rc = 0 ] && [ ! -e '$bin/gh' ] && ! grep -q 'apt-get install' '$tmp/log'"

no_gh; run "$step_gh" NEW_KEY_ONLY=1; rc=$?
check "the expired key dropped from the keyring: gh is still installed" test "$rc" = 0 -a -x "$bin/gh"

no_gh; run "$step_gh" EXTRA_KEY=1; rc=$?
check "the published keys plus another one: gh is skipped, nothing installed" \
  bash -c "[ $rc = 0 ] && [ ! -e '$bin/gh' ] && ! grep -q 'apt-get install' '$tmp/log'"

no_gh; run "$step_gh" SUDO_FAIL=install; rc=$?
check "sudo fails while installing the key: the install goes on" test "$rc" = 0
check "...says gh is not installed" grep -q "gh is not installed" "$tmp/out"
check "...and leaves no temporary file" test -z "$(ls -A "$tmp/t")"

no_gh; run "$step_gh" SUDO_FAIL=apt-get; rc=$?
check "apt fails: the install goes on" test "$rc" = 0 -a ! -e "$bin/gh"
check "...and the gh apt source is taken out again, so later apt updates do not trip on it" \
  grep -q "^sudo rm -f /etc/apt/sources.list.d/github-cli.list" "$tmp/log"

no_gh; run "$step_gh" GPG_FLOOD=1; rc=$?
check "a matching key is accepted however much gpg prints after its fingerprint" test "$rc" = 0 -a -x "$bin/gh"

no_gh; mv "$bin/gpg" "$tmp/gpg.off"; run "$step_gh"; rc=$?; mv "$tmp/gpg.off" "$bin/gpg"
check "no gpg: gh is skipped, the install goes on" test "$rc" = 0 -a ! -e "$bin/gh"
check "...saying gpg is missing, not that the key is wrong" grep -q "gpg is needed" "$tmp/out"

no_gh; run "$step_gh" GPG_FAIL=1; rc=$?
check "gpg cannot read the key: gh is skipped, the install goes on" test "$rc" = 0 -a ! -e "$bin/gh"
check "...saying gpg failed, not that the keyring was swapped" \
  bash -c "grep -q 'gpg could not read' '$tmp/out' && ! grep -q 'not the published one' '$tmp/out'"

no_gh; run "$step_gh" CURL_OK=0; rc=$?
check "the key cannot be downloaded: gh is skipped, the install goes on" test "$rc" = 0 -a ! -e "$bin/gh"
check "...saying so" grep -q "gh is not installed: could not download its apt key" "$tmp/out"
check "...and leaves no temporary file" test -z "$(ls -A "$tmp/t")"

has_gh; run "$step_gh" GH_LOGGED_IN=1
check "logged in: git is pointed at gh's login for github.com" grep -qx "gh auth setup-git --hostname github.com" "$tmp/log"
check "...decided without the network (no gh auth status)" bash -c "! grep -q 'gh auth status' '$tmp/log'"

has_gh; run "$step_gh" GH_LOGGED_IN=0 GITHUB_TOKEN=repo-scoped-test-value
check "a token in the environment is not taken for a gh login" bash -c "! grep -q 'setup-git' '$tmp/log'"

has_gh; run "$step_gh" GH_LOGGED_IN=1 GH_SETUP_OK=0; rc=$?
check "setup-git fails: the install goes on" test "$rc" = 0
check "...and says so" grep -q "could not point git at gh" "$tmp/out"

has_gh; run "$step_gh" GH_LOGGED_IN=0; rc=$?
check "logged out with no terminal: the build goes on" test "$rc" = 0
check "...without trying to log in" bash -c "! grep -q 'gh auth login' '$tmp/log'"
check "...and prints the commands, for github.com only" grep -q "gh auth setup-git --hostname github.com" "$tmp/out"
check "...and says where gh keeps its token" grep -q "hosts.yml" "$tmp/out"

# A cancelled or failed login on a terminal must not end the install. `script` gives the step a terminal.
if command -v script > /dev/null; then
  has_gh; : > "$tmp/log"
  printf '%s\n' "$step_gh" > "$tmp/step.sh"
  env -i PATH="$bin" HOME="$tmp" LOG="$tmp/log" KEY_FPR="$good_fpr" KEY_FPR2="$good_fpr2" GH_LOGGED_IN=0 GH_LOGIN_OK=0 \
    "$(command -v script)" -qec "bash -euo pipefail $tmp/step.sh" /dev/null > "$tmp/out" 2>&1; rc=$?
  check "a failed login on a terminal is tried" grep -q "^gh auth login --hostname github.com" "$tmp/log"
  check "...after saying where to enter the code if no browser opens" grep -q "github.com/login/device" "$tmp/out"
  check "...and does not stop the install" test "$rc" = 0
  check "...and git is not pointed at a gh with no login" bash -c "! grep -q 'setup-git' '$tmp/log'"
  # The marker is printed by the bash under test: Ctrl-C hits the whole foreground job, a wrapper shell included.
  has_gh; : > "$tmp/log"; printf '%s\necho STEP-7-DONE\n' "$step_gh" > "$tmp/step-marked.sh"
  env -i PATH="$bin" HOME="$tmp" LOG="$tmp/log" KEY_FPR="$good_fpr" KEY_FPR2="$good_fpr2" GH_LOGGED_IN=0 \
    GH_LOGIN_INT=1 "$(command -v script)" -qec "bash -euo pipefail $tmp/step-marked.sh" /dev/null \
    > "$tmp/out" 2>&1
  check "Ctrl-C during the login ends the login, not the install" grep -q "STEP-7-DONE" "$tmp/out"
else
  echo "skip the terminal cases: no 'script' command"
fi

has_gh; run "gh_logged_in=1; $step_login"' ; printf "%s\n" "${GIT_LOGIN[@]}"' 
check "logged in to gh: the private repos are fetched with gh's login" grep -qx 'credential.helper=!gh auth git-credential' "$tmp/out"
has_gh; run "gh_logged_in=0; $step_login"' ; printf "%s\n" "${GIT_LOGIN[@]}"' 
check "logged out: the token typed by hand stays in memory" grep -qx 'credential.helper=cache --timeout=900' "$tmp/out"
check "...and the host's store is skipped either way" grep -qx 'credential.helper=' "$tmp/out"

# Step 8 alone, with what it takes from step 7: the login command it prints.
step_repos="$(grep '^GH_LOGIN_CMD=' "$script")
$(sed -n '/^echo "== 8\/11/,/^get_repo "$AGENTICS_REPO"/p' "$script" | sed '$d')"
printf '#!/usr/bin/env bash\nexit 128\n' > "$bin/git"; chmod +x "$bin/git"
has_gh; run "gh_logged_in=1; HERE=/x; $step_repos"' ; get_repo https://github.com/o/private.git '"$tmp/clone"; rc=$?
check "a clone refused with gh's login stops the install" test "$rc" != 0
check "...saying git used gh's login, not that there is none" grep -q "used gh's login" "$tmp/out"
check "...and how to renew it" grep -q "gh auth login" "$tmp/out"
rm -f "$bin/git"

# A GITHUB_TOKEN in the environment would win over gh's login inside its credential helper: git runs without it.
printf '#!/usr/bin/env bash\necho "git token=[${GITHUB_TOKEN:-}${GH_TOKEN:-}] $*" >> "$LOG"\nexit 0\n' > "$bin/git"
chmod +x "$bin/git"
has_gh; run "gh_logged_in=1; HERE=/x; $step_repos"' ; get_repo https://github.com/o/private.git '"$tmp/clone3" \
  GITHUB_TOKEN=repo-scoped-test-value
check "git uses gh's login without an environment token in the way" grep -q '^git token=\[\] ' "$tmp/log"
rm -f "$bin/git"

# gh's login cannot see the private repo, on a terminal: git falls back to a token typed by hand, as before gh.
if command -v script > /dev/null; then
  printf '#!/usr/bin/env bash\necho "git $*" >> "$LOG"\ncase "$*" in *"gh auth git-credential"*) exit 128 ;; esac\nexit 0\n' \
    > "$bin/git"; chmod +x "$bin/git"; : > "$tmp/log"
  printf '%s\n' "gh_logged_in=1; HERE=/x; $step_repos" 'get_repo https://github.com/o/private.git "$1"' > "$tmp/repos.sh"
  env -i PATH="$bin" HOME="$tmp" LOG="$tmp/log" "$(command -v script)" -qec \
    "bash -euo pipefail $tmp/repos.sh $tmp/clone2" /dev/null > "$tmp/out" 2>&1; rc=$?
  check "gh's login refused on a terminal: git retries with a token typed by hand" \
    bash -c "[ $rc = 0 ] && grep -q 'credential.helper=cache --timeout=900 clone' '$tmp/log'"
  # The same for an update of a copy already there.
  mkdir -p "$tmp/copy/.git"; : > "$tmp/log"
  printf '%s\n' "gh_logged_in=1; HERE=/x; $step_repos" 'get_repo https://github.com/o/private.git "$1"' > "$tmp/repos.sh"
  env -i PATH="$bin" HOME="$tmp" LOG="$tmp/log" "$(command -v script)" -qec \
    "bash -euo pipefail $tmp/repos.sh $tmp/copy" /dev/null > "$tmp/out" 2>&1
  check "...and so does an update of a copy already there" \
    grep -q 'credential.helper=cache --timeout=900 -C .* pull --ff-only' "$tmp/log"
  rm -f "$bin/git"
fi

[ "$fail" = 0 ] || { echo "--- output of the last run:"; cat "$tmp/out"; echo "--- log:"; cat "$tmp/log"; }
exit $fail
