---
name: create_jira_teams
description: Turn a bug report posted in Microsoft Teams into properly-formed Jira tickets. Use when the user pastes a Teams thread, points at a Teams channel, or asks to file issues someone reported in chat instead of Jira. Handles splitting a rambling multi-issue message into discrete tickets, duplicate detection against existing issues, and a draft-then-approve flow.
---

# Teams → Jira

Product owners and QA folks report bugs in Teams chat rather than Jira. The messages are
conversational: several unrelated defects in one post, mixed with scheduling notes and
design musings. This skill converts one of those messages into clean tickets without
losing anything and without filing noise.

## Resolving the target

Nothing about the destination is hardcoded here — this file is version-controlled in a
public repo, so every site-specific value is read at runtime.

| Setting | Where it comes from |
| --- | --- |
| Jira site | The Jira entry's `hosts[0]` in `~/.claude/credentials.json` — the entry whose label starts with `"Jira API"`. Same resolution `/jira-comment`, `/jira-attach` and `/jira-update` use. |
| cloudId | Do not hardcode one. `getAccessibleAtlassianResources` returns it for the resolved site; the REST path the `/jira-*` commands use does not need it at all. |
| Project | Passed as an argument, named by the user, or — if neither — listed with `getVisibleJiraProjects` and **asked**. Never guessed. Once established, use it for every step in the run. |
| Issue types | Read from `getJiraProjectIssueTypesMetadata` for the resolved project rather than assumed; the common set is Bug, Task, New Feature, Epic, Sub-task. |
| Reporter | Always the authenticated user. The API cannot set another reporter — credit the original reporter in the description instead. |
| Default mode | **Draft, then wait for approval.** Never create without an explicit go-ahead. |

Sibling projects usually exist alongside the main one. Default to the project established
above; only use another if the user says so.

```bash
jira=$(jq -r '[.credentials[]|select(.label|startswith("Jira API"))][0]' ~/.claude/credentials.json)
site=$(jq -r '.hosts[0]' <<<"$jira")
```

## Getting the thread

In order of preference:

1. **User pastes it** — fastest, and unambiguous. Take it as-is.
2. **Microsoft 365 connector** — `chat_message_search` reaches Teams messages. The
   connector may be toggled **off** for the current chat; if its tools are absent, say so
   and tell the user to enable it in this conversation's connector settings rather than
   trying to work around it.
3. **Claude in Chrome** on `teams.microsoft.com` — brittle, slow. Last resort only.

Screenshots referenced in a message ("odd wrapping with the reporter's name:") frequently
do not survive the copy-paste. If the text points at an image you cannot see, flag the gap
explicitly rather than inventing what it showed.

## Splitting the message

One ticket per independently-fixable defect. Work through the message and sort every
statement into one of three buckets:

- **Ticket** — a reproducible defect or a concrete change request.
- **Context for a ticket** — environment, version, affected user, "confirm before fixing".
  Folds into the relevant ticket's description; never its own ticket.
- **Not a ticket** — production freeze windows, apologies, "don't deploy at 11am",
  status chatter. Report these back to the user in chat as operational notes. Filing
  them as Jira issues is the failure mode this skill exists to prevent.

Two symptoms that share a single root cause and one fix are one ticket. Two symptoms
in the same feature area that would be fixed in different code paths are two tickets —
splitting is cheaper to undo than merging.

Watch for the platform axis. Where the project's existing convention prefixes summaries
with the surface — `[iOS]`, `[Android]`, `[.NET]` — follow it, and check whether the same
defect on web and mobile is conventionally two tickets there. If the reporter says "on the
web" and does not mention mobile, scope the ticket to web and add an open question about
whether mobile needs a sibling.

## Duplicate check

Before drafting, run `searchJiraIssuesUsingJql` against the project for each candidate.
Use two or three distinct phrasings of the symptom — reporters and past ticket authors
rarely pick the same words:

```
project = <KEY> AND text ~ "<symptom phrasing 1>" ORDER BY created DESC
project = <KEY> AND text ~ "<symptom phrasing 2>" ORDER BY created DESC
```

Classify each hit:

- **True duplicate, open** → don't draft. Propose a comment on the existing issue.
- **True duplicate, Done** → the fix regressed, or shipped only on one platform.
  Draft a new ticket and reference the old one; do not reopen without being asked.
- **Related** → draft the new ticket and note the link. Relates-to links are cheap
  and make the pattern visible to whoever picks up the fix.

Pull `key`, `summary`, `status`, `issuetype` only. The full field payload for a mature
project is enormous and will blow the tool-output limit.

## Ticket shape

Match the terse, surface-prefixed style already in the project.

**Summary** — one line, under ~100 chars, leads with the surface, states the observed
wrong behavior. Not the suspected cause, not the fix.

- Good: `[.NET] Item created while the owning permission is revoked cannot be edited or deleted`
- Bad: `Fix privilege caching bug` (that's a hypothesis) / `Appointment problem` (says nothing)

**Description** — pass `contentFormat: "markdown"` to `createJiraIssue` and write plain
Markdown; it converts cleanly, including tables. Structure:

```markdown
**Reported by** <name> in Teams, <date>.

### Steps to reproduce
1. ...
2. ...

### Expected
...

### Actual
...

### Notes
- Reporter asked that this be confirmed by QA before a fix is written.
- Related: <KEY>-xxx — <summary> (<status>). <why it matters>
- Scoped to <surface> only per reporter. <Other surface> not assessed.
```

A "Related" line is worth little without the reason. `Related: <KEY>-891` is a shrug;
`Related: <KEY>-891 — conditional prompt shown unconditionally on iOS; the fix may point
at the shared logic` saves the assignee an hour.

For a design Task, replace Expected/Actual with **Observed**, **Cause (likely)**, and an
**Options to consider** table with a trade-off column and a recommendation. A design
ticket with no options enumerated just moves the thinking to someone else's queue.

Keep the reporter's own words for the repro steps where they're already clear. Do not
smooth them into your own phrasing — the specific wording is evidence.

**Issue type** — Bug when something behaves incorrectly. Task for polish, cleanup, or
"we should think about this." Design questions with no agreed answer are a Task with
the open question in the description, not a Bug.

**Fields to leave alone unless told** — assignee, priority, sprint, story points.

**fixVersion** — release strings often look like `2026.v3`, `2026.v4`. If the reporter
says "fix in v4," confirm the exact string with the user, then validate it exists before
creating; `createJiraIssue` fails outright on an unknown version name. Cheapest validation
is a JQL probe:

```
project = <KEY> AND fixVersion = "2026.v4"
```

A result set (or an empty one) means the version exists. A JQL error means it does not —
go back to the user rather than guessing.

**Attachments** — the Atlassian MCP has no attachment endpoint. Screenshots cannot be
uploaded programmatically. Reference them in the description, transcribe what they show
in enough detail that the ticket stands alone without them, and tell the user to drag
the images onto the issue. Never let a ticket depend on an image that isn't there.
(`/jira-attach` uploads files over the REST API if you have them locally.)

## The approval loop

1. Present every draft in chat as a table or short block — summary, type, description,
   related issues.
2. List what you deliberately did **not** file, and why.
3. Batch open questions, numbered, so the user can answer by number.
4. Wait. On approval, create with `createJiraIssue`, then report back the keys and
   browse URLs. Add relates-to links with `createIssueLink` after creation.

If the user approves a subset ("do 1 and 2, drop 3"), create only those and say plainly
which were skipped.

## Reporting back

Give the created keys as links (`https://<site>/browse/<KEY>-xxxx`, using the resolved
site), then a short summary of what changed and what's still open. Do not re-paste the
full descriptions — the user just read and approved them.
