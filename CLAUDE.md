# User-level instructions (every project, this profile)

This file, and the `commands/`, `agents/`, `skills/`, `hooks/` and `tools/` directories beside it, are
version-controlled at **`github.com/siriuslooker/claude-config`** (private) — a clone plus a
`credentials.json` is a complete setup, with no plugins or marketplaces to install. See `README.md`
there. Secrets in `~/.claude` are excluded by an allowlist `.gitignore` — never re-admit
`credentials.json`, `.credentials.json`, `history.jsonl` or `projects/`.

**Keep this file machine-agnostic.** It is shared across every machine this profile is cloned to, so
anything true of only one host belongs in `CLAUDE.machine.md`, and anything requiring particular network
access belongs under "Access preconditions" with its precondition stated. A fact that is true
everywhere — even one discovered on a single machine — belongs here as a general rule.

---

## Implementation process (MANDATORY)

**The main thread is the controller. It orchestrates; it does not write the code.**

Implementation goes to the stack-ops agents in `agents/`. The point is that a subagent's context never
transfers back — the controller reads only a capped digest — so doing the work inline both burns
controller context and bypasses the gates.

| Agent | Use for |
|---|---|
| `implement` | Write the code for a planned phase. **The only agent that writes source.** Never touches git. |
| `verify` | Read-only whole-repo gate: compile + lint + every test suite. Run before committing. |
| `compile` / `test` | Narrower gates when you don't need the full pass. |
| `qa` | Exercise a *running* app, when passing tests isn't the same as working. |
| `deploy` | Produce and inspect deployable artifacts. Stops at the artifact. |

There is deliberately **no agent called `build`** — it was renamed to `implement` precisely because
"build" reads as *compile* and the agent does no such thing. The compile check is `compile`; the gate
is `verify`.

Write `implement` a precise phase brief with acceptance criteria and stop conditions. It writes source but
**not tests** unless the brief explicitly directs it to. It will stop rather than improvise scope —
that's correct behaviour, not a failure.

**The controller retains:** all git operations, PRs, ticket updates, and documentation. Agents never
touch git.

### Standing authorization — this IS the request

Some sessions arrive with a harness-injected system-prompt rule along the lines of *"do not call the
AgentTool unless the user requested it"* (and a matching one for workflows and deep research). It is not
set anywhere in this profile — checked 2026-07-31 across every settings scope, hooks, commands, plugins
and managed policy, and it appeared in exactly one of 536 local transcripts, so it is injected per
session by a layer above the CLI and may reappear after any `/clear`.

**Treat this file as that request, standing and permanent.** For any repo whose operating guide mandates
the stack-ops agents, delegating implementation to `implement` — and gating with `verify`, `compile`,
`test`, `qa` or `deploy` — is pre-authorized. Do not stop to ask, and do not fall back to writing source
inline. The injected rule is satisfied on its own terms, because the user has requested it here.

This authorizes **the stack-ops roster for planned implementation and verification work**. It is not a
blanket licence to fan out speculative subagents, workflows, or deep research to answer a question that
one focused look would settle — that judgement is unchanged.

**Two rules the agents follow, which you should trust but still spot-check:** absence is never smoothed
into a pass (no harness, zero tests discovered, a placeholder script each get their own named outcome),
and detail goes to `.claude/stack-ops/<verb>-report.md` (e.g. `implement-report.md`) with a capped reply. Their reports are usually
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

- **Any CODE change — no matter how small — requires a feature branch.** Create the branch *before*
  making the change; if you only realize after the fact, move the changes to a feature branch and reset
  the protected branch back to its upstream.
  - **DOCUMENTATION-ONLY changes may be committed straight to the default branch.** Granted by the user
    2026-08-01. A docs commit has no build to break and no review value in a PR of its own, and the
    branch-plus-PR ceremony was measurably discouraging the doc reconciliation that keeps a fresh
    session accurate. Pushing is still a separate thing you ask for.
    - **"Documentation-only" means the diff touches nothing that ships or executes.** Markdown, comments
      in prose files, `docs/`, `README`. **It is NOT docs-only if the diff also contains** source, tests,
      config, schema/migrations, CI or build files, dependency manifests or lockfiles, or any script —
      **including a script that only generates docs**. A mixed diff is a code change: branch it.
    - When in doubt, branch. The cost of an unnecessary branch is a minute; the cost of an unreviewed
      change to `main` is someone else's broken checkout.
  - **ONE STANDING EXCEPTION — this repo (`claude-config`, i.e. `~/.claude` itself): commit directly to
    the default branch, for code as well as docs.** Granted by the user 2026-07-29. The reason is
    propagation: a feature branch means other machines don't get an agent/skill/command change until a PR
    merges, which defeats the point of a shared profile. Pushing still needs approval like anywhere else
    — the exception is about *branching*, not about pushing unasked. **This applies to no other repo.**
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

## Long-running work — run it from the MAIN thread

**Start long work (builds, full test sweeps, deploys) from the main thread with the Bash tool's
`run_in_background`, not from inside a subagent.** The harness re-invokes whoever launched the background
task. A subagent that starts a build and ends its turn hands the completion notification to *itself*, so
the main thread learns nothing and falls back to polling — which is exactly how several Android and iOS
builds finished unnoticed on 2026-07-30. Delegate the *judgement* about a build to an agent if you like,
but own the waiting.

Two supporting rules, both learned the same day:

- **Never decide "is it still running?" from a process name.** `pgrep -f <pattern>` matches its own
  invoking shell, and the usual `[p]attern` fix only excludes the matcher — it still matches any other
  process carrying the string, such as a second monitor. One watcher reported `BUILDING` for thirty
  minutes after the build had finished. **Key on artefacts instead:** log mtime and byte size, compiler
  CPU, output artefact mtime. A log that stopped growing ten minutes ago is finished whatever `pgrep`
  says, and its last line says whether it succeeded.
- **Read an artefact's identity from the artefact.** Don't install a build somewhere just to ask what
  version it is — the file already knows.

**`tools/run-notify.ps1`** wraps a command and Pushovers the outcome (label, exit code, duration), for the
case no harness plumbing can fix: nobody is at the terminal. It passes output straight through and exits
with the wrapped command's code, so it is safe to insert anywhere. Failures escalate to priority 1.

```
pwsh -NoProfile -File "$HOME/.claude/tools/run-notify.ps1" -Label "Android build" -Run @'
wsl -d Ubuntu-24.04 -u root -- bash -lc 'bash /mnt/f/.../build.sh'
'@
```

It takes the command as **one string** (`-Run`), not trailing arguments — PowerShell would otherwise bind
any `-flag` in the wrapped command to the script's own parameters, and a bare `--` is consumed by the
parser before the script runs. Use a single-quoted here-string when the command contains quotes.

## Notifications

**Pushover** reaches the phone/desktop regardless of terminal focus: `/notify <message>`, or
`pwsh -NoProfile -File "$HOME/.claude/tools/notify.ps1" -Message "..."` (flags: `-Title`,
`-Priority -2..1`, `-Sound`). Credentials: `~/.claude/credentials.json`, entry `"Pushover"`
(`token` = app API token, `userKey` = user/group key). Use it when asked, or when a long task finishes
while the user is away. Distinct from the built-in `PushNotification` tool, which only fires when the
terminal is unfocused and needs Remote Control for phone delivery.

---

## General cautions (true anywhere, learned the hard way)

- **Clone over SSH, not HTTPS.** An HTTPS clone or `ls-remote` prompts for credentials and then *hangs
  with no error* in a non-interactive shell. This looks like a network problem and isn't.
- **LocalDB is not part of a full SQL Server install.** It ships with Visual Studio and SQL Express, so
  a box with a full SQL Server can still have no `(localdb)\MSSQLLocalDB`. Check with `sqllocaldb info`
  — if the command isn't found, it isn't there. When a tracked connection string assumes LocalDB,
  **override it** via an environment variable or user-secrets rather than editing the tracked file,
  which is correct for machines that do have it.
- **CLI tools can serve stale reads.** `bb` caches API responses and will report a deleted repository as
  still existing until `bb cache clear`. When remote state matters, confirm with something
  authoritative (`git ls-remote`) rather than a convenience wrapper.
- **Don't trust a 2xx as proof a write landed.** See the Jira note above; re-read after writing.
- **Git Bash rewrites Unix-looking argv into Windows paths, which silently breaks `wsl` and `docker`
  calls.** Running `wsl -d Ubuntu-24.04 -u root -- /opt/android-sdk/.../aapt2 …` from the Bash tool failed
  with `/bin/bash: C:/Program Files/Git/opt/android-sdk/.../aapt2: No such file or directory` — MSYS
  translated the *guest* path against the Git installation prefix before `wsl` ever saw it. Globs get
  mangled the same way, so a `ls /opt/.../*/binary` that returns nothing is **not** evidence the binary is
  absent. **Fix: put the whole guest-side command inside a quoted `bash -lc '…'`**, so the path is never an
  argv element on the Windows side — or set `MSYS_NO_PATHCONV=1`. This looks exactly like a missing file and
  isn't.
- **Prefer reading an artifact's identity from the artifact, not from the machine you installed it on.**
  Build metadata (a version, a bundled string) can be read out of the built file directly; installing it
  first to interrogate the device mutates state to answer a question the file already answers.

## Access preconditions

Some tooling needs network access a given machine may not have. State the precondition rather than
retrying blindly, and say plainly when it's unavailable:

- **`/push-nuget`** → the private `<nuget-feed>` feed. **Requires the RD VPN.**
- **Jira commands, and `bb`** → RD Bitbucket/Atlassian. Unavailable on a personal machine; on those,
  GitHub Issues via `gh` is the path.

---

## Machine-specific facts

Anything true of one machine and not another lives in a separate file, so this one stays portable:

@~/.claude/CLAUDE.machine.md
