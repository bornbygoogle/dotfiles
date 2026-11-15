---
name: 'dev-with-agents-youtrack'
description: 'Short form of /dev-with-agents --card-provider youtrack --card <id>: reads a YouTrack card, analyses the code, shows a decision brief and waits for "go" before running the agentics pipeline. Usage: /dev-with-agents-youtrack <number|id>   e.g. /dev-with-agents-youtrack 196'
---

# /dev-with-agents-youtrack

`$ARGUMENTS` is a card number or id. A bare number gets the default project key from
`~/.claude/card-providers/youtrack.md` (`196` → `ERP-196`).
An argument that already holds a project key, with a `-` (`ABC-12`), is used as it is: never `ERP-ABC-12`.

Then do exactly what `/dev-with-agents --card-provider youtrack --card <id>` does: follow
`~/.claude/commands/dev-with-agents.md`, section "Start from a card", with that id. No argument: show the usage
line above and stop.
