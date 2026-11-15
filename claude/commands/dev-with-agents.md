---
name: 'dev-with-agents'
description: 'Run the agentics multi-agent pipeline against a repository — fix a bug, add a feature, audit the whole codebase, or inventory every feature the code implements. Every gate is evaluated by code, not asserted by a model. Invoking it ALWAYS means running the kernel — never hand-edit the change instead, however small the diff looks. Usage: /dev-with-agents --bugs "<desc>" | --feature "<desc>" | --card-provider <provider> --card <id> | --analyse [area] | --features | --worktree --bugs "<desc>" | --done [run_id|mission] | --check | --list'
---

# /dev-with-agents

Drives the `agentics` kernel: a 1-8 stage pipeline where every gate is evaluated
by code. Lives at `/mnt/data2/DiskG/MEGA/Code/agentics` (`$AGENTICS` below).

**Dev container or host?** You are in the dev container when `/workspaces` exists and `$REMOTE_CONTAINERS` is `true`. The paragraphs that say "in the dev container" apply there only; on the host, skip them.

    /dev-with-agents --bugs "<the defect>"
    /dev-with-agents --feature "<the capability>"
    /dev-with-agents --card-provider <provider> --card <id>   # from a ticket: decision brief first, run on "go"
    /dev-with-agents --analyse [optional area]
    /dev-with-agents --features
    /dev-with-agents --worktree --bugs "<the defect>"   # same, on its own branch + checkout
    /dev-with-agents --done [run_id|mission]            # commit, merge, delete branch (+ worktree); asks first
    /dev-with-agents --done --abandon [run_id|mission]  # drop a worktree run, commit nothing
    /dev-with-agents --check          # validate, spend no tokens
    /dev-with-agents --list           # the shipped workflows

## The run is the deliverable — you do not get to substitute for it

**Invoking `/dev-with-agents` means the kernel runs.** What the user asked for is
a kernel run: its gates, its artifacts, its report. It is not "the change itself,
by whichever route you judge quickest". Reading the arguments below, concluding
the pipeline is overkill, and editing the files by hand instead is the one
failure this section exists to stop.

None of these is a reason to skip the run:

- **"It is a one-line fix."** Diff size is not the deliverable. The run is — the
  gates are what make the fix trustworthy, and a one-line change passes them
  cheaply.
- **"I already know the cause."** Then the run confirms it against code instead
  of against your recollection, which is the entire point of gates evaluated by
  code rather than asserted by a model.
- **"The repo is too small / has no tests / is not really a codebase."** That is
  `--check`'s call and the profile's, not a judgement you make up front. Run
  `--check`, report what it says, and let a gate fail if one is going to.
- **"I will run it afterwards to verify my edit."** A run over work you already
  did measures your own change, not the task.

**If the request is ambiguous between flags, ASK ONE QUESTION AND WAIT** — one
flag per invocation, and two at once is a refusal, not a guess. Asking is the
sanctioned response. Hand-editing is not.

The only invocations that do not start a run are the ones named below: `--check`,
`--list`, `--done`, a question about a run that already exists, and a card flow until the user says "go".

## Parse the arguments

`$ARGUMENTS` is everything after the command name.

| the request | flag |
|---|---|
| "fix", "bug", "broken", "wrong output", a stack trace | `--bugs "$ARGUMENTS"` |
| "add", "implement", "support X", "new endpoint" | `--feature "$ARGUMENTS"` |
| "review", "audit", "refactor", "find bugs", "check security", "does it follow conventions" | `--analyse` |
| "what does this code do", "list the features", "feature inventory", "what can this system do" | `--features` |
| `--check`, `check` | `--check` |
| `--list`, `list` | `--list` |
| `--card-provider <provider> --card <id>` | "Start from a card" below |
| `--worktree` (with `--bugs`/`--feature`) | add `--worktree` to the run |
| `--done [run_id\|mission]` | `agentics done [run_id\|mission]` (see "Finish a run") |
| `--done --abandon [run_id\|mission]` | `agentics done --abandon [run_id\|mission]` |

`--bugs` and `--feature` take a description. `--analyse` and `--features` take
none: an audit and an inventory are both of the repository as a whole, and a
scope you invent is a scope the kernel did not measure. If the user names an
area, append it with `--task` rather than narrowing the profile.

One flag per invocation. Two at once is a refusal, not a guess — they are
separate missions with separate gates. The card pair is the one exception:
`--card-provider` and `--card` are one choice, made of two flags.

## Start from a card

`--card-provider <provider> --card <id>` starts from a ticket instead of a description, so the run gets the whole
card and the user validates an analysis and a design before any agent writes code. Both flags or neither: one
alone is a refusal, with the usage line `/dev-with-agents --card-provider <provider> --card <id>`. The shortcut
commands `/dev-with-agents-<provider>` land here too. Add `--worktree` to a card as to any `--feature`/`--bugs`
run; the `--worktree` section says where it applies.

**The provider file** `~/.claude/card-providers/<provider>.md` says how to read a card in that tracker: its
Connector, Id, Fetch and Mapping parts. This section never names a tracker. When the file does not exist,
list the files in `~/.claude/card-providers/` and stop. In the dev container, say how to get it: add its name to
`card-providers.conf` in the dotfiles repo, commit and push, then in the container pull and re-run
`bash ~/dotfiles/install-card-providers.sh ~/dotfiles` (or rebuild); `--choose` installs it in the running dev
container only. When its connector is missing, say what its Connector part says and stop. Never write to the
tracker: no comment, field, state or time log.

0. **An existing brief comes first.** `<id>` is the card given, normalised by the provider file's Id part (`196`
   becomes `ERP-196`), and every brief file is named after the card given, never after its parent. Look in
   `<reports>/briefs/` as step 3 defines `<reports>`, the no-profile folder included: the profile's folder first
   when both hold one. When `<id>.decision.md` exists, read nothing else yet: ask exactly
   **"Brief found (<date>). reuse / redo?"**, where `<date>` is the file's last change as `YYYY-MM-DD HH:MM`, and
   wait.
   On reuse, read only the card itself and its comments, and say what changed since the brief (a newer update, a
   new comment), that the parent was not re-read, and which parts of step 3 the brief lacks when an older command
   wrote it. When `<id>.reference.md` also exists, say a "go" was already given: another "go" starts a second run
   of the same mission. Then go straight to step 4, which shows the brief.
   On redo, rename the old brief `<id>.decision.<stamp>.md` and an old `<id>.reference.md`
   `<id>.reference.<stamp>.md`, so its recorded answers are kept. One `<stamp>` for both: the brief's last change
   as `YYYY-MM-DD-HHMM` (no space nor colon); never overwrite a kept copy, add `-2`, `-3`... to the stamp instead.
   Then go on with step 1. With no brief, go on with step 1.
1. **Read the card** as the provider file's Fetch part says: the card, all its comments, its parent and the
   parent's comments, the linked cards, the attachments as links.
2. **Analyse the code** the card names (classes, files, migrations, tests), with codebase-memory-mcp first,
   in this repo and in any other repo of `/workspaces` (or next to this one, on the host) the card names. Read
   only: nothing is built, run or edited before "go". This is where traps show up: a code that gets a new
   meaning, a unique index, a test the new spec makes obsolete, a part the card asks to "add" that already
   exists.
3. **Write the decision file** `<reports>/briefs/<id>.decision.md`, where `<reports>` is the profile's `reports`
   folder (outside the repo in the dev container; never commit a brief). A repo with no profile yet: write it to
   `~/agentics-reports/<repo>/briefs/`, and the missing profile is one of the decisions. It is for the user: plain
   English, jargon explained, as long as it needs, decisions first. Text quoted from the card stays in its own
   language. Its parts, in this order:
   1. **In short**: three lines: what the card wants, which repo(s), and the recommendation: *go*, *go on part
      of it*, or *wait* (and for what).
   2. **Decisions for you**: numbered. Each gives the question, the options, what each changes, the
      recommendation and why. Every gap is one: a question the card says to ask before coding with no answer
      in the comments, a second repo or a repo without an agentics profile, a part a comment puts on hold, a
      choice the code forces that the card does not settle.
   3. **What the card asks**: what to build, done when, out of scope (verbatim, from the provider's Mapping),
      each item tagged with its repo; the decisions found in comments (author, date, quote); the parent in two
      lines.
   4. **Analysis, the code today**: what exists, with `file:line`; what the change touches; the traps found.
      Each claim says whether it was read in the code or is an assumption.
   5. **Proposed design**: the files to create or change; the tests written first, one line each on what it
      proves; for a migration, its steps in order and whether it can be undone.
   6. **Risks**: what could go wrong and its impact on data (real or personal data, a migration that cannot be
      switched off), on security (rights, 403s), on other repos or teams.
   7. **How "done" is checked**: each done-when item mapped to the test or gate that proves it, and what the
      run cannot check (a mockup, a PR, a review).
   8. **Effort**: the card's estimate against what the analysis found.
   9. **Sources**: the cards, comments and files read, as links.

   Mockups and attachments are links only: the agents cannot open them, and the decision file says so.
4. Show the decision file in full, then ask exactly: **"Run? go / answers"**, and stop.
   Only an explicit "go" starts the run. Anything else is an answer: write it into the decision file (under the
   decision it settles, or "out of scope" for a part or repo the user drops), show what changed, and ask again.
   "go, but …" is an answer: apply the "but", show it, and ask again.
5. **On "go"**: write `<reports>/briefs/<id>.reference.md` for the agents, at most 6000 bytes (an accented
   letter takes 2; the stages' context budgets start at 10 KB, and a longer task pushes out their rules): the card id
   and title, what to build, the approved design, the decisions with the user's answers, done when, out of
   scope; cut comments and sources first when it does not fit. Then go through "Before running anything" and run:

   ```bash
   $AGENTICS/agentics run \
     --project <repo>/agentics.yaml \
     --mission <id-lowercase>-<slug-of-the-card-title> \
     --runtime <claude-code if you are Claude Code, else opencode> \
     --feature "$(cat <reports>/briefs/<id>.reference.md)"
   ```

   The mission is the kernel's slug: ASCII, lowercase, words joined by `-`, at most 60 characters (`erp-196-` then the
   title's first words, accents dropped). This file IS the run's description, the one text every stage reads.
   `--reference` and `--answer` would reach no role of the bugfix workflow (only pentest roles read them), so the
   approved design and the user's answers must be in it. `$(cat …)` keeps card text away from the shell: a quote or
   `$(…)` in a card title is never run. `--bugs` instead of `--feature` when the provider's Mapping says the card is a
   bug. One run per repo: for a card that spans two repos, run in this one, and the decision file has already put the
   other repo to the user as a decision. `--done` works as for any run.

## Running it from Claude Code: use the background

**A run exceeds the foreground Bash ceiling.** Claude Code caps a foreground
command at 600 000 ms (10 min); a bugfix run is 8 model invocations and routinely
longer. Start it with `run_in_background: true` and poll, or it will be killed
mid-stage and leave a half-written run directory that `--resume` then refuses.

`--check`, `--list` and `init` are sub-second and belong in the foreground.

### Showing the run to the user

- Start `agentics run ...` in the background. The first line it prints is
  `== run <run_id> (...) -- live log: <path>/progress.log`. Give the user that
  run_id and log path right away.
- While the run is going, stream `progress.log` into the conversation (with the
  Monitor tool if it's available, or `tail -n +<last line read>` every few
  minutes), **minus the per-tool echo lines**:

  ```bash
  tail -n +<N> -F progress.log \
    | grep --line-buffered -vE '^\S+ \[[^]]*\]\s+[a-z-]+\s+(Read|Grep|Glob|Edit|Bash|Write|says|thinks):'
  ```

  Paste what survives verbatim in a code block. Do not paraphrase it. The echo
  lines (`Read:`, `Grep:`, `says:` ...) are 85.6 % of an ANALYSE log's bytes
  (55 logs, 3.72 MB, measured 2026-10-20) and relaying them costs 15-40k tokens
  of context per run; they stay in `progress.log` for the user to `tail -f`.
  `--line-buffered` is required: without it grep holds its output until the
  run ends, the same silence as piping the run itself (see below).
  On a resume, start from the log's length at launch,
  `tail -n +$(( $(wc -l < progress.log) + 1 )) -F progress.log | grep ...` (same
  filter), never `-n +1`: the parked pass's summary is already in it (A74,
  run_5e36628884).
- When the run ends, paste the final summary block verbatim (from `run_id:`
  to `artifacts:`), then give your own reading of it. On a resume,
  `progress.log` already holds the parked pass's summary, `artifacts:` line
  included: the final block is the one after the last `== resuming` line (A74).
- Before editing `agentics.yaml` (for example the `tests.fast` filter), say so
  and show the diff. The run also prints the active `fast` command at the start.

### Showing the user live progress — do NOT pipe the run through `tail`

**The kernel already prints live per-tool-call progress. Do not pipe it away.**
`_progress_line` in `runtime/adapters.py` (one per adapter) turns each runtime
event into one short human line, prefixed with the role. What the model says
between tool calls shows as `says:`, and its thinking as `thinks:`:

```
    p-recon            session up (14 tools)
    p-recon            Bash: curl -sS -D- http://10.0.0.5/
    p-tester           Read: /path/to/target/config.php
    p-tester           done (1843 out, cost 0.0412)
```

**So the one thing you must not do is pipe the run through `tail`, `head` or any
filter.** A pipe buffers the whole stream and flushes at exit, so every one of
those lines sits invisible until the process ends and the user watches nothing
happen for ten minutes. This has already happened once and produced three
rounds of "why is nothing displayed?". Let the run write straight to its
background output file:

```bash
$AGENTICS/agentics run --project ... --runtime ... --task "..."
# run_in_background: true, NO pipe
```

Then read that output file incrementally to relay progress — it fills line by
line as the agents work.

**What is NOT available mid-run, so do not promise it.** The kernel persists
`run-state.json`, `artifacts.json`, `gate-reports.json` and the rendered report
in `_persist`, **at the end of each pass** — and a parked pass (pre-flight
budget, placement, any `AWAITING_HUMAN`) is a pass: those files already exist,
from the park, while a resume of that run is still working. Their presence
never means the resume is done. While it runs, three things land in
`runs/<run_id>/`: `progress.log` (the stream, each line prefixed with the
wall-clock time), `answers/` (each stage's raw answer), and `transcripts/NNN-<role>.json`
(each invocation's full reasoning, tool calls, answer and cost, written as it
returns). Gate verdicts are not on disk until the end.

When the run ends, the report has a companion, `agents_<run_id>.md`, beside
`run_<run_id>.md`: what each agent thought, did and produced, quoted from those
transcripts.

**The coarse fallback, if the stream was lost anyway:** each role gets a
`runs/run_*/scratch-<role>/` directory created when its stage starts. Empty, but
the names and mtimes give stage order and per-stage duration.

```bash
R=$(ls -dt $AGENTICS/runs/run_* | head -1)
ls -ltr --time-style='+%H:%M:%S' $R/
```

A `Monitor` on that directory gives one notification per stage *boundary*, which
is the wrong granularity for "what is the agent doing" and should not be used as
a substitute for the stream. If you do arm one, make it cover the failure paths:
exit when the process ends — the background task's own notification is the
reliable signal — or, failing that, when `run-state.json` is **newer than the
launch of this pass** (`find $R -maxdepth 1 -name run-state.json -newer <a file
touched at launch>`), never on its mere existence: on a resume it is there from
the start, and a loop keyed on it exits at once and reports a half-finished
run as final (A58, run_5df0f9ebbc). Cover the process vanishing without it too —
under `--runtime claude-code` that is the expected outcome, and a success-only
filter sits silent through the crash. Nothing is final before the `artifacts:`
line of the summary that follows the last `== resuming` line: a resumed
`progress.log` also holds the parked pass's own summary (A74).

## Before running anything

**1. Is there a project profile?** Without one the pipeline runs the shipped C#
demo fixture, not the user's code.

```bash
ls <repo>/agentics.yaml
```

If it does not exist, create it — on the host, the only file that goes in the
repository. **In the dev container,** the profile never goes in the repository: a repo under
`/workspaces` gets it from the dotfiles (`agentics/profiles/<repo>.yaml`,
installed by `agentics-profiles.sh`) as `agentics.container.yaml`. A .NET repo
with no dotfiles profile gets one generated there instead: its first line says
`# Generated by agentics-profiles.sh`. Say which kind it is. A generated one
guesses the fast suite from Testcontainers and the Integration trait only, and
falls back to the whole suite when unsure (the install prints why, and a warning
when the kernel refused the guess): check its `fast:` line against the repo
before the run, and propose moving it to the dotfiles once it is right. A repo with neither has none: not .NET, or
one the install named in a `note: ... no profile generated` line (two solutions,
no project outside the tests, a test project at its root, a quote or shell
character in a name). Say so and propose the dotfiles file. A profile made here is never
committed, and exists in this one clone only, not in the dotfiles that rebuild
the next container. It is
git-excluded only if the repo was in `/workspaces` when `agentics-profiles.sh`
last ran: for a repo cloned since, run it again first
(`bash ~/dotfiles/agentics-profiles.sh /workspaces`, idempotent), or the profile
and what the run writes show up as untracked.
Copy `$AGENTICS/demo/PythonShop/agentics.yaml` for Python,
`$AGENTICS/demo/GreetingDemo/agentics.yaml` for C#.

```yaml
name: MyRepo
project:
  root: .
  source_globs: ["src/**/*.py"]        # must match real files
  exclude: ["**/__pycache__/**"]
tests:
  authoritative: "python3 -m pytest -q"   # the suite the KERNEL runs
  fast: "python3 -m pytest -q tests/fast" # what the guard check re-runs
  parser: pytest                          # xunit|mstest|nunit|mtp|pytest|jest|none
roles:
  developer: {rules: rules/python.md}
security: [auth, token, secret, payment]   # path substrings
knowledge_base:
  root: ../secondbrain
  domains: [general]
reports: agentic-reports
```

Two keys earn their place. **`tests.fast`**: without it the guard check reverts
the fix and re-runs the AUTHORITATIVE suite, so on a project whose suite needs
Docker that is minutes per attempt against deliberately broken code.
**`knowledge_base.domains`**: a domain is a directory holding an `INDEX.md`,
derived from the filesystem — declare none and the documentation phase finds no
domain, refuses to invent one, SKIPS, and the run ends FAILED on
`G-DOC-PLACEMENT` for a repository that was empty rather than misconfigured.
The list is what `init` builds and `check` verifies. It does not limit placement:
the doc-writer may file a lesson in any domain of the knowledge base that holds an
`INDEX.md`, so a run on a C# repo can still write to `general/`.

**A knowledge base also needs its tools.** Knowledge is written only through
`<knowledge_base root>/tools/promote.py` (A141), which imports `tools/lint.py`, and the architect's notes come from
`tools/search.py` (A143). `check` reports a missing `promote.py` as a PROBLEM (A147) and `init` warns about it
(A156); both print a NOTE for a missing `search.py`, whose absence only means the architect gets no notes. The
architect also searches the secondbrain (`AGENTICS_KB`, or `../secondbrain` next to agentics) after the project's
own base, so a project-local base does not cut it off from the shared notes (A160); `check` shows it on its
`shared kb` line. `init` does not create them; run without `promote.py` and the documentation phase CRASHES with
`PromoteError: …/tools/promote.py not found`, and the run ends FAILED on `G-DOC-PLACEMENT` and `G-DOC-CRITIQUE` even
when every run gate passed (`run_aaf539a257`, 2026-10-23). For a project-local knowledge base, copy `promote.py`,
`lint.py` and `search.py` from `/mnt/data2/DiskG/MEGA/Code/secondbrain/tools/` (the copies do not follow later
changes there) and run `python3 <root>/tools/lint.py` (0 problems) before the run. If it was missing on a run whose
run gates all passed, fix it and re-document only: `agentics run --document-only <run_id> --placement <domain>` (no
`--project`).

**`source_globs` anchor the walk.** A glob with a literal first segment
(`src/**/*.py`) means the kernel only walks `src/`. An unanchored one
(`**/*.py`) means it walks everything, because source could be anywhere.
Measured on a 63 000-entry tree: 16.7 s per walk unanchored, 0.03 s anchored,
and the walk happens several times per stage. Anchor them.

`capabilities` and `may_write` are REFUSED in this file. Write authority is
decided once, in the workflow; a profile cannot grant it. Wanting one here means
the workflow needs a role, not the profile.

**2. `agentics init` — once per repository, and again after any profile change.**

```bash
$AGENTICS/agentics init --project <repo>/agentics.yaml
```

Invokes no model. Read its output: how many files the globs matched, which rules
files exist, which domains it built, where reports land, whether `tests.fast` is
declared.

**3. `agentics check` — always.**

```bash
$AGENTICS/agentics check --project <repo>/agentics.yaml --workflow <bugfix|analyse|features>
```

Pass the workflow of the mode you will run: `--bugs`/`--feature` → `bugfix`,
`--analyse` → `analyse`, `--features` → `features`. Without `--workflow`, `check`
validates BUGFIX, so an audit is checked against the wrong gates and gets no
cost estimate. `check` does not take `--analyse` itself.

`0 file(s) matched` means the globs are wrong and the run would measure nothing.
A `MISSING` knowledge base means documentation will be SKIPPED and
`G-DOC-PLACEMENT` will fail — the run is still worth doing, but say so.

**4. Is the tree clean?** The kernel detects a write by a read-only role and
refuses it, with NO rollback. If `git status` is dirty, say so and offer to
commit or stash first. A brief under `<reports>/briefs/` is expected after a card
flow: it is not a reason to commit or stash, and `agentics done` never commits it.

## Run it

```bash
$AGENTICS/agentics run \
  --project <repo>/agentics.yaml \
  --mission <kebab-case-slug> \
  --runtime <claude-code if you are Claude Code, else opencode> \
  --bugs "<the defect in the author's own words>"
```

The mission slug names `reports/<slug>/` and the knowledge-base note, and is
reused across runs so the note accumulates instead of fragmenting. Derive it
from the work: `cart-empty-total`, `order-export-csv`. Never omit it — a run
without one files its report under `null`.

### `--runtime` — detect it, always pass it, never ask

**Always pass `--runtime` explicitly, and derive it from the harness you are
running in. Do not ask the user which runtime to use.**

| you are running inside | pass |
|---|---|
| Claude Code (CLI, desktop Code tab, IDE extension) | `--runtime claude-code` |
| anything else | `--runtime opencode` |

You can tell from your own environment, so this is never a question for the
user. Leaving the flag off silently takes `opencode`, which is wrong whenever a
Claude Code session is the thing driving the run. Both runtimes restrict tools
per role and refuse a role they have no mapping for; the run report names
whichever prevention mechanism was actually in force, so **state which one you
used** — that is reporting, not asking.

`--runtime claude-code` from inside Claude Code means nested `claude` processes.

### `--worktree` — the run edits a separate checkout

**Not in the dev container.** The checkout would land in `/workspaces/<repo>.wt/`,
outside the folder shared with the host, and a rebuild deletes it. Run without
`--worktree` here, and say so if the user asked for it.

Add `--worktree` to a `--bugs`/`--feature` run (it needs `--mission`). The
kernel creates branch `agentics/<mission>` checked out in
`<repo-parent>/<repo>.wt/<mission>/`, cut from the branch the repository is on
(`done` merges back into that same branch), and runs there; reports, rules and the
knowledge base stay in the main repository. Use it whenever the target is the
agentics repository itself. It refuses when tracked files have uncommitted
changes (edits to the profile's own `reports`/`knowledge_base` excepted: the
run writes those in the main tree, and they are never part of its commit).
The checkout is kept after the run so the user can review the diff.

The checkout holds only what git tracks. If the suite needs untracked
dependencies, the profile lists them, relative to the project root:
`worktree_links: [.venv, node_modules]`. They are symlinked into the checkout,
never copied, and removing the checkout leaves them intact.

To resume a parked worktree run, use the printed `resume with:` line as is (it
names the derived `.agentics-wt-<mission>.yaml`), or drop `--project`: the
kernel refuses the original profile for it, by name.

## Finish a run — `--done`

**No commit without the user's yes.** In the dev container, never run
`agentics done` or `git commit` on your own, not even after `--done`. First
show the user, for the run:

1. the changed files and `git diff --stat`;
2. each gate and its PASS/FAIL;
3. the commit message you would use, in the repo's own format when it has one
   (gmao-referential and erp-socle: `<type>(<scope>): ERP-<n> <description>`,
   checked by `.githooks/commit-msg`);

then ask exactly: **"Commit? yes/no"**, and stop. Only an explicit "yes" in
the user's next message allows the commit. "no", silence or anything else:
change nothing, commit nothing. Claude Code also asks before both commands
(`ask` rules written by `claude-ask-rules.sh`): that prompt is the second
lock, not a reason to skip the question.

In a repo whose commit-msg hook refuses the kernel's message
(`agentics <run_id>: <mission>`), `agentics done` cannot succeed: after the
"yes", take the recorded files (the `paths` of
`$AGENTICS/runs/<run_id>/mutation-ledger.json`) that `git status --porcelain -- <paths>`
still lists, from the repo root: a path the run created then deleted, or one
.gitignore excludes, is not the change. `git add` only the new ones (`??`: an
untracked file is refused by `git commit -- <path>`); a tracked one needs no
`git add`, and adding it would overwrite what the user staged of it. Then run
`git commit -m "<agreed message>" -- <those paths>`, never a bare `git commit`, which would sweep in whatever else
is staged. If that commit fails (the hook refuses the message), `git reset -q --`
the new files you added, as `agentics done` does, or the next commit sweeps
them in. `agentics done` for that run then refuses with "its recorded files
are unchanged, nothing to commit"; that is expected.

```bash
$AGENTICS/agentics done [<run_id>|<mission>]   # foreground, sub-second
```

All git steps are done by this command. Do not run git yourself (the one
exception is the `git add` + `git commit` (+ `git reset` on failure) above, for a repo whose hook refuses
the kernel's message), and do not call it unless the user asked for `--done`
(in the dev container: answered "yes" as above), as it commits and merges. It refuses
a run that is not `DONE` or has a gating check not `PASS`, and a merge conflict
(aborted, branch kept; fix it and call `done` again, it picks up where it
stopped). A run made WITHOUT `--worktree` is only committed (its recorded
files, on the current branch): no merge, no branch deleted. With no argument it takes the only waiting worktree run,
or lists the waiting ones. It never pushes and never deletes `runs/<run_id>/`.

A worktree commit holds every change to a tracked file plus the new files the
kernel recorded; other new files (coverage, build output) are discarded with
the checkout. `done --abandon` drops a worktree run (typically a FAILED one):
branch and checkout removed, nothing committed. Only on the user's request.
A worktree run that never created its run directory is removed automatically.
Relay its output, or its `REFUSED:` line, verbatim.

## Read the result

Exit `0` = `DONE`. `1` = `FAILED` or `AWAITING_HUMAN`. `2` = bad arguments or
profile.

1. the terminal summary — per stage: context size, tokens, cost; per gate: PASS/FAIL
2. for `--features`, `reports/<slug>/features.md` — the catalogue itself. Read
   this before the run report, which is telemetry.
3. `reports/<slug>/run_*.md` — kernel-rendered; only section 5 is model prose
4. `runs/run_*/gate-reports.json` — for a FAIL, `checks[]` says which
   requirement failed and why
5. `runs/run_*/run-metrics.yaml` — real token and cost figures
6. what the knowledge base gave the run (A143): the analysis's `kb_query`, the
   design's `kb_used`, or the omission saying why nothing was searched:

   ```bash
   R=$AGENTICS/runs/<run_id>
   python3 -I -c "import json,sys; r=sys.argv[1]
   for a in json.load(open(r+'/artifacts.json')).values():
       c = a.get('content') or {}
       for k in ('kb_query', 'kb_used'):
           if k in c: print(a['kind'], k, json.dumps(c[k]))
   for s in json.load(open(r+'/context-explanation.json')):
       for o in s.get('omitted') or []:
           if 'knowledge base' in str(o.get('reason')): print(s['role'], o['reason'])" $R
   ```

Report: what changed, which gates passed, which failed and why, the cost, the
path to the report, and which knowledge-base notes the architect used (or why
none, or why it was not searched). A `DONE` run with a red gate is not clean — say which.

### AWAITING HUMAN

Follow the printed `resume with:` line. It is correct as printed.

```bash
$AGENTICS/agentics run --project <repo>/agentics.yaml --resume <run_id> --answer "<decision>"
```

**Do not add `--task`.** The parked run's task is restored from its own
`run-state.json`, and a `--task` that differs from it is REFUSED — half the
stages would be answering a different question. A bare `--resume` is a complete
request.

Every stage that completed before the park is reused; only the stage that asked,
and those after it, re-run. For a knowledge-placement park there is a
one-invocation path:

```bash
$AGENTICS/agentics run --document-only <run_id> --placement <domain>
```

## What each mode does

**`--bugs`** — `workflows/bugfix.yaml`, 8 stages, **18 gates**. analysis, design,
implementation, testing, then review + security_review in parallel (plus
ux_review if a screen changed), then synthesis, then a mission note and an
independent critique of it. `G-TEST-GUARDS` is the one that matters: the kernel
reverts the fix, re-runs the suite, and requires the new test to be what fails.

**`--feature`** — the same pipeline, different framing: every acceptance
criterion must be covered by a test the kernel can run.

**`--analyse`** — `workflows/analyse.yaml`, 4 stages, **12 gates**. Read-only: no
stage has `writes`, no role holds `file.write`. It audits what is there and
reports findings by severity. It certifies nothing about a change because it
makes none. Each finding worth fixing becomes its own `--bugs` run. A finding it
reports is a model's judgement cross-checked against kernel-measured facts where
facts exist — not a kernel-verified defect.

**`--features`** — `workflows/features.yaml`, 1 stage, **8 gates**. An analyst
walks the source index file by file and records every implemented feature with
what it is, how it works, and the code that implements it.
`G-FEATURES-RECORDED` certifies that a catalogue exists and that the analyst
*stated* the whole index was covered — `AGENT_ASSERTED`. The kernel knows which
files exist, never which features they hold. If `coverage_complete` is false the
sweep was partial; say so rather than presenting the list as the whole system.

## The two waivers, and what they now do

Both gates read a kernel-derived `*_unwaived` signal, so a waiver lets the run
close **without deleting the finding**:

| flag | gate | waived outcome |
|---|---|---|
| `--waive-duplication` | `G-NO-DUPLICATION` | gate PASSes; the violation stays at KERNEL_VERIFIED, the acceptance at HUMAN_ASSERTED |
| `--waive-tool-denial` | `G-NO-TOOL-DENIAL` | same shape — the refused tool use stays on the record |

Still do not reach for them to get a green run. They record a human accepting a
cost, and the finding remains in the run's artifacts either way.

## Rules

- Never hand-edit `kernel/`, `runtime/`, `workflows/`, or `run_workflow.py` to
  make a run succeed. Those are the enforcement boundary. A gate that blocks is
  telling the truth; changing the gate to pass is the failure this system exists
  to prevent.
- `agentics.yaml` is safe to create and edit. It is configuration.
- If a gate fails because the PROJECT is under-specified — no test command, no
  rules, globs matching nothing — fix the profile and re-run. That is a real fix.
- Report the cost. It is measured and in the summary.

## When something is wrong with the system itself

```bash
cd $AGENTICS && python3 -m pytest tests/ -q   # no model calls; every test must pass
python3 adversarial_probe.py                  # 19 attacks on the trust boundary
```

Use `pytest`, not `unittest discover` — part of the suite is parametrised and
`unittest` silently collects less. Both must pass before a run's verdict means
anything. If one fails, say the pipeline is broken rather than working around it.
