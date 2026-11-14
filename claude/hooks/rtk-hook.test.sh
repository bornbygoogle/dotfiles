#!/usr/bin/env bash
# Runnable check for rtk-hook. Feeds PreToolUse payloads; needs rtk and jq on PATH.
set -u
here=$(cd "$(dirname "$0")" && pwd)
fail=0

run() {  # $1 = command in, $2 = expected rewritten command ("" = no rewrite)
  local out got
  out=$(jq -nc --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c,timeout:400000}}' | "$here/rtk-hook")
  got=$(jq -r '.hookSpecificOutput.updatedInput.command // ""' <<<"${out:-{\}}")
  if [[ "$got" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: expected '$2', got '$got'"; fail=1; fi
  if [[ -n "$2" ]]; then
    [[ $(jq -r '.hookSpecificOutput.hookEventName' <<<"$out") == PreToolUse ]] || { echo "FAIL $1: hookEventName"; fail=1; }
    [[ $(jq -r '.hookSpecificOutput.updatedInput.timeout' <<<"$out") == 400000 ]] || { echo "FAIL $1: timeout dropped"; fail=1; }
  fi
}

run 'dotnet test --project x.csproj'          'rtk dotnet test --project x.csproj'
run 'dotnet test'                             'rtk dotnet test'
run 'cd tests && dotnet test'                 'cd tests && rtk dotnet test'
run 'dotnet test --project x 2>&1 | tail -5'  'rtk dotnet test --project x 2>&1 | tail -5'
run 'git status && dotnet test'               'rtk git status && rtk dotnet test'
run 'make x;dotnet test'                      'rtk make x; rtk dotnet test'
run 'rtk dotnet test'                         ''
run 'dotnet tests'                            ''
run 'echo hi'                                 ''
run 'git status'                              'rtk git status'
run 'dotnet build'                            'rtk dotnet build'
# The scanner's own cases live in rtk-dotnet-test-rewrite.test.sh; these prove the wrapper uses it.
run $'cat > r.sh <<EOF\ndotnet test\nEOF'    ''
run 'git commit -m "wire it; dotnet test now"' 'rtk git commit -m "wire it; dotnet test now"'
run 'timeout 900 dotnet test'                 'timeout 900 rtk dotnet test'

# RTK names the binary (agentics passes its absolute path); a bare `rtk` on PATH must not be used.
out=$(jq -nc '{tool_name:"Bash",tool_input:{command:"git status"}}' | RTK=/bin/false "$here/rtk-hook")
[[ -z "$out" ]] && echo "ok   RTK is honoured" || { echo "FAIL RTK ignored: $out"; fail=1; }
out=$(jq -nc '{tool_name:"Bash",tool_input:{command:"dotnet test"}}' | RTK=/bin/false "$here/rtk-hook")
[[ $(jq -r '.hookSpecificOutput.updatedInput.command' <<<"$out") == "rtk dotnet test" ]] \
  && echo "ok   dotnet test without rtk's own rewrite" || { echo "FAIL dotnet test under RTK: $out"; fail=1; }

# A scanner that cannot run must leave rtk's answer alone, never blank the command.
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cp "$here/rtk-hook" "$tmp/"
out=$(jq -nc '{tool_name:"Bash",tool_input:{command:"git status && dotnet test"}}' | "$tmp/rtk-hook" 2>/dev/null)
[[ $(jq -r '.hookSpecificOutput.updatedInput.command' <<<"$out") == "rtk git status && dotnet test" ]] \
  && echo "ok   missing scanner falls back to rtk" || { echo "FAIL missing scanner: $out"; fail=1; }

exit $fail
