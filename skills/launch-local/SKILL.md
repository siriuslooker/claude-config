---
name: launch-local
description: Start an app locally as a detached process that survives the agent's shell, health-check it, and return the URL plus a PID file for later cleanup. Reads a project's `local-env.json` port manifest when one exists, so ports and start commands are never guessed. Covers .NET (dotnet run) and Node (dev server / preview). Use before QA or any manual verification against a running app.
---

# Launch locally (detached)

You start the app and hand back a URL and a PID. **The process must outlive your shell** — a
foreground launch blocks until timeout and then dies, taking the QA run with it.

State goes under `.claude/stack-ops/` in the repo (works on both platforms, no temp-dir
special-casing). Create it first — `Start-Process -RedirectStandardOutput` fails if the directory
does not exist.

## Pick the command

**First look for a port manifest** — `local-env.json` at the repo root, or `.claude/local-env.json`.
When one exists it is authoritative for ports, commands, cwd, health URLs and start order, and you
should not re-derive any of them. Per surface it gives `port`, `command`, `cwd`, `health`,
`dependsOn`, and may add `healthExpect`, `fixed`, `startByDefault`, `authNote`, `declaredIn` and
`notes`. Honour `dependsOn` as the launch order and health-check each dependency before starting what
depends on it. `onPortBusy: "fail"` means report the collision rather than working around it. The
`/local-env` command drives this file; a manifest plus this skill is the whole contract.

The manifest is a *description* of the real configs, not their source — `declaredIn` names the file
the app actually reads. If they disagree, the config wins at runtime; report the drift.

Without a manifest, fall back to detection:

| Stack | Command | Default URL |
|---|---|---|
| netcore | `dotnet run --project <proj> --launch-profile http` | read `Properties/launchSettings.json` |
| node (dev) | `<pm> run dev` | read the Vite/Next default from output (`5173`, `3000`) |
| node (prod bundle) | `<pm> run build` then `<pm> run preview` | `4173` |

Read the actual port from `launchSettings.json` / `vite.config.*` rather than assuming. If the port
is already in use, report `PORT_IN_USE` with what holds it — do not silently pick another port; the
caller may be looking at a stale process from an earlier run.

**A package manager missing from your shell's PATH is not evidence it is uninstalled.** Agent shells
here routinely carry a reduced PATH. Before reporting `pnpm`/`npm`/`yarn` absent, check
`Get-Command`, then the usual install locations (`%APPDATA%\npm\<pm>.cmd`, the Node install dir,
`%LOCALAPPDATA%\pnpm`), and invoke it by full path if found. A manifest may carry a
`packageManagerNote` saying exactly this.

**Full-stack repos** (a .NET API serving an SPA): in dev, both processes run and the SPA's dev server
proxies API routes — launch the API **first**, then the SPA, and return the **SPA's** URL as the one
to drive. Say which is which in the payload.

## Configuration that is not in source control

Before launching, check for local-only config the app needs and cannot get from tracked files —
connection strings, secrets, API keys. Prefer environment variables or user-secrets over editing a
tracked `appsettings.*.json` / `.env`. If a required value is missing, report `CONFIG_MISSING` with
the key name rather than launching an app that will crash on first request.

**Never create a `.env.local` to point a Vite app at a local API.** Vite reads `.env.local` in
production mode as well as dev, so the override gets constant-folded into a production bundle and the
deployed app tries to reach the *developer's own machine*. Pass the variable per-invocation instead.

**A local data store is not the deployed one.** An app backed by a local database has its own file,
so accounts, settings and content from a shared test rig do not exist locally. When known-good
credentials fail against localhost, that is the first thing to check — surface the manifest's
`authNote` (which should say how to mint a local account) rather than debugging auth.

## Launch

**PowerShell:**
```powershell
New-Item -ItemType Directory -Force -Path ".claude/stack-ops" | Out-Null
$p = Start-Process pwsh -ArgumentList "-NoProfile","-Command","<command>" `
    -RedirectStandardOutput ".claude/stack-ops/app.log" `
    -RedirectStandardError  ".claude/stack-ops/app.err.log" `
    -PassThru -WindowStyle Hidden
$p.Id | Out-File -NoNewline ".claude/stack-ops/app.pid"
```

**POSIX:**
```bash
mkdir -p .claude/stack-ops
nohup <command> > .claude/stack-ops/app.log 2>&1 &
echo $! > .claude/stack-ops/app.pid
disown
```

Use one file set per process; for a two-process launch suffix them (`api.pid`, `web.pid`).

If the PID file ends up empty, abort with `LAUNCH_FAIL` — the caller needs it for cleanup.

## Health check

Poll up to 15 times at 2s intervals. Each iteration: confirm the PID is alive **and** probe the URL.
Break early if the process dies — do not keep polling a corpse for 30 seconds.

Outcomes:
- Alive + 2xx/3xx → `OK`.
- Died → `LAUNCH_FAIL`; include the last 30 lines of both logs. A .NET app that dies immediately is
  usually a DB connection or a missing-migration failure — quote the actual exception.
- Alive but never responds → `UNVERIFIED`; return the PID anyway. The health path may just be wrong.

## Return this payload

```markdown
## launch-local: <OK | UNVERIFIED | LAUNCH_FAIL | PORT_IN_USE | CONFIG_MISSING>

- **Drive this URL:** <url>
- **Processes:**
  - <stack> — PID <n>, pidfile `.claude/stack-ops/<name>.pid`, log `.claude/stack-ops/<name>.log`
- **Health:** <verified HTTP 200 at <path> | process alive, URL unverified>
- **Config supplied:** <env vars / user-secrets set for this run, or "none">
- **Auth for testing:** <credentials, or "none">

### Errors
<last 30 lines of the failing log, or omit>

### Cleanup
Stop with the PID files above. Any caller that launched must stop what it launched.
```
