# claude-config

Version-controlled Claude Code configuration — the contents of `~/.claude` that are worth carrying
between machines. Private repo.

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
| `CLAUDE.machine.md` | Per-host facts, one `## HOSTNAME` section each. Imported by `CLAUDE.md` |
| `settings.json` | Model, statusline, theme. No plugins or marketplaces |
| `commands/` | Slash commands — session workflow (`start-session`, `save-context`, `end-session`, `init-project`), Jira (`jira-comment`, `jira-attach`, `jira-update`), plus `notify`, `deep-review`, `push-nuget` |
| `agents/` | The **stack-ops agents**: `implement`, `verify`, `compile`, `test`, `qa`, `deploy` |
| `skills/` | Per-stack skills the agents dispatch to (`{compile,test,deploy}-{netcore,node}`, `stack-detect`, `report-handoff`, `launch-local`) plus `authoring-stack-ops-skills` |
| `hooks/` | `statusline.sh` |
| `tools/` | `notify.ps1` (Pushover wrapper) |
| `setup.ps1`, `setup.sh` | New-machine CLI installers (`gh`, `bb`, `sqlcmd`) — winget / Homebrew+apt |

### The stack-ops agents

`implement` writes the code for a planned phase and is the only agent that writes source; `verify` is
the read-only gate.
They are stack-agnostic — a per-stack skill knows *how*. Only `netcore` and `node` are implemented;
`netfx` is deliberately detected-but-unhandled as the worked example of that seam. To add a stack, use
the `authoring-stack-ops-skills` skill — **add a skill, never edit an agent.**

These began life as a Claude Code plugin in a separate Bitbucket repo. That was abandoned in favour of
plain files here, because a marketplace registration bakes in an absolute path to the plugin working
copy, and because a personal machine may have no Bitbucket access. **There is nothing to install** — a
clone plus a `credentials.json` is a complete setup. The old `<work-org>/claude-agents-plugin` repo
has been **deleted**; this repo is the only source. (Its git history survives only in a local working
copy at `<local-path>` on <workstation> — the files were copied
here, the commits were not.)

## Setting up a new machine

```bash
git clone git@github.com:siriuslooker/claude-config.git ~/.claude-config
```

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

1. **Recreate `credentials.json`** — it is not in the repo, and is the only thing a clone doesn't give
   you. Entries used by the tracked commands: `"Jira API (<work-org>)"` (`password` = API token from
   id.atlassian.com/manage-profile/security/api-tokens), `"Bitbucket API (<work-org>)"`, `"Pushover"`
   (`token`, `userKey`).
2. **Restart Claude Code** — agents and skills only load at startup, so they won't resolve in a session
   that was already running when you cloned.
3. **Install the CLIs the commands assume** — `gh` (GitHub), `bb` (Bitbucket), `sqlcmd` (DB work).
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
  per machine — add yours rather than editing another's. It is tracked on purpose: Claude Code documents
  the `@import` syntax but *not* what happens when the target is missing, and a gitignored file is absent
  on every fresh clone, so tracking it means the import can never dangle.
- **The Jira commands are RD-specific**, keyed to `<jira-site>` and a matching
  credentials entry. On a personal machine they're inert; GitHub Issues via `gh` is the path there.
