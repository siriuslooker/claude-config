---
description: Update fields on a Jira issue (description, summary, labels) via the REST API, showing the current value and requiring approval before overwriting.
argument-hint: <ISSUE-KEY?> [--field <name>] [--append] [--from <file>]
allowed-tools: Bash(git:*), Bash(jq:*), Bash(curl:*), Bash(diff:*), Bash(mkdir:*), Read, Write, Edit, AskUserQuestion
---

Update **fields** on a Jira issue — most often `description` — using the Jira Cloud REST API with the
token in `~/.claude/credentials.json`.

**Unlike `/jira-comment`, this is destructive.** A comment is additive; a field write replaces what
was there. So this command has two extra obligations: **back up the current value before writing**
(§3) and **show the user what is being replaced** (§5).

**The hard rule: never write without showing the current value, the new value, and getting explicit
approval.** See §5.

## Arguments

`$ARGUMENTS` — all optional:

- **`$1`** — the issue key (e.g. `EN-981`). Usually unnecessary; see §1.
- **`--field <name>`** — the field to write. Defaults to `description`. Also accepts `summary`,
  `labels`, or any `customfield_*` id.
- **`--append`** — add to the end of the existing value instead of replacing it. Strongly prefer this
  when the field already has content you did not write.
- **`--from <file>`** — take the new value from this file instead of drafting one.

## 1. Resolve the issue key (do not just ask)

In this order, stopping at the first that works:

1. **`$1`**, if it looks like a key (`^[A-Z][A-Z0-9]*-\d+$`).
2. **The current git branch** — branch name *is* the ticket key by convention on this machine, so
   this is the common case: `git rev-parse --abbrev-ref HEAD`.
3. **A recorded project key** — `jiraKey` in `.claude/jira.json`, then a Jira key in the project's
   `CLAUDE.md`.
4. **Ask the user**, then record it per `/jira-comment` §1 so it is never asked again.

Always state which key you resolved and how ("using EN-981 from the current branch") before drafting.
Writing to the wrong ticket here **destroys that ticket's description** — there is no undo in the UI
beyond the issue history.

## 2. Check the project is not read-only

Some projects on this machine are explicitly **read-only until the user authorizes writes per
ticket** — the `EN` project has carried that constraint. Check the project's `CLAUDE.md` for such a
standing rule. If one exists, say so and get per-ticket authorization before doing anything else.

## 3. Read and back up the current value

Never write blind. Fetch first:

```
jira=$(jq -r '[.credentials[]|select(.label|startswith("Jira API"))][0]' ~/.claude/credentials.json)
site=$(jq -r '.hosts[0]' <<<"$jira")
user=$(jq -r '.username' <<<"$jira")
tok=$(jq -r '.password' <<<"$jira")
curl -s -u "$user:$tok" \
  "https://$site/rest/api/2/issue/<KEY>?fields=summary,status,description" \
  > current.json
jq -r '.fields.description // ""' current.json > current-desc.txt
jq -r '{key,summary:.fields.summary,status:.fields.status.name,chars:(.fields.description//""|length)}' current.json
```

Keep `current-desc.txt` in the scratchpad for the rest of the session — it is the only copy of the
pre-write value. State whether the field was **empty** (a create, nothing at risk) or **populated**
(a genuine overwrite). If populated and the content was not written by you in this session, default
to `--append` and confirm the user actually wants a replacement.

Note the `fields=` list keeps the response small; requesting `*all` on a busy issue is slow and noisy.

## 4. Draft the new value

Use Jira **wiki markup** — `/rest/api/2` accepts it, and it avoids hand-building ADF JSON:

- `h3.` / `h4.` headings, `*bold*`, `_italic_`, `{{monospace}}`, `* ` bullets, `# ` numbered.
- `||header||header||` / `|cell|cell|` for tables.

Write the draft to a **scratch file**, never inline on the command line — a multi-line body quoted
through a shell is where this breaks.

For `--append`, concatenate rather than re-sending the whole field:

```
cat current-desc.txt > new-desc.txt
printf '\n\n' >> new-desc.txt
cat addition.txt >> new-desc.txt
```

## 5. Show the change and STOP

Print, then **stop and wait for explicit approval** — do not write in the same turn as the draft:

- Which field, on which issue key.
- Whether it is a **create** (was empty) or an **overwrite** (and the current char count).
- The **full new value**. For an overwrite of long content, also show `diff current-desc.txt
  new-desc.txt` so nothing is silently dropped.

If they ask for changes, revise and print again — still without writing.

*(`allowed-tools` above pre-authorizes `curl`, so this gate is instruction-only. To make it
structural, remove `Bash(curl:*)` from the frontmatter — every write then also raises a permission
prompt.)*

## 6. Write it

Build the JSON with `jq -Rs`, never by hand-quoting:

```
jq -Rs '{fields:{description:.}}' new-desc.txt > payload.json

jira=$(jq -r '[.credentials[]|select(.label|startswith("Jira API"))][0]' ~/.claude/credentials.json)
site=$(jq -r '.hosts[0]' <<<"$jira")
user=$(jq -r '.username' <<<"$jira")
tok=$(jq -r '.password' <<<"$jira")
curl -s -w "HTTP_STATUS:%{http_code}\n" -X PUT \
  -H "Content-Type: application/json" \
  -u "$user:$tok" \
  --data-binary "@payload.json" \
  "https://$site/rest/api/2/issue/<KEY>"
```

**Expect `204 No Content`** — an empty body is success here, not a failure. Read the token inside the
command and **never echo it.**

Other field shapes:

| Field | Payload |
|---|---|
| `summary` (single line) | `jq -Rs '{fields:{summary:(.\|rtrimstr("\n"))}}' new-summary.txt` |
| `labels` (replace) | `jq -n '{fields:{labels:["ci","mobile"]}}'` |
| `labels` (add one) | `jq -n '{update:{labels:[{add:"mobile"}]}}'` |
| Clear a field | `jq -n '{fields:{description:null}}'` |

## 7. Verify — a 204 does not mean it stored

**Always re-read the field after writing.** Jira converts wiki markup to ADF on the way in and can
*silently drop* content while still returning success. This is observed, not theoretical: a `204`
description update once discarded everything after a `----` rule.

```
curl -s -u "$user:$tok" \
  "https://$site/rest/api/2/issue/<KEY>?fields=description" \
  | jq -r '.fields.description' > stored-desc.txt
diff new-desc.txt stored-desc.txt && echo "IDENTICAL" || echo "DIFFERS — inspect above"
```

Some reflow is normal (markdown-style `-` bullets come back as `*`, a trailing newline is added).
**Structural loss is not** — check the last line survived and the section count matches. Report the
verified char count and the browse URL. If content was dropped, fix the markup and re-`PUT`; do not
leave a truncated description on the ticket.

**Markup that does not round-trip** (avoid):

- `----` horizontal rules — content *after* them can vanish.
- `{quote}` blocks containing `[~accountid:...]` mentions.
- Prefer `/rest/api/2` (wiki markup) over `/rest/api/3` (requires hand-built ADF JSON).

## 8. Failure modes

- **401** — token likely rotated. Tell the user to regenerate at
  `id.atlassian.com/manage-profile/security/api-tokens` and update the Jira entry's (label prefix
  `"Jira API"`) `password` in `~/.claude/credentials.json`. Do not retry blindly.
- **404** — wrong key, or not visible to this account. Re-check §1; do not guess another key.
- **400** — malformed body, or a field that is not on the issue's edit screen. Confirm `jq -Rs` built
  the payload, then check the field is editable:
  `curl -s -u ... ".../issue/<KEY>/editmeta" | jq -r '.fields|keys[]'`.
- **403** — the field is locked by a workflow or screen configuration, not a credential problem.

## Notes

- **Why this command exists:** a bare `curl -X PUT` from a normal session gets denied by the auto-mode
  permission classifier, because the machine's allow list grants only read-only curl (`-i`, `-I`,
  `-sI`, `-o /tmp/*`). The `allowed-tools` frontmatter above scopes the write grant to *this command*
  instead of widening shell network-write permissions globally.
- **Alternative path:** when the Atlassian MCP is authenticated (`/mcp` → claude.ai Atlassian), prefer
  `mcp__claude_ai_Atlassian__editJiraIssue` — MCP calls are not subject to the Bash classifier, and it
  takes `contentFormat: "markdown"`. That authentication does not persist across sessions, which is
  why this REST fallback stays useful. Its `cloudId` accepts the bare host (the Jira entry's
  `hosts[0]`); it returns the saved issue, but §7 still applies.
- Auth host is the site URL (the Jira entry's `hosts[0]`), **not** `api.atlassian.com/ex/jira/<cloudId>`.
  Basic auth = `email:api-token`.
- The token in `credentials.json` is Jira-scoped; the Bitbucket entry (label prefix `"Bitbucket API"`)
  in the same file returns 401 against Jira — don't use it here.
- Companion commands: **`/jira-comment`** to add a comment, **`/jira-attach`** to upload files.
- **Never mention Claude or AI** in any field text.
