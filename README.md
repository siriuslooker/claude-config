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
| `CLAUDE.md` | Global instructions: implementation process, ticketing, branch/PR rules, machine facts |
| `settings.json` | Model, statusline, theme, enabled plugins |
| `commands/` | Slash commands — session workflow (`start-session`, `save-context`, `end-session`, `init-project`), Jira (`jira-comment`, `jira-attach`, `jira-update`), plus `notify`, `deep-review`, `push-nuget` |
| `skills/` | Personal skills — currently `authoring-stack-ops-skills` |
| `agents/` | Personal subagents (none yet; the stack-ops agents come from a plugin) |
| `hooks/` | `statusline.sh` |
| `tools/` | `notify.ps1` (Pushover wrapper) |

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

1. **Recreate `credentials.json`** — it is not in the repo. Entries used by the tracked commands:
   `"Jira API (<work-org>)"` (`password` = API token from
   id.atlassian.com/manage-profile/security/api-tokens), `"Bitbucket API (<work-org>)"`, `"Pushover"`
   (`token`, `userKey`).
2. **Install the stack-ops plugin** — the agents referenced throughout `CLAUDE.md` live in a separate
   repo, because installed plugins are artifacts rather than config:
   ```
   claude plugin marketplace add git@bitbucket.org:<work-org>/claude-agents-plugin.git
   ```
   Then **restart Claude Code** — agents and skills only load at startup.
3. **Fix the machine-local path in `settings.json`.** `extraKnownMarketplaces` currently points at
   `<local-path>`, a local directory that won't exist
   elsewhere. Replace it with the git source above, or re-add the marketplace and let it rewrite the
   entry. **Known wart** — see below.
4. Install CLIs the commands assume: `gh` (GitHub), `bb` (Bitbucket), `sqlcmd` if doing DB work.

## Known warts

- **`settings.json` carries a machine-local absolute path** (`extraKnownMarketplaces` → the plugin
  working copy on the `F:` drive). It's tracked because the rest of the file is genuinely portable, but
  this key needs adjusting per machine. The clean fix is to point the marketplace at the plugin's git
  URL, at the cost of losing live local editing of the plugin.
- **The plugin repo is on Bitbucket**, which a personal machine may not have access to. If that becomes
  a problem, mirror `claude-agents-plugin` to GitHub and switch the marketplace source.
- **Nothing here is machine-agnostic by construction.** `CLAUDE.md` has a "machine facts" section with
  things that are true of this box (no LocalDB, SSH-only Bitbucket). Review it on a new machine rather
  than trusting it.
