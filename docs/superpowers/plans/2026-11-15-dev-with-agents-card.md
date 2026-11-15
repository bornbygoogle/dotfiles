# /dev-with-agents from a card: Implementation Plan

> **History.** This plan is as executed on 2026-11-15. The installer has changed since (f17228a and after): it
> installs only the providers chosen in `card-providers.conf` (or by argument, `$CARD_PROVIDERS`, `--choose`),
> and the install self-check checks those. The spec's Install section is current.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `/dev-with-agents --card-provider youtrack --card ERP-196` (short: `/dev-with-agents-youtrack 196`)
reads the card, analyses the code, shows a decision brief and waits for "go" before any kernel run.

**Architecture:** Markdown instructions only, no kernel change. The main command holds the provider-free steps;
`claude/card-providers/<p>.md` holds the tracker specifics; `claude/commands/dev-with-agents-<p>.md` is a
shortcut. A small installer script copies them into the container. Tests are bash checks on the real files.

**Tech Stack:** bash, jq, Claude Code slash commands, the YouTrack MCP connector.

**Spec:** `docs/superpowers/specs/2026-11-15-dev-with-agents-card-design.md`

## Global Constraints

- Read only on the tracker: no comment, state change or time log. No token stored.
- The main command holds no YouTrack word: `youtrack` (outside the `--card-provider` example), `get_issue`,
  `get_issue_comments`, `search_issues`, `subtask of`.
- No company URL in the dotfiles (public repo): no tracker host name in any tracked or untracked file.
- Briefs go to `<reports>/briefs/` of the profile in use (`~/agentics-reports/<repo>/briefs/` in the container),
  never in the repo.
- Nothing runs before the user answers "go" to the exact prompt **"Run? go / answers"**.
- Test style: the existing `check "<label>" <command>` harness, throwaway `$HOME`, no network, no model.
- No commit without the user's explicit yes (a yes means commit and push).

## Review Focus

1. `/dev-with-agents --card ERP-196` without `--card-provider` (or the reverse): refused with the usage line, no
   guess. Pinned in Task 2.
2. An unknown provider (`--card-provider jira`): lists the existing provider files and stops. Pinned in Task 2.
3. `/dev-with-agents-youtrack ERP-196` (full id given to the shortcut): kept as is, not `ERP-ERP-196`. Pinned in
   Task 1.
4. The connector missing in the container: the command says how to add it and stops; the install prints the
   hint and still succeeds. Pinned in Tasks 2 and 3.
5. Running the installer twice, or with no provider files: a second run replaces a stale copy, no error. Pinned in
   Task 3.

---

### Task 1: YouTrack provider file and shortcut command

**Files:**
- Create: `claude/card-providers/youtrack.md`
- Create: `claude/commands/dev-with-agents-youtrack.md`
- Test: `card-providers.test.sh` (new)

**Interfaces:**
- Produces: provider files with exactly these four `##` headings, in order: `## Connector`, `## Id`,
  `## Fetch`, `## Mapping`. Shortcut `dev-with-agents-<p>.md` whose body tells the agent to follow
  `/dev-with-agents` with `--card-provider <p> --card <id>`.

- [ ] **Step 1: Write the failing checks** in `card-providers.test.sh`:
  - `every shortcut has its provider`: for each `claude/commands/dev-with-agents-*.md`,
    `claude/card-providers/<p>.md` exists.
  - `every provider has its shortcut`: the reverse.
  - `each provider has the four parts`: `grep -c '^## \(Connector\|Id\|Fetch\|Mapping\)$'` is 4, in that order.
  - `the youtrack provider names its tools`: `get_issue`, `get_issue_comments`, `links: ` present.
  - `the youtrack provider sets the default project`: `ERP` named as the default key for a bare number.
  - `a full id is kept`: the shortcut says an argument already holding `-` (like `ABC-12`) is used as is.
  - `the youtrack bug mapping`: provider maps Type `Bug` to `--bugs`, anything else to `--feature`.
  - `no tracker host name`: no `https://<name>.youtrack.cloud` in any tracked file.
- [ ] **Step 2: Run** `bash card-providers.test.sh` → FAIL on the missing files.
- [ ] **Step 3: Write both files.** Provider: Connector (server `youtrack`; when missing, tell the user
  `claude mcp add --transport http --scope user youtrack <your YouTrack URL>/mcp` then `/mcp` to log in, and stop),
  Id (`<PROJECT>-<n>`, default `ERP`), Fetch (the spec's list: `get_issue`, all pages of `get_issue_comments`,
  parent via `parentIssue` + its comments, `search_issues "links: <id>"` summary and state, attachments as links),
  Mapping (Type field; "Ce qu'on attend" / "Fait quand" / "Hors périmètre"; a comment with "en attente" is a hold).
  Shortcut: frontmatter `name`, `description` with usage `/dev-with-agents-youtrack <n|id>`.
- [ ] **Step 4: Run** `bash card-providers.test.sh` → all ok.

### Task 2: The card flow in the main command

**Files:**
- Modify: `claude/commands/dev-with-agents.md` (frontmatter description, usage block lines 13-21, "The run is the
  deliverable" list of non-run invocations line 49-50, parse table lines 56-66, new section `## Start from a card`
  after "Parse the arguments")
- Test: `render-command.test.sh`

**Interfaces:**
- Consumes: the provider file headings from Task 1; the path `~/.claude/card-providers/<p>.md`.
- Produces: the strings `--card-provider`, `--card`, `Run? go / answers`, `<id>.decision.md`,
  `<id>.reference.md` that Task 3's checks and the user rely on.

- [ ] **Step 1: Add the failing checks** to `render-command.test.sh`, on the source and the rendered copy:
  - `the command documents the card flags`: `--card-provider` and `--card ` in the usage block.
  - `one card flag alone is refused`: the text says both or neither, and to show the usage line.
  - `an unknown provider lists the providers`: mentions listing `~/.claude/card-providers/` and stopping.
  - `the card flow stops before the run`: `Run? go / answers` present, and "go" is the only trigger.
  - `the two brief files`: `.decision.md` and `.reference.md` and `briefs/` present.
  - `the decision file order`: the nine headings of the spec appear in order (In short, Decisions for you, What
    the card asks, Analysis, Proposed design, Risks, How "done" is checked, Effort, Sources).
  - `no tracker word in the main command`: none of `get_issue`, `search_issues`, `subtask of`, a youtrack.cloud host.
  - `the analysis is read only`: says nothing is built, run or edited before "go".
- [ ] **Step 2: Run** `bash render-command.test.sh` → the new checks FAIL.
- [ ] **Step 3: Edit the command.** The section follows the spec's "Steps, whatever the provider" and "The two
  files". Answers go to the decision file; on "go", write the reference file and run with it as the description
  (`--feature "$(cat …reference.md)"`; ruling, final review C1), `--mission <id-lowercase>-<slug>`, `--feature` or
  `--bugs` from the provider's mapping; one run per repo. Add to the non-run invocations: a card flow before "go".
- [ ] **Step 4: Run** `bash render-command.test.sh` → all ok; `bash card-providers.test.sh` still ok.

### Task 3: Install into the dev container

**Files:**
- Create: `install-card-providers.sh` (usage: `install-card-providers.sh <dotfiles dir>`)
- Modify: `install-agentic.sh` step 9 (call it after `render-command.sh`); self-check block (provider dir exists)
- Test: `card-providers.test.sh`

**Interfaces:**
- Consumes: Task 1's files. Calls `claude mcp list`.
- Produces: `~/.claude/commands/dev-with-agents-<p>.md` and `~/.claude/card-providers/<p>.md`.

- [ ] **Step 1: Add the failing checks** (throwaway `$HOME`, a fake `claude` first on `PATH` that prints a
  canned `mcp list`):
  - `the installer copies shortcuts and providers`: both files exist under `$HOME/.claude`.
  - `a missing connector prints the hint and succeeds`: fake list without `youtrack` → exit 0, output holds
    `claude mcp add`.
  - `a present connector prints no hint`: fake list with `youtrack:` → no `claude mcp add` in output.
  - `running twice is harmless`: second run exits 0, files unchanged.
  - `install-agentic.sh calls it`: `grep -q install-card-providers.sh install-agentic.sh`.
- [ ] **Step 2: Run** → FAIL (no script).
- [ ] **Step 3: Write the script**: copy with `cp`, then for each provider, `grep -q "^<p>:"` on `claude mcp list`
  output; on miss, print the provider file's Connector hint line. Wire it into step 9 and the self-check.
- [ ] **Step 4: Run** all five suites → all ok.

### Task 4: Live check, then report

- [ ] **Step 1:** On the host (it has the YouTrack connector), from a scratch folder in the session scratchpad
  with `.claude/commands/` holding the new main command and shortcut, and the provider copied to
  `~/.claude/card-providers/youtrack.md`: run `/dev-with-agents-youtrack 196` interactively against a copy of
  gmao-referential's profile. Expected: a decision file for ERP-196 in `briefs/` whose "Decisions for you" names
  the missing matrix cells and erp-socle, and the session stops on "Run? go / answers". Answer nothing; no kernel
  run starts (`ls $reports/runs` unchanged).
- [ ] **Step 2: Teardown:** remove the scratch folder and the temporary `~/.claude/card-providers/` on the host;
  verify with `ls`.
- [ ] **Step 3:** Report and ask for the commit yes/no (commit and push, then `git -C ~/dotfiles pull` and
  `bash ~/dotfiles/install-card-providers.sh ~/dotfiles` in the container).
