# User-level instructions (all projects on this machine)

This file, and the `commands/`, `agents/`, `skills/`, `hooks/` and `tools/` directories beside it, are
version-controlled at **`github.com/siriuslooker/claude-config`** (private) — a clone plus a
`credentials.json` is a complete setup, with no plugins or marketplaces to install. See `README.md`
there. Secrets in `~/.claude` are excluded by an allowlist `.gitignore` — never re-admit
`credentials.json`, `.credentials.json`, `history.jsonl` or `projects/`.

---

## Implementation process (MANDATORY)

**The main thread is the controller. It orchestrates; it does not write the code.**

Implementation goes to the stack-ops agents in `agents/`. The point is that a subagent's context never
transfers back — the controller reads only a capped digest — so doing the work inline both burns
controller context and bypasses the gates.

| Agent | Use for |
|---|---|
| `build` | Implement a phase. **The only agent that writes source.** Never touches git. |
| `verify` | Read-only whole-repo gate: compile + lint + every test suite. Run before committing. |
| `compile` / `test` | Narrower gates when you don't need the full pass. |
| `qa` | Exercise a *running* app, when passing tests isn't the same as working. |
| `deploy` | Produce and inspect deployable artifacts. Stops at the artifact. |

⚠️ **`build` means "implement the current phase", not `dotnet build`.** These are deliberately bare,
generic names now that they are user-level agents rather than namespaced plugin ones — so read the table
above rather than assuming from the name. The compile check is `compile`; the gate is `verify`.

Write `build` a precise phase brief with acceptance criteria and stop conditions. It writes source but
**not tests** unless the brief explicitly directs it to. It will stop rather than improvise scope —
that's correct behaviour, not a failure.

**The controller retains:** all git operations, PRs, ticket updates, and documentation. Agents never
touch git.

**Two rules the agents follow, which you should trust but still spot-check:** absence is never smoothed
into a pass (no harness, zero tests discovered, a placeholder script each get their own named outcome),
and detail goes to `.claude/stack-ops/<verb>-report.md` with a capped reply. Their reports are usually
accurate but not infallible — verify claims about repo state (e.g. "that file is gitignored") yourself
before acting on them.

### A stack with no skill

If `stack-detect` reports anything under **`Unhandled`**, or the repo's language has no `compile-*`
skill, **stop and author the skill first** — see the **`authoring-stack-ops-skills`** skill. Do not let
an agent substitute another stack's skill; `dotnet build` on an old-style `.csproj` fails in ways that
look like source errors. New skills go in `~/.claude/skills/` beside the existing ones, and require a
**session restart** before they resolve. Only `netcore` and `node` are implemented today.

---

## Session workflow

Every project should carry the four session commands and the `docs/` scaffold they maintain:

- **`/init-project`** — once, on a fresh project: interviews you and writes `CLAUDE.md` plus the `docs/`
  baseline.
- **`/start-session`** — first thing in a fresh context: reads the docs and git state, then briefs you.
- **`/save-context`** — mid-session checkpoint. Freshens status only. Safe to run repeatedly.
- **`/end-session`** — real close-out: reconciles status, **appends to the decision log**, records
  deferrals, stamps the doc index.

The scaffold these assume: `1-documentation-index.md` (the catalogue — consult before opening docs by
guesswork), `2-project-status.md` (living now-state; read first, update last), `3-project-roadmap.md`,
`4-decision-log.md` (**append-only** — never rewrite), `5-deferred-items.md` (punted items, each with a
revisit *trigger*).

Decisions and their rationale belong in the decision log, not in a commit message alone. If you make a
call that would otherwise be re-litigated later, park a note for the next `/end-session`.

---

## Ticketing — provider depends on the project

Determine the provider from the **git remote**, unless the project's own `CLAUDE.md` states otherwise:

| Remote | Provider | Ticket form |
|---|---|---|
| `bitbucket.org/<work-org>/...` | **Jira** (`<jira-site>`) | `EN-957` |
| `github.com/siriuslooker/...` | **GitHub Issues** | `GH-42` |

If the remote is neither, or there's no ticket, **ask** before branching.

### Jira (RD work)

The Atlassian MCP servers are often unauthenticated and have **no attachment endpoint**, so these use
the REST API with the token in `~/.claude/credentials.json` (entry `"Jira API (<work-org>)"`):

- **`/jira-comment`** — draft a concise bulleted summary of recent work, print it, post only on approval.
- **`/jira-attach <ISSUE-KEY> <file>...`** — upload files.
- **`/jira-update`** — change description/summary/labels, showing the current value first.

Use `/rest/api/2` (accepts wiki markup) over `/rest/api/3` (needs hand-built ADF JSON). **A 2xx does not
mean it stored** — Jira converts markup to ADF on the way in and can silently drop content. Always
re-read after writing. Known casualties: `----` horizontal rules (content *after* them vanishes) and
`{quote}` blocks containing `[~accountid:...]` mentions.

### GitHub Issues (personal work)

Use the `gh` CLI: `gh issue list`, `gh issue comment <n> --body-file <f>`, `gh pr create`. Same
discipline as the Jira commands — draft, show, post on approval.

---

## Source control — branching & PR process (MANDATORY, all repos)

Follow these in **every** session, for **every** repo, without being reminded.

### Git

- **Never commit directly to a long-lived branch** (`master`/`main`/`development`). **Any code change —
  no matter how small — requires a feature branch.** Create the branch *before* making the change; if
  you only realize after the fact, move the changes to a feature branch and reset the protected branch
  back to its upstream.
- **Branch source:** `git fetch` first. If the repo has **`origin/development`**, cut from it; otherwise
  cut from `main`/`master`.
- **Branch name = `<ticket>-<summary>`.**
  - Summary **≤ 25 characters**, lowercase, hyphen-separated, describing the work not the ticket.
  - Ticket prefix per the table above: `EN-957-entity-readthrough`, `GH-42-fix-stale-cache`.
  - **Omit the prefix only when there is no ticket** (`fix-stale-cache`) — but ask if you can't tell
    what the work is.
  - One ticket may span several branches over time; the summary keeps them distinct. Don't reuse or
    recreate a bare ticket-key branch.
- **Pull requests:** open from the feature branch into its base (`development` if it exists, else
  `main`) when the effort is complete or when asked.
- **Bitbucket has no `gh`.** Use the **`bb` CLI** (`bb pullrequest create|merge`, `--repository
  <work-org>/<repo>`). `--dry-run` is a cheap way to confirm auth. Bitbucket PRs have an **author and
  reviewers, no assignee** — the API refuses to add the author as their own reviewer, so "assign it to
  me" is satisfied by the CLI being authenticated as you. Don't probe for credentials; test auth with an
  ordinary read.
- **Never push, force-push, or open PRs without explicit approval** — unless a project has a standing
  policy on file (see its `CLAUDE.md`).
- **Never mention Claude or AI** in any commit, PR, tag, or ticket text.
- **`.gitignore` patterns must never differ from a real source path only by case.** Git on Windows is
  case-insensitive, so `src/App/storage/` silently swallows the source folder `src/App/Storage/` — files
  are lost, not merely untracked. This cost a broken `main` once.

### SVN

- **Any change requires a branch.** Derive the path from where the working copy points:
  - `^/trunk/custom/<client_abbreviation>` → `^/branches/<client_abbreviation>/<ticket>-<summary>`
  - `^/trunk/common/code/<version>/<feature>` → `^/branches/common/<feature>/<ticket>-<summary>`
- Leaf name follows the same `<ticket>-<summary>` rule as git.
- **Never commit Sitefinity configuration** — anything under `App_Data\Sitefinity\Configuration\*.config`.
  Committing these from a dev machine breaks prod on launch.
- **`svn commit` is gated exactly like a git push.** Run `svn status`, review the diff, present the full
  path list plus the message, and wait for approval. Commit only the approved paths.

---

## Notifications

**Pushover** reaches the phone/desktop regardless of terminal focus: `/notify <message>`, or
`pwsh -NoProfile -File "$HOME/.claude/tools/notify.ps1" -Message "..."` (flags: `-Title`,
`-Priority -2..1`, `-Sound`). Credentials: `~/.claude/credentials.json`, entry `"Pushover"`
(`token` = app API token, `userKey` = user/group key). Use it when asked, or when a long task finishes
while the user is away. Distinct from the built-in `PushNotification` tool, which only fires when the
terminal is unfocused and needs Remote Control for phone delivery.

---

## Miscellaneous machine facts

- **No SQL Server LocalDB on this machine** — only a full SQL Server 2025 default instance
  (`MSSQLSERVER`). Connection strings assuming `(localdb)\MSSQLLocalDB` will not resolve; override via
  environment variable or user-secrets rather than editing a tracked settings file. LocalDB ships with
  Visual Studio and SQL Express, *not* with a full SQL Server install.
- **Clone Bitbucket repos over SSH, not HTTPS.** HTTPS prompts for credentials and hangs in a
  non-interactive shell with no error.
- **`/push-nuget`** pushes a built `.nupkg` to the private `<nuget-feed>` feed (VPN required, gated).
