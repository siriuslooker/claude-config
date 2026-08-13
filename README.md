# claude-config

Version-controlled Claude Code configuration — the contents of `~/.claude` that are worth carrying
between machines.

⚠️ **This repo is PUBLIC.** Nothing here may name a host, an address, a device serial, a drive layout,
an internal service or an employer's tenant — write it as though a stranger is reading it, because one
can. Per-machine facts have their own gitignored file; see *Known warts*.

## ⚠️ Secrets

`~/.claude` is a live runtime directory that holds credentials and full session transcripts. The
`.gitignore` here is therefore an **allowlist**: it ignores everything, then re-admits only the config
paths below. This is deliberate — a blocklist would silently start tracking any secret file a future
Claude Code version drops into the directory.

**Never re-admit** `credentials.json`, `.credentials.json` (Claude auth), `history.jsonl`, `projects/`
(transcripts + per-machine memory), `sessions/`, `tasks/`, `jobs/`, `keystores/`, `session-env/`,
`paste-cache/`, `debug/`, `shell-snapshots/`, `file-history/`, `daemon.log`.

If you add a new tracked path, run `git add -A --dry-run` and read the list before committing.

## What's tracked

| Path | What |
|---|---|
| `CLAUDE.md` | Global instructions: implementation process, ticketing, branch/PR rules. Machine-agnostic by policy |
| `CLAUDE.machine.example.md` | Template for per-host facts. **The real `CLAUDE.machine.md` is gitignored** — copy this to it |
| `settings.json` | Model, statusline, theme, hook registrations. No plugins or marketplaces |
| `.gitattributes` | Line-ending normalisation |
| `commands/` | 12 slash commands — session workflow (`start-session`, `save-context`, `end-session`, `init-project`, `adopt-project`), Jira (`jira-comment`, `jira-attach`, `jira-update`), plus `notify`, `deep-review`, `push-nuget`, `local-env` |
| `agents/` | The **stack-ops agents**: `implement`, `verify`, `compile`, `test`, `qa`, `deploy` |
| `skills/` | 16 skills — per-stack (`{compile,test,deploy}-{netcore,node}`, `compile-netfx`, `{compile,qa}-expo-{ios,android}`), plus `stack-detect`, `report-handoff`, `launch-local`, `phase-loop`, `authoring-stack-ops-skills` |
| `hooks/` | `statusline.sh`, `delegation-standing-request.sh` (restates the standing subagent request each turn), `pwsh-exec.sh` (resolves `pwsh` without trusting `PATH`) |
| `tools/` | `notify.ps1` (Pushover), `run-notify.ps1` (wrap a command, push its outcome), `idle-notify.ps1` (push when a turn ends and nobody replies), `bg-task.sh` (make a background task visible in the status line), `reap-stale-dev-servers.ps1`, `find-leaked-dev-procs.ps1` |
| `setup.ps1`, `setup.sh` | New-machine CLI installers (`gh`, `bb`, `sqlcmd`) — winget / Homebrew+apt |

### The stack-ops agents

`implement` writes the code for a planned phase and is the only agent that writes source; `verify` is
the read-only gate.
They are stack-agnostic — a per-stack skill knows *how*. Implemented today: `netcore`, `node`,
`expo-ios` and `expo-android`, with `netfx` compile-only. To add a stack, use the
`authoring-stack-ops-skills` skill — **add a skill, never edit an agent.**

These began life as a Claude Code plugin in a separate repo. That was abandoned in favour of plain
files here, because a marketplace registration bakes in an absolute path to the plugin working copy,
and because a personal machine may have no access to the host it lived on. **There is nothing to
install** — a clone, a `credentials.json` and a `CLAUDE.machine.md` are a complete setup (both are
covered in *Setting up a new machine* below). The old plugin repo has been **deleted**; this repo is
the only source, and its commits were not carried over — only the files.

## Setting up a new machine

```bash
git clone git@github.com:siriuslooker/claude-config.git ~/.claude-config
```

⚠️ **Use the SSH remote, not HTTPS.** An HTTPS clone or `ls-remote` prompts for credentials and then
*hangs with no error* in a non-interactive shell — which looks exactly like a network problem and
isn't. Check an existing checkout with `git remote -v` and switch it with
`git remote set-url origin git@github.com:siriuslooker/claude-config.git` if it reads `https://`.

`~/.claude` already exists and contains live state, so **don't clone over it.** Either clone elsewhere
and copy the tracked paths in, or initialise in place:

```bash
cd ~/.claude
git init
git remote add origin git@github.com:siriuslooker/claude-config.git
git fetch origin
git checkout -f main       # tracked paths only; everything else is ignored
```

Then, separately:

1. **Recreate `credentials.json`** — it is not in the repo and never will be. It holds one entry per
   service the tracked commands talk to: an issue tracker, a source host, and Pushover (`token`,
   `userKey`). **Each command names the entry key it reads** — open the one you need rather than
   listing tenants here, which is how an internal hostname ends up on a public page.
2. **Create `CLAUDE.machine.md`** — `CLAUDE.md` imports it and the repo does not carry it:

   ```bash
   cp ~/.claude/CLAUDE.machine.example.md ~/.claude/CLAUDE.machine.md
   ```

   Then replace the placeholder `## <HOSTNAME>` section with this machine's facts. Leaving it as the
   bare template is fine; leaving it *absent* is not, because a missing import target is undocumented
   behaviour.
3. **Restart Claude Code** — agents and skills only load at startup, so they won't resolve in a session
   that was already running when you cloned.
4. **Install the CLIs the commands assume** — `gh` (GitHub), `bb` (Bitbucket), `sqlcmd` (DB work).
   There is a script per platform at the repo root:

   ```powershell
   pwsh -NoProfile -File ~/.claude/setup.ps1 -Check   # report only, install nothing
   pwsh -NoProfile -File ~/.claude/setup.ps1          # install what's missing (winget)
   ```

   ```bash
   bash ~/.claude/setup.sh --check                    # report only, install nothing
   bash ~/.claude/setup.sh                            # install what's missing
   ```

   Both are idempotent, take `--check`/`-Check` and `--dry-run`/`-DryRun`, print a per-tool summary
   with versions, and **exit non-zero if anything is still missing** — a tool that can't be installed
   is reported with its manual step, never smoothed into a pass. `setup.ps1` uses winget; `setup.sh`
   covers macOS (Homebrew) and Debian/Ubuntu (apt), detected at runtime.

   Two things the scripts deliberately won't do:

   - **`bb` is never auto-installed on macOS/Linux.** At least two unrelated CLIs are called
     "Bitbucket CLI" and both provide a `bb` command; ours is
     [gildas/bitbucket-cli](https://github.com/gildas/bitbucket-cli) (winget `Gildas.Bitbucket-CLI` —
     *not* `dlbroadfoot.bb`, which has a higher version number and different subcommands). The Unix
     side probes, reports, and tells you to drop the release binary on `PATH`.
   - **No third-party package repositories are added for you.** On apt that means `gh` comes from the
     distro archive if it's there, and `sqlcmd` needs Microsoft's repo added by hand — both print the
     vendor's documented instructions instead of guessing.

Nothing else. No plugins, no marketplaces.

## Known warts

- **`settings.json` is portable but opinionated** — it pins the model, effort level, fullscreen TUI and
  dark theme. Adjust per taste rather than assuming it's neutral.
- **The agent names are bare and generic** — `implement`, `verify`, `compile`, `test`, `qa`, `deploy`.
  They lost the `stack-ops:` prefix when they stopped being plugin agents, so a project-level agent with
  one of those names would shadow them. (`implement` was called `build` until the name proved
  confusing — it reads as *compile*, which is a different agent entirely.)
- **Per-host facts live in `CLAUDE.machine.md`**, imported by `CLAUDE.md`, with one `## HOSTNAME` section
  per machine. **That file is gitignored** — it names hosts, LAN addresses, device serials and drive
  layouts, and none of that belongs in the repo. Only `CLAUDE.machine.example.md` is tracked. ⚠️ Claude
  Code documents the `@import` syntax but *not* what happens when the target is missing, so **copy the
  example to `CLAUDE.machine.md` as part of setting up a machine** — see step 2 above.
- **The Jira commands are work-specific**, keyed to one Atlassian tenant and a matching credentials
  entry — both named in the commands themselves, not here. On a personal machine they're inert; GitHub
  Issues via `gh` is the path there.
