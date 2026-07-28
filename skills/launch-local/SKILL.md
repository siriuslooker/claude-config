---
name: launch-local
description: Start an app locally as a detached process that survives the agent's shell, health-check it, and return the URL plus a PID file for later cleanup. Covers .NET (dotnet run) and Node (dev server / preview). Use before QA or any manual verification against a running app.
---

# Launch locally (detached)

You start the app and hand back a URL and a PID. **The process must outlive your shell** — a
foreground launch blocks until timeout and then dies, taking the QA run with it.

State goes under `.claude/stack-ops/` in the repo (works on both platforms, no temp-dir
special-casing). Create it first — `Start-Process -RedirectStandardOutput` fails if the directory
does not exist.

## Pick the command

| Stack | Command | Default URL |
|---|---|---|
| netcore | `dotnet run --project <proj> --launch-profile http` | read `Properties/launchSettings.json` |
| node (dev) | `<pm> run dev` | read the Vite/Next default from output (`5173`, `3000`) |
| node (prod bundle) | `<pm> run build` then `<pm> run preview` | `4173` |

Read the actual port from `launchSettings.json` / `vite.config.*` rather than assuming. If the port
is already in use, report `PORT_IN_USE` with what holds it — do not silently pick another port; the
caller may be looking at a stale process from an earlier run.

**Full-stack repos** (a .NET API serving an SPA): in dev, both processes run and the SPA's dev server
proxies API routes — launch the API **first**, then the SPA, and return the **SPA's** URL as the one
to drive. Say which is which in the payload.

## Configuration that is not in source control

Before launching, check for local-only config the app needs and cannot get from tracked files —
connection strings, secrets, API keys. Prefer environment variables or user-secrets over editing a
tracked `appsettings.*.json` / `.env`. If a required value is missing, report `CONFIG_MISSING` with
the key name rather than launching an app that will crash on first request.

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
