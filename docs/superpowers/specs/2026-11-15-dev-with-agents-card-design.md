# /dev-with-agents from a card: start a run from a ticket, any tracker

## Why

Today a run starts from a `--feature "…"` string I type by hand, so the agents only see what I remembered to
copy. A card like ERP-196 holds much more: the context, the expected changes per repo, the "done when" list,
the out-of-scope list, the parent story, and comments such as "back end possible, front en attente". The run
should start from all of it, and I should validate an analysis and a design before any agent writes code.

YouTrack is the first card provider, not the only one: GitHub Issues, Jira or others come later, so nothing in
the main command may assume YouTrack.

## Goals

- `/dev-with-agents --card-provider youtrack --card ERP-196` reads the card, analyses the code it touches, and
  writes a decision brief: analysis, proposed design, risks, and the decisions I have to make, each with a
  recommendation.
- `/dev-with-agents-youtrack 196` is the short form of the same thing.
- It shows me the brief and **waits for my go**. Nothing runs before that.
- On my go, the approved brief becomes the run's description, so the agents follow the design I validated.
- Adding a provider later means adding one provider file and one shortcut command, nothing else.

## Non-goals

- No writing back to the tracker: no comment, no state change, no time logged. Read only. In the container,
  `claude-ask-rules.sh` makes the 10 YouTrack write tools ask first, so the prose is not the only guard.
- No kernel change in agentics.
- No tracker token stored anywhere.
- No second provider now: only the contract that makes one easy to add.

## Anti-goals

- A run that starts on a card with unanswered questions without me knowing.
- A brief I cannot decide from in one read: jargon, no recommendation, decisions buried at the end.
- A brief that drops "Hors périmètre" or "Fait quand": those are what the gates and the review check against.
- YouTrack words (`get_issue`, "subtask of", custom field names) in the main command.

## Approaches

- **A, picked: the command reads the card through the tracker's MCP connector.** The Claude session running
  `/dev-with-agents` has the connector; the kernel's child agents do not (`--setting-sources ""`), so the session
  writes the brief and passes it on as the run's description (`--reference` would reach no bugfix role:
  only pentest roles read it). Reuses my existing connector login.
- B, a script calling the tracker's REST API: repeatable output, but needs a permanent token in the container.
- C, card reading in the agentics kernel: a tracker client in the kernel, most work.

## Design

### Commands

- `/dev-with-agents --card-provider <p> --card <id>`: the full form, in the existing command. Both flags or
  neither: one alone is refused with the usage line.
- `/dev-with-agents-youtrack <n or id>`: a shortcut command. `196` becomes
  `--card-provider youtrack --card ERP-196`; a full id (`ABC-12`) is kept as is. The default project key `ERP`
  lives in the provider file.

A future provider adds `/dev-with-agents-<provider>`, the same three lines.

### Providers

The main command knows the steps, the provider file knows the tracker. Provider files live in
`claude/card-providers/<provider>.md` in the dotfiles, installed to `~/.claude/card-providers/` (not under
`commands/`, where every `.md` becomes a slash command). An unknown provider: the command lists the files that
exist and stops.

A provider file answers, for its tracker:

1. **Connector**: which MCP server and tools it needs, and what to tell me when they are missing (the add
   command and the login, without the company URL: the dotfiles repo is public).
2. **Id**: the id format, and the default project key for a bare number.
3. **Fetch**: the card (summary, description, type, state, custom fields), all its comments, the parent and its
   comments, linked cards one level deep (summary and state), attachments as links.
4. **Mapping**: which field says bug or feature; where the card keeps "what to build", "done when", "out of
   scope" (for this YouTrack: "Ce qu'on attend", "Fait quand", "Hors périmètre"); how a comment marks a decision
   or a hold.

`youtrack.md` for YouTrack: connector `youtrack`, tools `get_issue`, `get_issue_comments`,
`search_issues "links: <id>"`; default project `ERP`; Type `Bug` → `--bugs`, anything else → `--feature`.

### Steps, whatever the provider

1. **Read the card** through the provider file.
2. **Analyse the code**, before anything is written: the session reads the code the card names (classes,
   files, migrations, tests), with codebase-memory-mcp first, in the current repo and in any other repo of
   `/workspaces` the card names. Read only: nothing is built, run or edited at this stage. This is the step that
   found, for ERP-134, that the old codes `gmao-technician` and `gmao-planner` get new meanings.
3. **Write the decision file** and show it in full.
4. **Stop: "Run? go / answers".** My answers are written into the decision file (`--answer` reaches no bugfix role);
   a part or repo I drop moves to out of scope.
5. **On "go"**: write the reference file, then

   ```
   agentics run --feature|--bugs "$(cat <id>.reference.md)" --mission <id-lowercase>-<slug> --runtime …
   ```

   One run per repo: a two-repo card gets a run for the current repo, and the decision file lists the other repo
   as a decision. `--done` keeps its "Commit? yes/no".

### The two files

In `~/agentics-reports/<repo>/briefs/` (outside the repo, never committed):

1. `<id>.decision.md`, **for me**: plain English, as long as it needs, written so I can decide in one read.
2. `<id>.reference.md`, **for the agents**: at most 6000 bytes, passed as the run's description. Written only after
   my go, from the decision file with my answers in it, so the agents follow the design I approved.

**The decision file**, in this order (what I decide first, the support after):

1. **In short**: three lines. What the card wants, which repo(s), and the recommendation: *go*, *go on part of
   it*, or *wait* (and for what).
2. **Decisions for you**: numbered. Each one gives the question, the options, what each changes, the
   recommendation and why. Every gap becomes one: a question the card says to ask before coding ("demander au
   PO … avant de coder") with no answer in the comments, a second repo or one without an agentics profile, a
   part a comment puts on hold ("en attente"), a choice the code forces that the card does not settle (ERP-196
   says "ajoute les 7 rôles" while 7 GMAO roles already exist).
3. **What the card asks**: "what to build", "done when" and "out of scope", text kept verbatim in the card's
   language, each item tagged with its repo; decisions found in comments (author, date, quote); the parent story
   in two lines.
4. **Analysis, the code today**: what exists, with `file:line`; what the change touches; traps found (a reused
   code, a unique index, a test the new spec makes obsolete). Each claim says whether it was read in the code or
   is an assumption.
5. **Proposed design**: the files to create or change; the tests written first, one line each on what it
   proves; for a migration, its steps in order and whether it can be undone.
6. **Risks**: what could go wrong and its impact on data (real or personal data, a migration that cannot be
   switched off), on security (rights, 403s), on other repos or teams.
7. **How "done" is checked**: each "done when" item mapped to the test or gate that proves it, and what the run
   cannot check (a mockup, a PR, a review).
8. **Effort**: the card's estimate against what the analysis found.
9. **Sources**: the cards, comments and files read, as links.

Mockups and attachments are links only: the agents cannot open them, and the decision file says so.

### Install, in the dev container

- `render-command.sh` already renders `dev-with-agents.md`; step 9 of `install-agentic.sh` also copies, for
  the chosen providers (below), their shortcut command and their provider file.
- Which providers get installed: the names given to `install-card-providers.sh`, else `$CARD_PROVIDERS` (blank
  counts as unset), else `card-providers.conf` in the dotfiles (the container build has no terminal and clones the
  dotfiles afresh: the conf survives a rebuild once committed and pushed). The install self-check (`--check`) checks
  that the same choice is installed. `--choose` shows a numbered menu. A provider no longer chosen loses its
  provider file and shortcut.
- For each chosen provider, the install checks `claude mcp list` for its connector; a missing one prints the
  provider's add command and login, and does not fail the install.

### Tests

`render-command.test.sh` (or a new `card-providers.test.sh`), on the real files:

- the main command documents `--card-provider` and `--card`, and holds no YouTrack tool name;
- every `dev-with-agents-<p>.md` shortcut has a matching `card-providers/<p>.md`, and the reverse;
- each provider file has the four parts (connector, id, fetch, mapping);
- the command keeps the "Run? go / answers" stop and the two brief paths;
- the install copies the shortcut and provider files into a temporary `$HOME`.

## Left to the builder

- The slug: the kernel's rule (ASCII, lowercase kebab-case, at most 60 characters).
- How to cut the reference file to 6000 bytes (the design and the decisions stay whole; comments and sources go
  first).

## Not verified yet

- The YouTrack connector's OAuth login from inside the container (the browser callback goes through VS Code's
  port forwarding).
