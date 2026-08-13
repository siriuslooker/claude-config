# User-level instructions (every project, this profile)

This file, and the `commands/`, `agents/`, `skills/`, `hooks/` and `tools/` directories beside it, are
version-controlled at **`github.com/siriuslooker/claude-config`** — a clone plus a `credentials.json`
and a `CLAUDE.machine.md` is a complete setup, with no plugins or marketplaces to install. See
`README.md` there. Secrets in `~/.claude` are excluded by an allowlist `.gitignore` — never re-admit
`credentials.json`, `.credentials.json`, `history.jsonl` or `projects/`.

⚠️ **That repo is PUBLIC.** Nothing written into this file, or any tracked file beside it, may name a
host, an address, a device serial, a drive layout, an internal service or an employer's tenant. Where a
command needs one, it reads it from `credentials.json` at runtime — that file is gitignored and is the
right home for every such value. Per-machine facts go in `CLAUDE.machine.md`, which is gitignored too.

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

Every project should carry the session commands and the `docs/` scaffold they maintain:

- **`/init-project`** — once, on a fresh project: interviews you and writes `CLAUDE.md` plus the `docs/`
  baseline.
- **`/adopt-project`** — once, on an **existing** project that predates the scaffold: mines the repo's
  own `CLAUDE.md`, ad-hoc handoff docs and commit trail, interviews only the gaps, then writes the five
  docs and patches `CLAUDE.md`. Also relocates the current-state narrative that has usually accreted in
  `CLAUDE.md` into STATUS and the decision log, so the two can't drift. Use this, **not**
  `/init-project`, when there's already code and history.
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
| `bitbucket.org/...` (the work remote) | **Jira** (site host = the Jira entry's `hosts[0]` in `~/.claude/credentials.json`) | `EN-957` |
| `github.com/siriuslooker/...` | **GitHub Issues** | `GH-42` |

If the remote is neither, or there's no ticket, **ask** before branching.

### Jira (work)

The Atlassian MCP servers are often unauthenticated and have **no attachment endpoint**, so these use
the REST API with the token in `~/.claude/credentials.json` (the entry whose label starts with
`"Jira API"`):

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
  <org>/<repo>`). `--dry-run` is a cheap way to confirm auth. Bitbucket PRs have an **author and
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

### Make a background task VISIBLE — `tools/bg-task.sh`

A session waiting on a five-minute build looks completely idle. Subagents appear in the status bar;
background bash tasks did not, so wrap long `run_in_background` commands and they will:

```
bash ~/.claude/tools/bg-task.sh "Android build" "bash scripts/build.sh"
```

Label first, command as **one string** — same shape as `run-notify.ps1`, and equally transparent:
stdout/stderr pass through unmodified, the wrapper prints nothing of its own, and it exits with the
wrapped command's code. The two compose; `run-notify.ps1` tells you when it *finished*, this tells you
it is *still going*. The bar shows `⚙ Android build 4m` for one task, `⚙ 3 tasks 12m` for several
(elapsed = the longest-running), and **nothing at all** when none is running.

⚠️ **Liveness is the PID, and the two cheaper designs are both measured dead ends.** The `statusLine`
stdin payload carries nothing about background tasks or subagents — checked against the documented
schema. And the task output directory is not a liveness signal: a **running** Metro process had a
`.output` whose mtime was **three hours stale**, while completed *agent* outputs are **0 bytes**, so
"is the file growing?" reports a live task as dead and a dead one as live. Same class of error as
keying liveness off a process name. So the wrapper registers its own PID in a marker and the status
line asks the OS with `kill -0`.

A marker is deleted by an `EXIT`/`INT`/`TERM` trap. A **SIGKILLed** wrapper orphans its marker, and
that is fine and expected: the status line drops any marker whose PID is dead and deletes it on the
next render. **Do not add a cleanup daemon** — the PID check already is the cleanup.

**`refreshInterval` in `settings.json`'s `statusLine` object is what makes the timer tick** (2s).
Without it the bar only re-renders on conversation state changes, so the elapsed time freezes at
whatever it was when the turn ended — exactly the case this exists for. ⚠️ **Unrelated to
`REFRESH_INTERVAL` *inside* `hooks/statusline.sh`**, which throttles the Anthropic usage API call and
defaults to 300s. Both must keep working; do not conflate them.

- **Marker dir `~/.claude/.bg-tasks/`** — excluded by the allowlist `.gitignore` (which ignores `*`), so
  **do not add an entry for it.**

## Notifications

### HARD RULE — every stop notifies if Brian is away (automatic; hooks own it)

**`tools/idle-notify.ps1` is wired to three hooks in `settings.json`, so it applies to every session on
this machine.** Requested 2026-08-03 as a standing rule.

| Hook | Invocation | Effect |
|---|---|---|
| `Stop` | `-Event Stop` | arm a timer for this session |
| `UserPromptSubmit` | `-Event Cancel` | he replied — disarm |
| `SessionEnd` | `-Event Cancel` | session gone — nothing to wait for |

**It measures the right thing: not "does he look idle" but "did he reply."** On stop it writes a marker
holding a fresh nonce and launches a *detached* watcher; after `IdleSeconds` (default 300) the watcher
re-reads the marker and pushes only if it is still there with a matching nonce. A missing marker means he
replied; a changed nonce means a newer turn owns the notification. That is what keeps a burst of quick
turns from queueing a burst of pushes — **exactly one notification per genuinely-idle turn.**

**A turn that ends with a background task still running waits 30 minutes, not 5** (`BusySeconds`, added
2026-08-06). Ending a turn while a subagent or background shell runs is not a turn you owe a reply to —
the session re-invokes itself when the task returns — so the 5-minute push was pure noise, and during a
long agent run it fired every time. The Stop payload states this outright, in a **supported** field:

```
"background_tasks": [ { id, type: "subagent", status: "running", description, agent_type } ]
```

⚠️ **Do not reimplement this by scanning the temp directory.** Measured 2026-08-06: a running agent's own
`<id>.output` stays **0 bytes with a stale mtime for the whole run** — it is written on completion — so
the obvious "is its log growing?" check reports a perfectly healthy agent as dead. Same class of trap as
keying liveness off a process name; the payload field is the only honest source.

**It is a longer wait, not suppression, and that is deliberate:** a task that *hangs* is exactly what you
want to hear about, and "never notify while busy" would hide precisely that. No liveness re-check is
needed — a task that finishes normally re-invokes the session, whose next Stop mints a new nonce and
retires the old watcher through the mismatch test that already existed. So the busy timer only ever fires
when nothing came back, and it says so: *"Still running … may be stuck"*, at priority 1.

This exists because a run that halts silently has failed even when the work is correct: the dead time
between stopping and being noticed is the cost. Because it is a hook, it covers *every* stop
mechanically — completion, escalation, a hard stop, a stop you did not plan — which beats remembering.

- **Do not send a manual push merely because you are stopping.** The hook has it. Push explicitly
  (`/notify`) only when the *content* matters more than the fact of stopping: a specific question, a
  blocker needing a one-line answer, or console-required work like "restart Claude Code" — and note those
  arrive *immediately*, whereas the hook waits out the idle window.
- **The watcher MUST stay detached.** Sleeping inside the hook would block the session for five minutes
  and the harness would be right to kill it.
- **Marker dir `~/.claude/.idle-watch/`** — excluded by the allowlist `.gitignore` (which ignores `*`), so
  **do not add an entry for it.**
- ⚠️ **Do NOT "improve" this with window-focus detection.** Focus looks like the better signal and it was
  tried: `Add-Type` declaring `GetForegroundWindow`/`GetLastInputInfo` via P/Invoke matches a keylogger
  signature, and **the antivirus on this box blocks the script at parse time** — *"This script contains
  malicious content and has been blocked by your antivirus software."* That kills the whole hook, not just
  the probe. If you ever need a *right-now* away check without P/Invoke, `quser` gives session STATE and
  minute-resolution idle time, and a running `LogonUI` process means the workstation is locked.

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
- **PowerShell array splatting is POSITIONAL, not named.** `& $script @('-Message', $m, '-Title', $t)`
  binds the literal string `-Message` to the *first positional parameter* and the message text to the
  second, so `-Title` lands on whatever comes third — and if that parameter is `[int]`, the call dies with
  a type-conversion error that names the wrong parameter entirely. **Splat a hashtable** (`@{ Message = $m;
  Title = $t }`) whenever you want named binding. Cost a real debugging detour on 2026-08-03.
- **Prefer reading an artifact's identity from the artifact, not from the machine you installed it on.**
  Build metadata (a version, a bundled string) can be read out of the built file directly; installing it
  first to interrogate the device mutates state to answer a question the file already answers.

## Access preconditions

Some tooling needs network access a given machine may not have. State the precondition rather than
retrying blindly, and say plainly when it's unavailable:

- **`/push-nuget`** → the private work NuGet feed. **Requires the work VPN.**
- **Jira commands, and `bb`** → the work Bitbucket/Atlassian tenant. Unavailable on a personal machine;
  on those, GitHub Issues via `gh` is the path.

---

## Machine-specific facts

Anything true of one machine and not another lives in a separate file, so this one stays portable.
**That file is gitignored** — it names hosts, addresses, device serials and drive layouts, which do not
belong in the repo. Only the template `CLAUDE.machine.example.md` is tracked; on a new machine, copy it
to `CLAUDE.machine.md` before anything else, or this import has no target.

@~/.claude/CLAUDE.machine.md
