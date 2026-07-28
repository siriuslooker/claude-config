---
description: Draft a concise bulleted Jira comment summarizing recent work, print it for approval, and post it only after the user approves.
argument-hint: <ISSUE-KEY?> [--since <ref>] [--edit <comment-id>]
allowed-tools: Bash(git:*), Bash(jq:*), Bash(curl:*), Read, Write, Edit, AskUserQuestion
---

Post a concise, bulleted summary of recent work as a comment on a Jira issue. Uses the Jira Cloud
REST API directly with the token in `~/.claude/credentials.json` (the Atlassian MCP is often
unauthenticated, and this avoids an OAuth round trip).

**The hard rule: never post without showing the draft first and getting explicit approval.** See §4.

## Arguments

`$ARGUMENTS` — all optional:

- **`$1`** — the issue key (e.g. `EN-957`). Usually unnecessary; see §1.
- **`--since <ref>`** — summarize commits since this git ref instead of the default range.
- **`--edit <comment-id>`** — rewrite an existing comment in place instead of adding a new one.

## 1. Resolve the issue key (do not just ask)

In this order, stopping at the first that works:

1. **`$1`**, if given and it looks like a key (`^[A-Z][A-Z0-9]*-\d+$`).
2. **The current git branch**, if it matches that same pattern. Branch name *is* the ticket key by
   convention on this machine, so this is the common case — `git rev-parse --abbrev-ref HEAD`.
3. **A recorded project key** — look for `jiraKey` in `.claude/jira.json`, then for a Jira key in the
   project's `CLAUDE.md`.
4. **Ask the user**, then **record it** so this never has to be asked again in this project: write
   `{"jiraKey": "ABC-123"}` to `.claude/jira.json` and tell the user you did. If the project's
   `CLAUDE.md` has a natural "facts worth knowing" type section, add a one-line note there instead —
   it travels with the repo for teammates. Do **not** put it in `settings.local.json` (gitignored,
   so the next person re-answers the same question).

Always state which key you resolved and how ("using EN-957 from the current branch") before drafting.
Getting this wrong posts someone else's work to the wrong ticket.

## 2. Gather the evidence

Summarize **what actually happened**, from two sources:

- **This session's work** — what was built, decided, verified, and deliberately left undone. This is
  the important half: verification results, known gaps, and "why" are things no commit message holds.
- **The commits** — cross-check against `git log --oneline <range>` and `git diff --stat <range>`.
  Default range is the current branch's commits not yet on the main branch
  (`git log --oneline main..HEAD`, or `origin/main..HEAD` if that is more accurate); with
  `--since <ref>`, use `<ref>..HEAD`. If the branch is already merged, fall back to the commits
  referencing the issue key (`git log --oneline --grep <KEY>`).

If a fresh context has no session history, say so plainly and summarize from git alone rather than
inventing detail.

## 3. Draft the comment

Format: **one bolded lead line, then bullets.** Aim for **8–12 bullets, ~1500–2000 characters.**
Prose paragraphs, fenced code blocks, and tables are what this command exists to avoid.

Use Jira **wiki markup** (`/rest/api/2` accepts it — see §6):

- `*bold*`, `_italic_`, `{{monospace}}`, `* ` for bullets, `h4.` for a heading if you truly need one.

Cover, in roughly this order, skipping any that don't apply:

- **What changed** and where it landed (PR number, merge commit).
- **Bug / cause / fix** as separate bullets when this was a defect. State the root cause as
  *confirmed*, and say how it was confirmed — not as a guess.
- **Any durable lesson** worth a future reader's attention.
- **Other changes** carried along (docs, tooling, config).
- **Verified** — one bullet, comma-separated results. Not a table.
- **Gaps left open** — what was deliberately not fixed, and why. Do not quietly omit these.
- **Next** — the immediate follow-on work.

Be specific: file paths, error text, commit SHAs, status codes. Vague summaries are worthless on a
ticket read six months later.

## 4. Print it and STOP

Print the full draft to the user, then **stop and wait for explicit approval.** Do not post in the
same turn as the draft. If they ask for changes, revise and print again — still without posting.

*(Note: `allowed-tools` above pre-authorizes `curl`, so this gate is instruction-only. If you want it
enforced structurally, remove `Bash(curl:*)` from the frontmatter — the POST will then always raise a
permission prompt as a second, independent gate.)*

## 5. Post it

Read the token inside the command; **never echo it.** Build the JSON with `jq -Rs` rather than
hand-quoting — the body contains characters that will otherwise break the payload.

```
jq -Rs '{body:.}' draft.txt > payload.json

tok=$(jq -r '.credentials[]|select(.label=="Jira API (<work-org>)").password' ~/.claude/credentials.json)
curl -s -w "HTTP_STATUS:%{http_code}\n" -X POST \
  -H "Content-Type: application/json" \
  -u "<work-email>:$tok" \
  --data-binary "@payload.json" \
  "https://<jira-site>/rest/api/2/issue/<KEY>/comment"
```

Expect `201`. With `--edit <comment-id>`, use `-X PUT` against
`.../issue/<KEY>/comment/<comment-id>` and expect `200`.

## 6. Verify — a 2xx does not mean it stored

**Always re-read the comment after writing and confirm it survived.** Jira converts wiki markup to
ADF on the way in, and content can be *silently dropped* while still returning success. This is
observed, not theoretical: a `204` description update once discarded everything after a `----` rule.

```
curl -s -u "<work-email>:$tok" \
  "https://<jira-site>/rest/api/2/issue/<KEY>/comment/<id>" \
  | jq -r '"chars: \(.body|length)", "bullets: \([.body|split("\n")[]|select(startswith("* "))]|length)", "ends with: \(.body|split("\n")|map(select(length>0))|last|.[0:60])"'
```

Check the bullet count matches what you drafted and the final bullet is intact. Report the comment id
and the verified counts. If content was dropped, fix the markup and re-`PUT` — do not leave a
truncated comment sitting on the ticket.

**Markup that does not round-trip** (avoid):

- `----` horizontal rules — content *after* them can vanish.
- `{quote}` blocks containing `[~accountid:...]` mentions.
- Prefer `/rest/api/2` (wiki markup) over `/rest/api/3` (requires hand-built ADF JSON).

## 7. Failure modes

- **401** — the token is likely rotated. Tell the user to regenerate it at
  `id.atlassian.com/manage-profile/security/api-tokens` and update the `"Jira API (<work-org>)"`
  entry's `password` in `~/.claude/credentials.json`. Do not retry blindly.
- **404** — wrong key, or the issue isn't visible to this account. Re-check the key and how it was
  resolved (§1); do not guess a different one.
- **400** — almost always a malformed body. Re-check that `jq -Rs` built the payload.

## Notes

- Auth host is the site URL `<jira-site>`, **not** `api.atlassian.com/ex/jira/<cloudId>`.
  Basic auth = `email:api-token`.
- The token in `credentials.json` is Jira-scoped; the separate `"Bitbucket API (<work-org>)"` entry
  in the same file returns 401 against Jira — don't use it here.
- Companion command: **`/jira-attach`** for uploading files (the REST attachment endpoint needs a
  different content type and the `X-Atlassian-Token: no-check` header).
- **Never mention Claude or AI** in comment text.
- Write the draft to a scratch file rather than inlining a long body on the command line — quoting a
  multi-line body through a shell is where this breaks.
