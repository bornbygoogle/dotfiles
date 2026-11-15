#!/usr/bin/env bash
# Runnable check for agentics-profiles.sh, on throwaway folders: no network, no model, no real kernel.
set -u
here=$(cd "$(dirname "$0")" && pwd)
fail=0
check() {  # $1 = label, then the test command
  local label=$1; shift
  if "$@"; then echo "ok   $label"; else echo "FAIL $label"; fail=1; fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A profile for "app" and "notes", none for "other". "notes" is a plain folder, not a repository of its own,
# though the workspaces folder above it is one: git answers "inside a work tree" for it all the same.
mkdir -p "$tmp/profiles" "$tmp/ws/notes" "$tmp/home/.claude"
printf 'name: app\n' > "$tmp/profiles/app.yaml"
printf 'name: notes\n' > "$tmp/profiles/notes.yaml"
for r in . app other; do git init -q "$tmp/ws/$r"; done
# The repo folder is shared with the host, which may have its own agentics.yaml with host paths.
printf 'name: app on the host\n' > "$tmp/ws/app/agentics.yaml"
# A kernel stand-in that records how it was called.
mkdir -p "$tmp/kernel"
printf '#!/bin/sh\necho "$@" >> "%s/kernel.log"\n' "$tmp" > "$tmp/kernel/agentics"
chmod +x "$tmp/kernel/agentics"
# Existing settings that must survive: the rtk hook written by an earlier step.
echo '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"~/.claude/hooks/rtk-hook"}]}]}}' \
  > "$tmp/home/.claude/settings.json"

run() {
  HOME="$tmp/home" AGENTICS_DIR="$tmp/kernel" AGENTICS_PROFILES="$tmp/profiles" \
    bash "$here/agentics-profiles.sh" "$tmp/ws" > "$tmp/out.log" 2>&1
}
settings="$tmp/home/.claude/settings.json"
profile_in_repo="$tmp/ws/app/agentics.container.yaml"

settings_before=$(cat "$settings")
check "the script runs" run
run  # second run: nothing may be added twice
check "the Claude settings are left alone (the commit lock is claude-ask-rules.sh)" test "$(cat "$settings")" = "$settings_before"

check "the profile is copied into the repo it names, under the container name" cmp -s "$tmp/profiles/app.yaml" "$profile_in_repo"
check "the host's own agentics.yaml is left untouched" test "$(cat "$tmp/ws/app/agentics.yaml")" = "name: app on the host"
check "a repo without a profile gets none" test ! -e "$tmp/ws/other/agentics.container.yaml"
check "a folder that is not a git repo is left alone" test -z "$(ls -A "$tmp/ws/notes")"
check "agentics.container.yaml is excluded once" test "$(grep -cx 'agentics.container.yaml' "$tmp/ws/app/.git/info/exclude")" = 1
# A profile made by hand in a repo with no dotfiles profile must not show up as untracked either.
check "a repo without a profile still excludes agentics.container.yaml, once" \
  test "$(grep -cx 'agentics.container.yaml' "$tmp/ws/other/.git/info/exclude" 2> /dev/null)" = 1
check ".agentics/ is excluded once" test "$(grep -cx '.agentics/' "$tmp/ws/app/.git/info/exclude")" = 1
# What a hand-made profile writes in the repo: the demos' rules folder, `agentics init`'s starter knowledge base and reports.
for p in .agentics/ .agentic/ agentic-reports/; do
  check "a repo without a profile excludes $p, once" \
    test "$(grep -cxF "$p" "$tmp/ws/other/.git/info/exclude" 2> /dev/null)" = 1
done
check "git lists no container file as untracked" test -z "$(git -C "$tmp/ws/app" status --porcelain -- agentics.container.yaml .agentics)"
check "the kernel ran init on the container profile" grep -qx "init --project $profile_in_repo" "$tmp/kernel.log"
check "the kernel ran check on the container profile" grep -qx "check --project $profile_in_repo" "$tmp/kernel.log"
check "the kernel never ran for the repo without a profile" bash -c "! grep -q '/other/' '$tmp/kernel.log'"

# A local edit to the profile in the repo is never overwritten.
echo "# my local edit" >> "$profile_in_repo"
run
check "a profile already in the repo is not overwritten" grep -q "my local edit" "$profile_in_repo"
check "a repo copy that differs from the dotfiles profile is reported" \
  grep -q "differs from $tmp/profiles/app.yaml" "$tmp/out.log"

# An exclude file whose last line has no newline: the appended patterns still get lines of their own.
printf '*.log' > "$tmp/ws/app/.git/info/exclude"
run
check "a last exclude line without newline is kept apart" grep -qx '\*\.log' "$tmp/ws/app/.git/info/exclude"
check "the profile is excluded after such a line" grep -qx 'agentics.container.yaml' "$tmp/ws/app/.git/info/exclude"

# Container paths: /home/vscode in a profile becomes this container's $HOME when it is copied.
printf 'name: homed\nknowledge_base: /home/vscode/secondbrain\n' > "$tmp/profiles/homed.yaml"
git init -q "$tmp/ws/homed"
# A repo git cannot read (a host worktree whose .git points to a host path) is skipped with a warning,
# and the repos after it are still set up. "broken" comes before "homed" in both loops.
mkdir -p "$tmp/ws/broken" && echo "gitdir: /nowhere" > "$tmp/ws/broken/.git"
printf 'name: broken\n' > "$tmp/profiles/broken.yaml"
run; rc=$?
check "a repo git cannot read does not stop the script" test "$rc" = 0
check "a repo git cannot read is reported" grep -q "skipped $tmp/ws/broken" "$tmp/out.log"
check "the repo after it is still set up, with \$HOME in its paths" \
  grep -qx "knowledge_base: $tmp/home/secondbrain" "$tmp/ws/homed/agentics.container.yaml"
run
check "a substituted copy is not reported as a local edit" bash -c "! grep -q 'homed.*differs' '$tmp/out.log'"
rm -rf "$tmp/ws/broken" "$tmp/profiles/broken.yaml"

# A kernel that fails on one repo ("app", first in the loop): the repos after it are still set up,
# and the script still fails at the end, naming the repo.
mkdir -p "$tmp/badkernel"
printf '#!/bin/sh\necho "$@" >> "%s/badkernel.log"\ncase "$*" in */app/*) exit 1 ;; esac\n' "$tmp" > "$tmp/badkernel/agentics"
chmod +x "$tmp/badkernel/agentics"
HOME="$tmp/home" AGENTICS_DIR="$tmp/badkernel" AGENTICS_PROFILES="$tmp/profiles" \
  bash "$here/agentics-profiles.sh" "$tmp/ws" > "$tmp/bad.log" 2>&1; rc=$?
check "a kernel failure on one repo makes the script fail" test "$rc" != 0
check "a kernel failure on one repo does not stop the next" grep -qx "check --project $tmp/ws/homed/agentics.container.yaml" "$tmp/badkernel.log"
check "a kernel failure names its repo" grep -q "failed.*$tmp/ws/app" "$tmp/bad.log"

# A .NET repo with no dotfiles profile gets one generated, learned from the hand-written ones. Fakes: the
# files the generator reads, nothing that builds.
dotnet_repo() {  # dotnet_repo <name> <solution file> [path of a csproj, ":tc" after it for a Testcontainers one]...
  local repo="$tmp/ws/$1" p; shift
  git init -q "$repo"; touch "$repo/$1"; shift
  for p in "$@"; do
    mkdir -p "$repo/$(dirname "${p%:tc}")"
    case "$p" in
      *:tc) echo '<Project><ItemGroup><PackageReference Include="Testcontainers.PostgreSql" /></ItemGroup></Project>' ;;
      *) echo '<Project />' ;;
    esac > "$repo/${p%:tc}"
    # A project named *Tests or *Test holds a test; any other name holds none unless a fixture adds one.
    case "${p%:tc}" in *Tests.csproj | *Test.csproj) echo '[Fact] public void T() {}' > "$(dirname "$repo/${p%:tc}")/T.cs" ;; esac
  done
}
mtp_runner='{ "test": { "runner": "Microsoft.Testing.Platform" } }'
mtp_xunit() {  # mtp_xunit <repo>: MTP runner, xunit v3 declared centrally, as in erp-socle
  echo "$mtp_runner" > "$tmp/ws/$1/global.json"
  echo '<Project><ItemGroup><PackageVersion Include="xunit.v3" Version="3.0.0" /></ItemGroup></Project>' \
    > "$tmp/ws/$1/Directory.Packages.props"
}
dotnet_repo mtp1 Mtp1.slnx src/A/A.csproj tests/Mtp1.UnitTests/Mtp1.UnitTests.csproj \
  tests/Mtp1.IntegrationTests/Mtp1.IntegrationTests.csproj:tc
mtp_xunit mtp1
dotnet_repo mtp2 Mtp2.slnx src/A/A.csproj tests/Mtp2.A.IntegrationTests/Mtp2.A.IntegrationTests.csproj:tc \
  tests/Mtp2.B.IntegrationTests/Mtp2.B.IntegrationTests.csproj:tc tests/Mtp2.UnitTests/Mtp2.UnitTests.csproj
mtp_xunit mtp2
# No src/ (system-trade-2's layout): one glob per project folder, the test project left out.
dotnet_repo vst Vst.sln Core/Core.csproj Api/Api.csproj Vst.Tests/Vst.Tests.csproj
echo '[Trait("Category", "Integration")] public class T {}' > "$tmp/ws/vst/Vst.Tests/T.cs"
dotnet_repo plain Plain.sln src/A/A.csproj tests/Plain.Tests/Plain.Tests.csproj
touch "$tmp/ws/app/App.slnx"  # "app" has a dotfiles profile: it must win
run
gen() { grep -qxF "$2" "$tmp/ws/$1/agentics.container.yaml"; }  # gen <repo> <exact line of its generated profile>
check "a .NET repo without a profile gets one" gen mtp1 'name: "mtp1"'
check "generated: src/ sources" gen mtp1 '    - "src/**/*.cs"'
check "generated: migrations excluded" gen mtp1 '    - "**/Migrations/**"'
check "generated: the whole suite" gen mtp1 '  authoritative: "dotnet test"'
check "generated: mtp parser from global.json" gen mtp1 "  parser: mtp"
check "generated: the Testcontainers project left out of the fast suite" \
  gen mtp1 '  fast: "dotnet test --solution \"Mtp1.slnx\" --filter-not-namespace \"Mtp1.IntegrationTests\" --filter-not-namespace \"Mtp1.IntegrationTests.*\" --ignore-exit-code 8"'
check "generated: \$HOME's secondbrain" gen mtp1 "knowledge_base: \"$tmp/home/secondbrain\""
check "generated: reports outside the repo" gen mtp1 "reports: \"$tmp/home/agentics-reports/mtp1\""
check "generated: every Testcontainers project left out" \
  gen mtp2 '  fast: "dotnet test --solution \"Mtp2.slnx\" --filter-not-namespace \"Mtp2.A.IntegrationTests\" --filter-not-namespace \"Mtp2.A.IntegrationTests.*\" --filter-not-namespace \"Mtp2.B.IntegrationTests\" --filter-not-namespace \"Mtp2.B.IntegrationTests.*\" --ignore-exit-code 8"'
check "generated without src/: one glob per project folder" bash -c "grep -qxF '    - \"Api/**/*.cs\"' '$tmp/ws/vst/agentics.container.yaml' && grep -qxF '    - \"Core/**/*.cs\"' '$tmp/ws/vst/agentics.container.yaml'"
check "generated without src/: the test project is not a source" bash -c "! grep -q 'Vst.Tests' '$tmp/ws/vst/agentics.container.yaml'"
check "generated: xunit parser without an mtp global.json" gen vst "  parser: xunit"
check "generated: the Integration trait left out of the fast suite" gen vst '  fast: "dotnet test --filter \"Category!=Integration\""'
# The real kernel's `check` refuses a profile without tests.fast (agentics:668-675): nothing to leave out, the
# whole suite, as Shopify_2's hand-written profile does.
check "generated: the whole suite as fast suite when nothing can be left out" gen plain '  fast: "dotnet test"'
check "every generated profile has a fast suite (the kernel refuses one without)" bash -c \
  "for f in '$tmp'/ws/*/agentics.container.yaml; do head -1 \"\$f\" | grep -q '^# Generated' || continue; grep -q '^  fast: ' \"\$f\" || exit 1; done"
check "a dotfiles profile wins over a generated one" bash -c "! grep -q authoritative '$profile_in_repo'"
check "the kernel ran init on a generated profile" grep -qx "init --project $tmp/ws/mtp1/agentics.container.yaml" "$tmp/kernel.log"
check "a generated profile is reported" grep -q "generated $tmp/ws/mtp1/agentics.container.yaml" "$tmp/out.log"
echo "# my local edit" >> "$tmp/ws/mtp1/agentics.container.yaml"
run
check "a generated profile is not regenerated over a local edit" grep -q "my local edit" "$tmp/ws/mtp1/agentics.container.yaml"
# A later run still sends a generated profile to the kernel: a check that failed once must keep failing.
: > "$tmp/kernel.log"
run
check "a generated profile goes through the kernel again on a later run" \
  grep -qx "check --project $tmp/ws/mtp1/agentics.container.yaml" "$tmp/kernel.log"
rm -rf "$tmp/ws/mtp1" "$tmp/ws/mtp2" "$tmp/ws/vst" "$tmp/ws/plain" "$tmp/ws/app/App.slnx"

# What the generator must refuse, or get right, beyond the five repos it was learned from.
dotnet_repo twosln Two.sln Two.slnx src/A/A.csproj          # `dotnet test` alone fails: which solution?
dotnet_repo nosrc E.sln Tests/E.Tests.csproj                 # nothing but tests: no source to glob
dotnet_repo names Names.sln Latest/Latest.csproj TestUnit/TestUnit.csproj Api.IntegrationTests/Api.IntegrationTests.csproj
# Docker through a shared test project (its reference spread over lines, a Condition first), or through the
# nearest Directory.Build.props, the one MSBuild imports. A comment is not a reference.
dotnet_repo chain Chain.slnx src/A/A.csproj tests/Chain.Shared/Chain.Shared.csproj:tc \
  tests/Chain.Integration/Chain.Integration.csproj tests/Chain.Docs/Chain.Docs.csproj tests/Db/Db.Tests.csproj \
  tests/Db/Inner/Inner.Tests.csproj tests/Chain.Unit.Tests/Chain.Unit.Tests.csproj
mtp_xunit chain
printf '<Project><ItemGroup>\n  <ProjectReference Condition="true"\n    Include="..\\Chain.Shared\\Chain.Shared.csproj" />\n</ItemGroup></Project>\n' \
  > "$tmp/ws/chain/tests/Chain.Integration/Chain.Integration.csproj"
printf '<Project>\n<!--\n<PackageReference Include="Testcontainers" />\n-->\n</Project>\n' \
  > "$tmp/ws/chain/tests/Chain.Docs/Chain.Docs.csproj"
echo '<Project><ItemGroup><PackageReference Include="Testcontainers" /></ItemGroup></Project>' \
  > "$tmp/ws/chain/tests/Db/Directory.Build.props"
echo '<Project />' > "$tmp/ws/chain/tests/Db/Inner/Directory.Build.props"
echo '<Project><!-- <PackageReference Include="Testcontainers" /> --></Project>' > "$tmp/ws/chain/Directory.Build.props"
# VSTest can only filter by "contains": a Testcontainers project leaves no safe fast suite. The trait alone can,
# as the repo spells it.
dotnet_repo vdock Vdock.sln Core/Core.csproj Vdock.IntegrationTests/Vdock.IntegrationTests.csproj:tc \
  Vdock.Tests/Vdock.Tests.csproj
echo '[Trait("Category","integration")] public class T {}' > "$tmp/ws/vdock/Vdock.Tests/T.cs"
dotnet_repo vtrait Vtrait.sln Core/Core.csproj Vtrait.Tests/Vtrait.Tests.csproj
echo '[Trait( "Category" , "integration" )] public class T {}' > "$tmp/ws/vtrait/Vtrait.Tests/T.cs"
# Every test project needs Docker: a fast suite would run zero tests and pass.
dotnet_repo alldock Alldock.slnx src/A/A.csproj tests/Fixture/Fixture.csproj:tc tests/X.Tests/X.Tests.csproj \
  tests/Y.Tests/Y.Tests.csproj
mtp_xunit alldock
for p in X Y; do
  echo '<Project><ItemGroup><ProjectReference Include="../Fixture/Fixture.csproj" /></ItemGroup></Project>' \
    > "$tmp/ws/alldock/tests/$p.Tests/$p.Tests.csproj"
done
# MTP without xunit v3 (MSTest, NUnit, TUnit): --filter-not-namespace is xunit's option.
dotnet_repo mstest Mstest.slnx src/A/A.csproj tests/M.IntegrationTests/M.IntegrationTests.csproj:tc tests/M.Tests/M.Tests.csproj
echo "$mtp_runner" > "$tmp/ws/mstest/global.json"
# global.json as the SDK reads it: comments and a trailing comma.
dotnet_repo jsonc Jsonc.slnx src/A/A.csproj tests/J.Tests/J.Tests.csproj
mtp_xunit jsonc
printf '{\n  // the test runner\n  "test": { "runner": "Microsoft.Testing.Platform", },\n}\n' > "$tmp/ws/jsonc/global.json"
# A grouping folder holding a project and its tests: the project's own folder is the glob, not the group.
dotnet_repo services Services.sln Services/Api/Api.csproj Services/Api.Tests/Api.Tests.csproj
# src/ with tests only: no source.
dotnet_repo srctests Srctests.sln src/X.Tests/X.Tests.csproj
# A repo the generator cannot write to: a warning, and the repos after it are still set up.
dotnet_repo readonly Readonly.sln Core/Core.csproj
chmod a-w "$tmp/ws/readonly"
# A Docker project whose name is not a test name is still a test project, never a source.
dotnet_repo integ Integ.slnx src/A/A.csproj tests/Foo.Integration/Foo.Integration.csproj:tc tests/Foo.Tests/Foo.Tests.csproj
mtp_xunit integ
dotnet_repo integ2 Integ2.sln Core/Core.csproj Foo.Integration/Foo.Integration.csproj:tc Foo.Tests/Foo.Tests.csproj
# Tests under src/, and code outside it: one glob per code project, as without src/.
dotnet_repo mixed Mixed.sln src/A/A.csproj src/A.Tests/A.Tests.csproj tools/Cli/Cli.csproj
# Spaces in project names: one name each, and the namespace MSBuild derives (a space becomes _).
dotnet_repo spaced Spaced.slnx src/A/A.csproj "tests/My Db.IntegrationTests/My Db.IntegrationTests.csproj:tc" \
  tests/Uses.Db.Tests/Uses.Db.Tests.csproj tests/U.Tests/U.Tests.csproj
mtp_xunit spaced
echo '<Project><ItemGroup><ProjectReference Include="..\My Db.IntegrationTests\My Db.IntegrationTests.csproj" /></ItemGroup></Project>' \
  > "$tmp/ws/spaced/tests/Uses.Db.Tests/Uses.Db.Tests.csproj"
# MTP switched on by the MSBuild property (.NET 9), not by global.json.
dotnet_repo tpds Tpds.sln src/A/A.csproj tests/T.Tests/T.Tests.csproj
echo '<Project><PropertyGroup><TestingPlatformDotnetTestSupport>true</TestingPlatformDotnetTestSupport></PropertyGroup></Project>' \
  > "$tmp/ws/tpds/Directory.Build.props"
echo '[Trait("Category", "Integration")] public class T {}' > "$tmp/ws/tpds/tests/T.Tests/T.cs"
# A test-named helper with no test: leaving the Docker project out would leave zero tests.
dotnet_repo helper Helper.slnx src/A/A.csproj tests/Foo.IntegrationTests/Foo.IntegrationTests.csproj:tc \
  tests/Foo.Tests.Common/Foo.Tests.Common.csproj
mtp_xunit helper
# xunit v3 next to MSTest: the MSTest app refuses --filter-not-namespace.
dotnet_repo mixedfw Mixedfw.slnx src/A/A.csproj tests/M.IntegrationTests/M.IntegrationTests.csproj:tc tests/M.Tests/M.Tests.csproj
mtp_xunit mixedfw
echo '<Project><ItemGroup><PackageReference Include="MSTest" /></ItemGroup></Project>' > "$tmp/ws/mixedfw/tests/M.Tests/M.Tests.csproj"
# A project without Docker inside the Docker project's namespace: "Api.Tests.*" would take it too.
dotnet_repo nested Nested.slnx src/A/A.csproj tests/Api.Tests/Api.Tests.csproj:tc tests/Api.Tests.Unit/Api.Tests.Unit.csproj
mtp_xunit nested
echo '[Fact] public void T() {}' > "$tmp/ws/nested/tests/Api.Tests.Unit/T.cs"
# Test projects inside a source glob: a root project, a test folder inside a project's folder, tests in src/.
dotnet_repo rootapp Rootapp.sln App.csproj tests/X.Tests/X.Tests.csproj
dotnet_repo nestapi Nestapi.sln Api/Api.csproj Api/Tests/Api.Tests.csproj
dotnet_repo srcmix Srcmix.sln src/A/A.csproj src/A.Tests/A.Tests.csproj
# A Testcontainers reference early in a file bigger than a pipe buffer.
dotnet_repo big Big.slnx src/A/A.csproj tests/Big.IntegrationTests/Big.IntegrationTests.csproj tests/B.Tests/B.Tests.csproj
mtp_xunit big
{ echo '<Project><ItemGroup><PackageReference Include="Testcontainers" /></ItemGroup>'
  for i in $(seq 4000); do echo "<PropertyGroup><Filler$i>some text to pass 64 KB</Filler$i></PropertyGroup>"; done
  echo '</Project>'; } > "$tmp/ws/big/tests/Big.IntegrationTests/Big.IntegrationTests.csproj"
# The package's older id.
dotnet_repo legacy Legacy.slnx src/A/A.csproj tests/L.IntegrationTests/L.IntegrationTests.csproj tests/L.Tests/L.Tests.csproj
mtp_xunit legacy
echo '<Project><ItemGroup><PackageReference Include="DotNet.Testcontainers" /></ItemGroup></Project>' \
  > "$tmp/ws/legacy/tests/L.IntegrationTests/L.IntegrationTests.csproj"
# VSTest, the trait spelled two ways: both left out, in a fixed order.
dotnet_repo vmix Vmix.sln Core/Core.csproj Vmix.Tests/Vmix.Tests.csproj
echo '[Trait("Category", "integration")] public class A {}' > "$tmp/ws/vmix/Vmix.Tests/A.cs"
echo '[Trait("Category", "Integration")] public class B {}' > "$tmp/ws/vmix/Vmix.Tests/B.cs"
# A Docker project nested inside a test-named project that has no test of its own: nothing runs without Docker.
dotnet_repo nesteddb Nesteddb.slnx src/A/A.csproj tests/Db.Tests/Db.Tests.csproj \
  tests/Db.Tests/Db.IntegrationTests/Db.IntegrationTests.csproj:tc
mtp_xunit nesteddb
rm "$tmp/ws/nesteddb/tests/Db.Tests/T.cs"
# Tests in a subfolder of their project still belong to it.
dotnet_repo subdir Subdir.slnx src/A/A.csproj tests/S.IntegrationTests/S.IntegrationTests.csproj:tc \
  tests/S.UnitTests/S.UnitTests.csproj
mtp_xunit subdir
mkdir -p "$tmp/ws/subdir/tests/S.UnitTests/Users" && mv "$tmp/ws/subdir/tests/S.UnitTests/T.cs" "$tmp/ws/subdir/tests/S.UnitTests/Users/"
# Test helpers by name: *Tests.<Something>, *.Testing.
dotnet_repo helpers Helpers.sln Core/Core.csproj Fix.IntegrationTests.Fixtures/Fix.IntegrationTests.Fixtures.csproj \
  Foo.Testing/Foo.Testing.csproj
# A Testcontainers reference behind a Condition in Directory.Build.props: which projects get it is not knowable here.
dotnet_repo condprops Condprops.slnx src/A/A.csproj tests/G.IntegrationTests/G.IntegrationTests.csproj \
  tests/G.UnitTests/G.UnitTests.csproj
mtp_xunit condprops
echo '<Project><ItemGroup Condition="$(MSBuildProjectName.EndsWith(`IntegrationTests`))"><PackageReference Include="Testcontainers" /></ItemGroup></Project>' \
  > "$tmp/ws/condprops/tests/Directory.Build.props"
# Two projects with one name in two folders, only one with Docker: told apart by path.
dotnet_repo samename Samename.slnx src/A/A.csproj tests/Unit/Tests.csproj tests/Integration/Tests.csproj:tc
mtp_xunit samename
# A solution name with a character the kernel refuses in a command.
dotnet_repo badname 'R;D.sln' src/A/A.csproj
# VSTest: the trait key spelled otherwise than Category is not what `Category!=` filters.
dotnet_repo vcase Vcase.sln Core/Core.csproj Vcase.Tests/Vcase.Tests.csproj
echo '[Trait("category", "Integration")] public class A {}' > "$tmp/ws/vcase/Vcase.Tests/A.cs"
# A copy of the repo in a hidden folder (Claude Code's worktrees) is not a project of it.
dotnet_repo worktree Worktree.sln src/A/A.csproj .claude/worktrees/f/src/A/A.csproj
# MTP through the .NET 9 switch, with a Docker project: the whole suite, and why.
dotnet_repo tpdsdock Tpdsdock.sln src/A/A.csproj tests/I.IntegrationTests/I.IntegrationTests.csproj:tc tests/I.Tests/I.Tests.csproj
echo '<Project><PropertyGroup><TestingPlatformDotnetTestSupport>true</TestingPlatformDotnetTestSupport></PropertyGroup></Project>' \
  > "$tmp/ws/tpdsdock/Directory.Build.props"
# A Condition on something else in the Directory.Build.props that brings Testcontainers in.
dotnet_repo unrelcond Unrelcond.slnx src/A/A.csproj tests/X.IntegrationTests/X.IntegrationTests.csproj tests/X.Tests/X.Tests.csproj
mtp_xunit unrelcond
printf '%s\n' '<Project><PropertyGroup Condition="$(Configuration) == Debug"><Optimize>false</Optimize></PropertyGroup>' \
  '<ItemGroup><PackageReference Include="Testcontainers" /></ItemGroup></Project>' \
  > "$tmp/ws/unrelcond/tests/X.IntegrationTests/Directory.Build.props"
# A quote in a project folder would break the YAML string it goes in.
dotnet_repo quotepath Quotepath.sln 'src/B"q/B.csproj'
# The namespace a project really has: its RootNamespace; a segment starting with a digit; one set for many projects.
dotnet_repo rootns Rootns.slnx src/A/A.csproj tests/Db.IntegrationTests/Db.IntegrationTests.csproj tests/Db.Tests/Db.Tests.csproj
mtp_xunit rootns
echo '<Project><PropertyGroup><RootNamespace>Company.Db.Tests.Integration</RootNamespace></PropertyGroup><ItemGroup><PackageReference Include="Testcontainers" /></ItemGroup></Project>' \
  > "$tmp/ws/rootns/tests/Db.IntegrationTests/Db.IntegrationTests.csproj"
dotnet_repo digit Digit.slnx src/A/A.csproj tests/2FA.IntegrationTests/2FA.IntegrationTests.csproj:tc tests/D.Tests/D.Tests.csproj
mtp_xunit digit
dotnet_repo propns Propns.slnx src/A/A.csproj tests/P.IntegrationTests/P.IntegrationTests.csproj:tc tests/P.Tests/P.Tests.csproj
mtp_xunit propns
echo '<Project><PropertyGroup><RootNamespace>Company.$(MSBuildProjectName)</RootNamespace></PropertyGroup></Project>' \
  > "$tmp/ws/propns/tests/Directory.Build.props"
# A Directory.Build.props that imports the one above it: the Docker reference comes through the import.
dotnet_repo importprops Importprops.slnx src/A/A.csproj tests/I.IntegrationTests/I.IntegrationTests.csproj \
  tests/I.UnitTests/I.UnitTests.csproj
mtp_xunit importprops
echo '<Project><ItemGroup><PackageReference Include="Testcontainers" /></ItemGroup></Project>' > "$tmp/ws/importprops/tests/Directory.Build.props"
echo "<Project><Import Project=\"\$([MSBuild]::GetPathOfFileAbove('Directory.Build.props', '\$(MSBuildThisFileDirectory)../'))\" /></Project>" \
  > "$tmp/ws/importprops/tests/I.IntegrationTests/Directory.Build.props"
echo '<Project />' > "$tmp/ws/importprops/tests/I.UnitTests/Directory.Build.props"
# A ProjectReference through an MSBuild property cannot be followed here.
dotnet_repo propref Propref.slnx src/A/A.csproj tests/P.Shared/P.Shared.csproj:tc \
  tests/P.IntegrationTests/P.IntegrationTests.csproj tests/P.Tests/P.Tests.csproj
mtp_xunit propref
echo '<Project><ItemGroup><ProjectReference Include="$(MSBuildThisFileDirectory)../P.Shared/P.Shared.csproj" /></ItemGroup></Project>' \
  > "$tmp/ws/propref/tests/P.IntegrationTests/P.IntegrationTests.csproj"
# A conditional Testcontainers reference in the root props: production code is still code.
dotnet_repo rootcond Rootcond.slnx src/A/A.csproj tests/R.IntegrationTests/R.IntegrationTests.csproj tests/R.Tests/R.Tests.csproj
mtp_xunit rootcond
echo '<Project><ItemGroup Condition="$(MSBuildProjectName.EndsWith(`IntegrationTests`))"><PackageReference Include="Testcontainers" /></ItemGroup></Project>' \
  > "$tmp/ws/rootcond/Directory.Build.props"
# A computed RootNamespace with no Docker anywhere: nothing to explain.
dotnet_repo nsnodock Nsnodock.slnx src/A/A.csproj tests/N.Tests/N.Tests.csproj
mtp_xunit nsnodock
echo '<Project><PropertyGroup><RootNamespace>Co.$(MSBuildProjectName)</RootNamespace></PropertyGroup></Project>' \
  > "$tmp/ws/nsnodock/Directory.Build.props"
# The same under MTP, which takes the solution through --solution only.
dotnet_repo rootmtp Rootmtp.slnx App.csproj tests/X.Tests/X.Tests.csproj
mtp_xunit rootmtp
# A test project by its tests, whatever its name.
dotnet_repo specs Specs.sln Core/Core.csproj Foo.Specs/Foo.Specs.csproj
echo '[Fact] public void T() {}' > "$tmp/ws/specs/Foo.Specs/T.cs"
# Two test projects in one folder inside a source glob.
dotnet_repo dupex Dupex.sln src/A/A.csproj src/A/Tests/A.Tests.csproj src/A/Tests/A.Tests.Common.csproj
# A profile made by hand in a repo with no dotfiles profile: left alone, never sent to the kernel.
git init -q "$tmp/ws/handmade" && printf 'name: handmade\n' > "$tmp/ws/handmade/agentics.container.yaml"
# Names YAML or a command line would misread.
dotnet_repo 'odd #2' 'My App.slnx' src/A/A.csproj tests/Odd.IntegrationTests/Odd.IntegrationTests.csproj:tc \
  tests/Odd.Tests/Odd.Tests.csproj
mtp_xunit 'odd #2'
# A repo with a dotfiles profile and a solution, and no repo copy yet: the dotfiles profile must be the one copied.
dotnet_repo handnet Handnet.slnx src/A/A.csproj
printf 'name: handnet\n' > "$tmp/profiles/handnet.yaml"
run; rc=$?
check "an unwritable repo does not stop the script" test "$rc" = 0
check "an unwritable repo is reported" grep -q "readonly.*cannot write" "$tmp/out.log"
check "an unwritable repo: the system's own reason is shown" grep -q "readonly.*Permission denied" "$tmp/out.log"
check "the repo after an unwritable one still gets its profile" test -e "$tmp/ws/services/agentics.container.yaml"
chmod u+w "$tmp/ws/readonly"
check "two solutions at the root: no profile generated" test ! -e "$tmp/ws/twosln/agentics.container.yaml"
check "two solutions at the root: said so" grep -q "twosln.*more than one solution" "$tmp/out.log"
check "no non-test project: no profile generated" test ! -e "$tmp/ws/nosrc/agentics.container.yaml"
check "a project named Latest is a source" gen names '    - "Latest/**/*.cs"'
check "TestUnit and *.IntegrationTests are test projects" bash -c "! grep -qE 'TestUnit|IntegrationTests/' '$tmp/ws/names/agentics.container.yaml'"
check "a test project using a Testcontainers project is left out too" gen chain \
  '  fast: "dotnet test --solution \"Chain.slnx\" --filter-not-namespace \"Chain.Integration\" --filter-not-namespace \"Chain.Integration.*\" --filter-not-namespace \"Chain.Shared\" --filter-not-namespace \"Chain.Shared.*\" --filter-not-namespace \"Db.Tests\" --filter-not-namespace \"Db.Tests.*\" --ignore-exit-code 8"'
check "VSTest with a Testcontainers project: the whole suite" gen vdock '  fast: "dotnet test"'
# "All the lookups are case insensitive" (learn.microsoft.com/dotnet/core/testing/selective-unit-tests): one clause.
check "VSTest: the trait left out, whatever its case" gen vtrait '  fast: "dotnet test --filter \"Category!=Integration\""'
check "every test project needs Docker: the whole suite" gen alldock '  fast: "dotnet test"'
check "MTP without xunit v3: the whole suite" gen mstest '  fast: "dotnet test"'
check "a Docker project with another name is left out" gen integ \
  '  fast: "dotnet test --solution \"Integ.slnx\" --filter-not-namespace \"Foo.Integration\" --filter-not-namespace \"Foo.Integration.*\" --ignore-exit-code 8"'
check "a Docker project with another name is not a source" bash -c "! grep -q 'Foo.Integration/' '$tmp/ws/integ2/agentics.container.yaml'"
check "tests under src/: no src/** glob" bash -c "! grep -qF '\"src/**/*.cs\"' '$tmp/ws/mixed/agentics.container.yaml'"
check "tests under src/: each code project its glob" bash -c \
  "grep -qxF '    - \"src/A/**/*.cs\"' '$tmp/ws/mixed/agentics.container.yaml' && grep -qxF '    - \"tools/Cli/**/*.cs\"' '$tmp/ws/mixed/agentics.container.yaml'"
check "a project name with a space: one namespace, as MSBuild derives it" gen spaced \
  '  fast: "dotnet test --solution \"Spaced.slnx\" --filter-not-namespace \"My_Db.IntegrationTests\" --filter-not-namespace \"My_Db.IntegrationTests.*\" --filter-not-namespace \"Uses.Db.Tests\" --filter-not-namespace \"Uses.Db.Tests.*\" --ignore-exit-code 8"'
check "MTP through TestingPlatformDotnetTestSupport: mtp parser" gen tpds "  parser: mtp"
check "MTP through TestingPlatformDotnetTestSupport: no VSTest filter" gen tpds '  fast: "dotnet test"'
check "a hand-made profile with no dotfiles one is left alone" test "$(cat "$tmp/ws/handmade/agentics.container.yaml")" = "name: handmade"
check "a hand-made profile with no dotfiles one never goes to the kernel" bash -c "! grep -q '/handmade/' '$tmp/kernel.log'"
check "a repo that is not .NET makes no noise" bash -c "! grep -q '/other' '$tmp/out.log'"
check "only a test-named helper would be left: the whole suite" gen helper '  fast: "dotnet test"'
check "xunit v3 next to MSTest: the whole suite" gen mixedfw '  fast: "dotnet test"'
check "a project inside the Docker project's namespace: the whole suite" gen nested '  fast: "dotnet test"'
check "a root project: every test folder excluded" bash -c \
  "grep -qxF '    - \"**/*.cs\"' '$tmp/ws/rootapp/agentics.container.yaml' && grep -qxF '    - \"tests/X.Tests/**\"' '$tmp/ws/rootapp/agentics.container.yaml'"
check "a test folder inside a project's folder is excluded" gen nestapi '    - "Api/Tests/**"'
check "tests in src/: src/** with their folders excluded" bash -c \
  "grep -qxF '    - \"src/**/*.cs\"' '$tmp/ws/srcmix/agentics.container.yaml' && grep -qxF '    - \"src/A.Tests/**\"' '$tmp/ws/srcmix/agentics.container.yaml'"
check "a reference early in a big file is found" gen big \
  '  fast: "dotnet test --solution \"Big.slnx\" --filter-not-namespace \"Big.IntegrationTests\" --filter-not-namespace \"Big.IntegrationTests.*\" --ignore-exit-code 8"'
check "DotNet.Testcontainers is Docker too" gen legacy \
  '  fast: "dotnet test --solution \"Legacy.slnx\" --filter-not-namespace \"L.IntegrationTests\" --filter-not-namespace \"L.IntegrationTests.*\" --ignore-exit-code 8"'
check "the trait spelled two ways: one clause takes both" gen vmix '  fast: "dotnet test --filter \"Category!=Integration\""'
check "MTP without xunit v3: still the mtp parser" gen mstest "  parser: mtp"
check "a global.json with comments still says mtp" gen jsonc "  parser: mtp"
check "a Docker project nested in a test-less project: the whole suite" gen nesteddb '  fast: "dotnet test"'
check "a Docker project nested in a test-less project: said why" grep -q "nesteddb: the fast suite is the whole one: no test runs without Docker" "$tmp/out.log"
check "a test in a subfolder of its project counts for that project" gen subdir \
  '  fast: "dotnet test --solution \"Subdir.slnx\" --filter-not-namespace \"S.IntegrationTests\" --filter-not-namespace \"S.IntegrationTests.*\" --ignore-exit-code 8"'
check "*Tests.<Something> and *.Testing are test helpers, not sources" \
  bash -c "! grep -qE 'Fixtures/|Foo.Testing/' '$tmp/ws/helpers/agentics.container.yaml'"
check "a conditional Testcontainers reference: the whole suite" gen condprops '  fast: "dotnet test"'
check "a conditional Testcontainers reference: said why" grep -q "condprops: the fast suite is the whole one: .*Condition" "$tmp/out.log"
check "two projects with one name: told apart by path, then refused as one namespace" \
  grep -q "samename: the fast suite is the whole one: .*shares the namespace of a Docker project" "$tmp/out.log"
check "a name the kernel refuses in a command: no profile generated" test ! -e "$tmp/ws/badname/agentics.container.yaml"
check "a name the kernel refuses in a command: said so" grep -q "badname: .*character" "$tmp/out.log"
check "no generated profile carries a shell operator in a test command" bash -c \
  "for f in '$tmp'/ws/*/agentics.container.yaml; do head -1 \"\$f\" | grep -q '^# Generated' || continue; ! grep -E '^\s*(authoritative|fast):' \"\$f\" | grep -qE '&&|[;|<>\`]|\\\$\(' || exit 1; done"
check "VSTest: the trait key in another case is the same key" gen vcase '  fast: "dotnet test --filter \"Category!=Integration\""'
check "hidden folders (a worktree copy) are not projects" bash -c \
  "grep -qxF '    - \"src/**/*.cs\"' '$tmp/ws/worktree/agentics.container.yaml' && ! grep -q '.claude' '$tmp/ws/worktree/agentics.container.yaml'"
check "MTP through TestingPlatformDotnetTestSupport with Docker: said why" \
  grep -q "tpdsdock: the fast suite is the whole one: .*TestingPlatformDotnetTestSupport" "$tmp/out.log"
check "a Condition elsewhere in Directory.Build.props: the Docker project still left out" gen unrelcond \
  '  fast: "dotnet test --solution \"Unrelcond.slnx\" --filter-not-namespace \"X.IntegrationTests\" --filter-not-namespace \"X.IntegrationTests.*\" --ignore-exit-code 8"'
check "a quote in a project path: no profile generated" test ! -e "$tmp/ws/quotepath/agentics.container.yaml"
check "a quote in a project path: said so" grep -q "quotepath: .*quote" "$tmp/out.log"
check "a RootNamespace is the namespace left out" gen rootns \
  '  fast: "dotnet test --solution \"Rootns.slnx\" --filter-not-namespace \"Company.Db.Tests.Integration\" --filter-not-namespace \"Company.Db.Tests.Integration.*\" --ignore-exit-code 8"'
check "a segment starting with a digit gets MSBuild's _" gen digit \
  '  fast: "dotnet test --solution \"Digit.slnx\" --filter-not-namespace \"_2FA.IntegrationTests\" --filter-not-namespace \"_2FA.IntegrationTests.*\" --ignore-exit-code 8"'
check "a RootNamespace set in Directory.Build.props: the whole suite" gen propns '  fast: "dotnet test"'
check "a RootNamespace set in Directory.Build.props: said why" grep -q "propns: the fast suite is the whole one: .*RootNamespace" "$tmp/out.log"
check "an exclude is written once" test "$(grep -cxF '    - "src/A/Tests/**"' "$tmp/ws/dupex/agentics.container.yaml")" = 1
check "a project next to the solution at the root: the solution named (dotnet test would refuse, MSB1011)" \
  bash -c "grep -qxF '  authoritative: \"dotnet test \\\"Rootapp.sln\\\"\"' '$tmp/ws/rootapp/agentics.container.yaml' && grep -qxF '  fast: \"dotnet test \\\"Rootapp.sln\\\"\"' '$tmp/ws/rootapp/agentics.container.yaml'"
check "a project next to the solution under MTP: --solution" gen rootmtp '  authoritative: "dotnet test --solution \"Rootmtp.slnx\""'
check "a props importing the one above: its Docker reference counts" gen importprops \
  '  fast: "dotnet test --solution \"Importprops.slnx\" --filter-not-namespace \"I.IntegrationTests\" --filter-not-namespace \"I.IntegrationTests.*\" --ignore-exit-code 8"'
check "a ProjectReference through a property: the whole suite" gen propref '  fast: "dotnet test"'
check "a ProjectReference through a property: said why" grep -q "propref: the fast suite is the whole one: .*property" "$tmp/out.log"
check "a conditional reference in the root props: production code stays a source" gen rootcond '    - "src/**/*.cs"'
check "a conditional reference in the root props: said why" grep -q "rootcond: the fast suite is the whole one: .*Condition" "$tmp/out.log"
check "a computed RootNamespace without Docker: no reason given for nothing" bash -c "! grep -q 'nsnodock: the fast suite' '$tmp/out.log'"
check "a project holding tests is a test project, whatever its name" bash -c "! grep -q 'Foo.Specs' '$tmp/ws/specs/agentics.container.yaml'"
: > "$tmp/out.log"; run
check "the reason for a whole fast suite is said on every run" \
  grep -q "condprops: the fast suite is the whole one: .*Condition" "$tmp/out.log"
# Once the user writes a real fast suite there, the reason no longer holds.
sed -i 's/^  fast: .*/  fast: "dotnet test --filter-not-namespace \\"G.IntegrationTests\\""/' "$tmp/ws/condprops/agentics.container.yaml"
: > "$tmp/out.log"; run
check "an edited fast suite: the old reason is no longer said" bash -c "! grep -q 'condprops: the fast suite' '$tmp/out.log'"
check "a project's own folder is its glob" gen services '    - "Services/Api/**/*.cs"'
check "a grouping folder is not a glob" bash -c "! grep -qF '\"Services/**/*.cs\"' '$tmp/ws/services/agentics.container.yaml'"
check "src/ with tests only: no profile generated" test ! -e "$tmp/ws/srctests/agentics.container.yaml"
check "an odd folder name is quoted" gen 'odd #2' 'name: "odd #2"'
check "an odd folder name is quoted in the reports path" gen 'odd #2' "reports: \"$tmp/home/agentics-reports/odd #2\""
check "a solution name with a space stays one argument" gen 'odd #2' \
  '  fast: "dotnet test --solution \"My App.slnx\" --filter-not-namespace \"Odd.IntegrationTests\" --filter-not-namespace \"Odd.IntegrationTests.*\" --ignore-exit-code 8"'
check "a dotfiles profile wins over a generated one, even on a first run" \
  cmp -s "$tmp/profiles/handnet.yaml" "$tmp/ws/handnet/agentics.container.yaml"
# A dotfiles profile added after a profile was generated replaces it; the generated one is kept aside, hidden.
printf 'name: services\n' > "$tmp/profiles/services.yaml"
run
check "a dotfiles profile added later replaces a generated one" \
  cmp -s "$tmp/profiles/services.yaml" "$tmp/ws/services/agentics.container.yaml"
check "the replaced generated profile is kept aside" \
  grep -q "^# Generated by agentics-profiles.sh" "$tmp/ws/services/agentics.container.yaml.generated"
check "the generated profile kept aside is excluded from git" \
  test -z "$(git -C "$tmp/ws/services" status --porcelain -- agentics.container.yaml.generated)"
# The same again later: the first copy kept aside is not overwritten.
rm "$tmp/profiles/services.yaml" "$tmp/ws/services/agentics.container.yaml"
run
printf 'name: services\n' > "$tmp/profiles/services.yaml"
run
check "a second generated profile kept aside does not overwrite the first" \
  test "$(ls "$tmp/ws/services" | grep -c '^agentics.container.yaml.generated')" = 2
check "both generated profiles kept aside are excluded from git" \
  test -z "$(git -C "$tmp/ws/services" status --porcelain -- 'agentics.container.yaml.generated*')"
# A repo folder that cannot take the copy kept aside: the generated profile stays whole, nothing is left behind.
rm "$tmp/profiles/services.yaml" "$tmp/ws/services/agentics.container.yaml"
run
chmod a-w "$tmp/ws/services"
printf 'name: services\n' > "$tmp/profiles/services.yaml"
run; rc=$?
chmod u+w "$tmp/ws/services"
check "cannot keep the generated profile aside: the script goes on" test "$rc" = 0
check "cannot keep the generated profile aside: it stays in place" \
  grep -q "^# Generated by agentics-profiles.sh" "$tmp/ws/services/agentics.container.yaml"
check "cannot keep the generated profile aside: nothing left behind" \
  test "$(ls "$tmp/ws/services" | grep -c '^agentics.container.yaml.generated')" = 2
# The copy kept aside is made, then the dotfiles profile cannot be written over the generated one: rolled back.
chmod a-w "$tmp/ws/services/agentics.container.yaml"
run; rc=$?
chmod u+w "$tmp/ws/services/agentics.container.yaml"
check "a failed replacement: the script goes on" test "$rc" = 0
check "a failed replacement: the generated profile stays in place" \
  grep -q "^# Generated by agentics-profiles.sh" "$tmp/ws/services/agentics.container.yaml"
check "a failed replacement: the copy kept aside is taken back" \
  test "$(ls "$tmp/ws/services" | grep -c '^agentics.container.yaml.generated')" = 2
check "a failed replacement: the system's own reason is shown" grep -q "services.*Permission denied" "$tmp/out.log"
rm -rf "$tmp/ws/rootmtp" "$tmp/ws/importprops" "$tmp/ws/propref" "$tmp/ws/rootcond" "$tmp/ws/nsnodock" "$tmp/ws/specs"
rm -rf "$tmp/ws/worktree" "$tmp/ws/tpdsdock" "$tmp/ws/unrelcond" "$tmp/ws/quotepath" "$tmp/ws/rootns" \
  "$tmp/ws/digit" "$tmp/ws/propns" "$tmp/ws/dupex"
rm -rf "$tmp/ws/subdir" "$tmp/ws/nesteddb" "$tmp/ws/helpers" "$tmp/ws/condprops" "$tmp/ws/samename" "$tmp/ws/badname" "$tmp/ws/vcase"
rm -rf "$tmp/ws/twosln" "$tmp/ws/nosrc" "$tmp/ws/names" "$tmp/ws/chain" "$tmp/ws/vdock" "$tmp/ws/vtrait" \
  "$tmp/ws/alldock" "$tmp/ws/mstest" "$tmp/ws/jsonc" "$tmp/ws/services" "$tmp/ws/srctests" "$tmp/ws/readonly" \
  "$tmp/ws/odd #2" "$tmp/ws/handnet" "$tmp/profiles/handnet.yaml" "$tmp/profiles/services.yaml" "$tmp/ws/integ" \
  "$tmp/ws/integ2" "$tmp/ws/mixed" "$tmp/ws/spaced" "$tmp/ws/tpds" "$tmp/ws/handmade" "$tmp/ws/helper" \
  "$tmp/ws/mixedfw" "$tmp/ws/nested" "$tmp/ws/rootapp" "$tmp/ws/nestapi" "$tmp/ws/srcmix" "$tmp/ws/big" \
  "$tmp/ws/legacy" "$tmp/ws/vmix"

# Workspaces below a hidden folder: grep must not take the whole repo for a hidden folder to skip.
hidden_repo="$tmp/.hid/ws/dot"
git init -q "$hidden_repo" && touch "$hidden_repo/Dot.slnx"
mkdir -p "$hidden_repo/src/A" "$hidden_repo/tests/D.IntegrationTests" "$hidden_repo/tests/D.Tests"
echo '<Project />' > "$hidden_repo/src/A/A.csproj"
echo '<Project><ItemGroup><PackageReference Include="Testcontainers" /></ItemGroup></Project>' \
  > "$hidden_repo/tests/D.IntegrationTests/D.IntegrationTests.csproj"
echo '<Project />' > "$hidden_repo/tests/D.Tests/D.Tests.csproj"
echo '[Fact] public void T() {}' > "$hidden_repo/tests/D.Tests/T.cs"
echo "$mtp_runner" > "$hidden_repo/global.json"
echo '<Project><ItemGroup><PackageVersion Include="xunit.v3" Version="3.0.0" /></ItemGroup></Project>' \
  > "$hidden_repo/Directory.Packages.props"
HOME="$tmp/home" AGENTICS_DIR="$tmp/kernel" AGENTICS_PROFILES="$tmp/profiles" \
  bash "$here/agentics-profiles.sh" "$tmp/.hid/ws" > "$tmp/hid.log" 2>&1
check "a repo below a hidden folder is read whole" grep -qxF \
  '  fast: "dotnet test --solution \"Dot.slnx\" --filter-not-namespace \"D.IntegrationTests\" --filter-not-namespace \"D.IntegrationTests.*\" --ignore-exit-code 8"' \
  "$tmp/.hid/ws/dot/agentics.container.yaml"
rm -rf "$tmp/.hid"

# A generated profile the kernel refuses is a guess gone wrong, not a broken install: a warning, and exit 0.
dotnet_repo refused Refused.sln Core/Core.csproj
mkdir -p "$tmp/refusing"
printf '#!/bin/sh\ncase "$*" in */refused/*) exit 1 ;; esac\n' > "$tmp/refusing/agentics"
chmod +x "$tmp/refusing/agentics"
HOME="$tmp/home" AGENTICS_DIR="$tmp/refusing" AGENTICS_PROFILES="$tmp/profiles" \
  bash "$here/agentics-profiles.sh" "$tmp/ws" > "$tmp/refused.log" 2>&1; rc=$?
check "a generated profile the kernel refuses does not fail the install" test "$rc" = 0
check "a generated profile the kernel refuses is reported" grep -q "warning: .*refused.*generated" "$tmp/refused.log"
rm -rf "$tmp/ws/refused"

# The real profiles: the kernel runs test commands as argv and refuses shell operators
# (kernel.execute._FORBIDDEN_TOKENS: && || ; | > < ` $().
for profile in "$here"/agentics/profiles/*.yaml; do
  check "$(basename "$profile"): no shell operator in a test command" \
    bash -c "! grep -E '^\s*(authoritative|fast):' '$profile' | grep -qE '&&|[;|<>\`]|\\\$\('"
done

[ "$fail" = 0 ] || { echo "--- output of the last run:"; cat "$tmp/out.log"; }
exit $fail
