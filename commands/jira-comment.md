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

- **This session's work** — what was built, fixed and confirmed working. Gather what was left undone
  too, so you know the shape of things, but see §3: it does **not** go in the comment.
- **The commits** — cross-check against `git log --oneline <range>` and `git diff --stat <range>`.
  Default range is the current branch's commits not yet on the main branch
  (`git log --oneline main..HEAD`, or `origin/main..HEAD` if that is more accurate); with
  `--since <ref>`, use `<ref>..HEAD`. If the branch is already merged, fall back to the commits
  referencing the issue key (`git log --oneline --grep <KEY>`).

If a fresh context has no session history, say so plainly and summarize from git alone rather than
inventing detail.

## 3. Draft the comment

Format: **one bolded lead line, then bullets.**

### ⛔ Length is a HARD CAP, not a target

**Maximum 10 bullets. Maximum 1500 characters. Maximum ~25 words per bullet.**

These are ceilings you stay under, not lengths you fill. **Six tight bullets beat ten padded ones.**
Prose paragraphs, fenced code blocks, and tables are what this command exists to avoid.

⚠️ **Count both before printing the draft, and state the counts to the user.** If either is over,
*cut before printing* — do not print a long draft and offer to shorten it. Offering to trim is not a
substitute for trimming; the user should never have to ask twice.

**When the work spans several increments, that is a reason to compress, not to exceed the cap.** One
bullet per increment, not one per detail within it. A session covering three pieces of work gets the
same 10 bullets as a session covering one. If it genuinely will not fit, post the *most recent* work
and say so in one line — do not silently widen the scope to justify the length.

**Cut these first — they are where the bloat always comes from:**

- Measurements, byte counts and timings, unless the number *is* the finding.
- A separate "cause confirmed" bullet — fold the how-confirmed into the bug bullet as a clause.
- Anything already obvious from a linked PR diff.
- Background, rationale and design reasoning. The decision log holds that; the ticket does not.

A reader should get the whole picture in about thirty seconds. If yours takes longer, it is too long.

### ⛔ Never include these three

Not "keep them brief" — **leave them out entirely.** All three are things the ticket's audience does
not read a comment for, and each one reliably drags a draft over the cap.

1. **No git commit IDs.** No SHAs, no `abc1234`, no commit ranges, no "three commits on branch X".
   A *PR number* is fine and often useful — a commit hash means nothing to a reader who is not in the
   working copy, and the PR already links the diff.
2. **No unit test results.** No pass counts, no "236 .NET / 69 SPA", no "build and lint clean". Green
   tests are the baseline for calling work done, not a finding. Verification that a *human* could not
   have assumed is still worth a clause — "confirmed in the backoffice embed as an event-limited
   admin" — but a number from a test runner never is.
3. **No "open", "gaps", "next" or "in flight".** **Constrain the comment strictly to what was
   completed.** Work that has not landed does not go on the ticket in any form, including a single
   trailing line. Deliberate omissions, known gaps and follow-on work belong in the project's own
   status doc and deferred-items list, where they are tracked and revisited; a ticket comment is a
   record of what shipped, and a reader six months later needs to know what is true, not what was
   pending on a Tuesday.

⚠️ These override anything above that appears to invite such content. If applying them leaves you
with very little to say, that is the correct outcome — post the short version rather than padding it
back out with status.

Use Jira **wiki markup** (`/rest/api/2` accepts it — see §6):

- `*bold*`, `_italic_`, `{{monospace}}`, `* ` for bullets, `h4.` for a heading if you truly need one.

Cover, in roughly this order, **skipping freely** — this is a menu to select from, not a checklist to
complete. Most comments should not have all five:

- **What changed** and where it landed (PR number, if there is one).
- **Bug / cause / fix** when this was a defect — the root cause as *confirmed*, with how it was
  confirmed as a clause, not as its own bullet.
- **Any durable lesson** worth a future reader's attention.
- **Other changes** carried along (docs, tooling, config).
- **Confirmed working** — only where a human could not have assumed it, and never test-runner output.

Be specific: file paths, error text, status codes. Vague summaries are worthless on a ticket read six
months later — but specificity means naming the *thing*, not appending a measurement to it.

## 4. Print it and STOP

Print the full draft to the user, then **stop and wait for explicit approval.** Do not post in the
same turn as the draft. If they ask for changes, revise and print again — still without posting.

State the bullet count and character count with the draft, so the cap in §3 is visibly met. If you
find yourself writing "longer than the target, I can tighten it if you prefer" — stop and tighten it
first. That sentence means the draft should not have been printed.

*(Note: `allowed-tools` above pre-authorizes `curl`, so this gate is instruction-only. If you want it
enforced structurally, remove `Bash(curl:*)` from the frontmatter — the POST will then always raise a
permission prompt as a second, independent gate.)*

## 5. Post it

Read the token inside the command; **never echo it.** Build the JSON with `jq -Rs` rather than
hand-quoting — the body contains characters that will otherwise break the payload.

```
jq -Rs '{body:.}' draft.txt > payload.json

jira=$(jq -r '[.credentials[]|select(.label|startswith("Jira API"))][0]' ~/.claude/credentials.json)
site=$(jq -r '.hosts[0]' <<<"$jira")
user=$(jq -r '.username' <<<"$jira")
tok=$(jq -r '.password' <<<"$jira")
curl -s -w "HTTP_STATUS:%{http_code}\n" -X POST \
  -H "Content-Type: application/json" \
  -u "$user:$tok" \
  --data-binary "@payload.json" \
  "https://$site/rest/api/2/issue/<KEY>/comment"
```

Expect `201`. With `--edit <comment-id>`, use `-X PUT` against
`.../issue/<KEY>/comment/<comment-id>` and expect `200`.

## 6. Verify — a 2xx does not mean it stored

**Always re-read the comment after writing and confirm it survived.** Jira converts wiki markup to
ADF on the way in, and content can be *silently dropped* while still returning success. This is
observed, not theoretical: a `204` description update once discarded everything after a `----` rule.

```
curl -s -u "$user:$tok" \
  "https://$site/rest/api/2/issue/<KEY>/comment/<id>" \
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
  `id.atlassian.com/manage-profile/security/api-tokens` and update the Jira entry's (label prefix
  `"Jira API"`) `password` in `~/.claude/credentials.json`. Do not retry blindly.
- **404** — wrong key, or the issue isn't visible to this account. Re-check the key and how it was
  resolved (§1); do not guess a different one.
- **400** — almost always a malformed body. Re-check that `jq -Rs` built the payload.

## Notes

- Auth host is the site URL (the Jira entry's `hosts[0]`), **not** `api.atlassian.com/ex/jira/<cloudId>`.
  Basic auth = `email:api-token`.
- The token in `credentials.json` is Jira-scoped; the separate Bitbucket entry (label prefix
  `"Bitbucket API"`) in the same file returns 401 against Jira — don't use it here.
- Companion command: **`/jira-attach`** for uploading files (the REST attachment endpoint needs a
  different content type and the `X-Atlassian-Token: no-check` header).
- **Never mention Claude or AI** in comment text.
- Write the draft to a scratch file rather than inlining a long body on the command line — quoting a
  multi-line body through a shell is where this breaks.
