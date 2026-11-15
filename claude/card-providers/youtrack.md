# Card provider: YouTrack

Read by `/dev-with-agents --card-provider youtrack --card <id>`. This file only says how to read a card in
YouTrack; the steps (analysis, decision file, "Run? go / answers", the run) are in the main command.
**Read only:** never comment, change a field, change the state or log time on the card.

## Connector

The MCP server named `youtrack` (its tools are `mcp__youtrack__*`). When its tools are missing, or answer that
you are not logged in, stop and tell the user, without guessing the company URL:

    claude mcp add --transport http --scope user youtrack <your YouTrack URL>/mcp

then `/mcp` in Claude Code to log in (once per container). Nothing else is needed: no token is stored.

## Id

`<PROJECT>-<number>`, like `ERP-196`. The default project key is `ERP`: a bare number (`196`) means `ERP-196`.
An id that already holds a project key is used as it is.

## Fetch

1. `get_issue` with the id: summary, description, type, state, sprint, estimate, custom fields, `parentIssue`,
   `linkedIssueCounts`, attachments.
2. `get_issue_comments` with the id, every page (`offset` by 10 until fewer than 10 come back). Comments come
   only from `get_issue_comments`: never use `get_issue`'s `recentComments` or `totalComments`. Those still hold
   comments their author deleted, with no marker (ERP-134, 2026-11-15), and a deleted question would show up in
   the brief as open.
3. The parent, when `parentIssue` is set: `get_issue` and all its comments (`get_issue_comments`, as above).
   A user story's comments often hold the decisions (who said what is on hold).
4. Linked cards, one level deep: `search_issues` with the query `links: <id>`, every page (`offset` by 20
   until fewer than 20 come back). Keep the id, summary, state and link type; do not open each one, except a
   card the description names as an input.
5. Attachments and links to mockups: list them as links. The agents cannot open them.

## Mapping

- **Bug or feature:** the `Type` custom field. `Bug` → `--bugs`; anything else (Task, User Story, Feature…)
  → `--feature`.
- **What to build:** the description's "Ce qu'on attend" part (or "Contexte" when there is no such part).
- **Done when:** the "Fait quand" checklist.
- **Out of scope:** the "Hors périmètre" part.
- **Inputs:** the "Entrées" part: cards, mockups, ADRs and code it names.
- **Decisions and holds:** a comment that says a part is "en attente" puts that part on hold; a comment that
  answers a question asked in the description settles it. A question the description says to ask before coding
  ("demander au PO … avant de coder") with no answer in the comments is open.
