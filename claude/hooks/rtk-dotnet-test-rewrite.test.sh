#!/usr/bin/env bash
# Runnable check for rtk-dotnet-test-rewrite (stdin command -> stdout command).
set -u
here=$(cd "$(dirname "$0")" && pwd)
fail=0

run() {  # $1 = command in, $2 = expected out (same as $1 = left alone)
  local got
  got=$(printf '%s' "$1" | "$here/rtk-dotnet-test-rewrite"; printf x); got=${got%x}
  if [[ "$got" == "$2" ]]; then echo "ok   ${1//$'\n'/⏎}"; else echo "FAIL ${1//$'\n'/⏎}: expected '$2', got '$got'"; fail=1; fi
}
same() { run "$1" "$1"; }

# segment starts
run 'dotnet test'                                'rtk dotnet test'
run 'dotnet test --project x 2>&1 | tail -5'    'rtk dotnet test --project x 2>&1 | tail -5'
run 'cd tests && dotnet test'                    'cd tests && rtk dotnet test'
run 'a || dotnet test'                           'a || rtk dotnet test'
run 'a;dotnet test'                              'a;rtk dotnet test'
run 'a | dotnet test'                            'a | rtk dotnet test'
run 'a & dotnet test'                            'a & rtk dotnet test'
run $'make\ndotnet test'                         $'make\nrtk dotnet test'
run '(cd x && dotnet test)'                      '(cd x && rtk dotnet test)'
run 'echo $(dotnet test)'                        'echo $(rtk dotnet test)'
run 'dotnet  test'                               'rtk dotnet  test'
run $'dotnet test\n'                             $'rtk dotnet test\n'
# prefixes
run 'timeout 900 dotnet test'                    'timeout 900 rtk dotnet test'
run 'timeout -k 5 --foreground 900 dotnet test'  'timeout -k 5 --foreground 900 rtk dotnet test'
run 'FOO=1 dotnet test'                          'FOO=1 rtk dotnet test'
run 'X="$(cat prod.conn)" dotnet test --project p'  'X="$(cat prod.conn)" rtk dotnet test --project p'
run 'X=$(cat a b) timeout 300 dotnet test'       'X=$(cat a b) timeout 300 rtk dotnet test'
# line continuations are blanks
run $'make && \\\n  dotnet test'                 $'make && \\\n  rtk dotnet test'
run $'FOO=1 \\\n  dotnet test'                   $'FOO=1 \\\n  rtk dotnet test'
# reserved words and `time` in front of the command
run 'for p in a b; do dotnet test --project $p; done'  'for p in a b; do rtk dotnet test --project $p; done'
run 'if x; then dotnet test; else dotnet test; fi'     'if x; then rtk dotnet test; else rtk dotnet test; fi'
run 'while dotnet test; do :; done'              'while rtk dotnet test; do :; done'
run '{ dotnet test; }'                           '{ rtk dotnet test; }'
run '! dotnet test'                              '! rtk dotnet test'
run 'time dotnet test'                           'time rtk dotnet test'
run 'time -p dotnet test'                        'time -p rtk dotnet test'
# arithmetic is not a heredoc
run $'echo $((1<<2))\ndotnet test'               $'echo $((1<<2))\nrtk dotnet test'
same 'echo $((x<<y))'
run 'N=$((1<<2)) dotnet test'                    'N=$((1<<2)) rtk dotnet test'
# a function body opens a command (seen in real traffic: run(){ dotnet test ...; })
run 'run(){ dotnet test --project x; }; run'     'run(){ rtk dotnet test --project x; }; run'
run 'f() { dotnet test; }'                       'f() { rtk dotnet test; }'
same 'echo { dotnet test'
# left alone: heredoc bodies, quotes, escapes, comments, near misses
same $'cat > r.sh <<EOF\ndotnet test --project x\nEOF'
same $'cat > r.sh <<\'EOF\'\ndotnet test\nEOF'
same $'cat <<-EOF\n\tdotnet test\n\tEOF'
run  $'cat <<EOF\nx\nEOF\ndotnet test'          $'cat <<EOF\nx\nEOF\nrtk dotnet test'
run  'cat <<< "x"; dotnet test'                  'cat <<< "x"; rtk dotnet test'
same 'git commit -m "wire it; dotnet test now"'
same "echo 'a | dotnet test'"
same 'echo a\; dotnet test'
same 'echo hi # ; dotnet test'
same 'rtk dotnet test'
same 'dotnet tests'
same 'dotnet test-x'
same 'echo dotnet test'
same 'git status'

exit $fail
