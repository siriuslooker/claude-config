---
description: Start, stop or inspect this project's localhost development surfaces from its own port manifest, so QA never guesses a port or a start command.
argument-hint: up [surface...] | down [surface...] | status | restart [surface...]
allowed-tools: Read, Glob, Grep, PowerShell, Bash, Skill
---

Bring this project's local development surfaces up (or down), reading **the project's own port
manifest** rather than guessing ports or start commands.

**You run this from the MAIN thread. Do not delegate it to a subagent.** A dev server is
long-running, and the harness re-invokes whoever launched a background process — a subagent that
starts a server and ends its turn hands the completion notification to *itself*, so the main thread
learns nothing and falls back to polling. Delegate the *judgement* about a running app to the `qa`
agent if you like, but own the launching.

## Arguments

`$ARGUMENTS` — a verb, optionally followed by surface names:

| Verb | Effect |
|---|---|
| `up` (default when no verb given) | Start the manifest's `defaultUp` surfaces, in dependency order. Named surfaces override that list. |
| `down` | Stop what was started, by PID file, falling back to port owner. |
| `status` | Report what is listening, what is not, and whether the manifest has drifted from the real configs. Starts nothing. |
| `restart` | `down` then `up` for the named surfaces (all of `defaultUp` if none named). |

Examples: `/local-env up`, `/local-env up admin`, `/local-env status`, `/local-env down`,
`/local-env restart backend`.

## Find the manifest

Look, in order, for:

1. `local-env.json` at the repo root
2. `.claude/local-env.json`

**If neither exists, do not improvise a launch.** Say so, then offer to author one — read the repo's
package scripts, Vite/launchSettings configs and any dev-server docs, propose a port block from a
quiet range, and **ask the user to confirm the ports before writing the file**. Ports are a decision
with a long tail (they end up in hardcoded client URLs, `adb reverse` rules and reviewer muscle
memory), so they are the user's call, not yours. Then write the manifest and continue.

## The manifest contract

Fields you rely on, per surface: `port`, `command`, `cwd`, `health`, `dependsOn`, and optionally
`healthExpect`, `startByDefault`, `fixed`, `authNote`, `declaredIn`, `notes`. Top level:
`defaultUp`, `driveUrlDefault`, `onPortBusy`, `packageManager`, `portRange`.

Honour these three rules:

- **`dependsOn` sets the order.** Start an API before the SPA that calls it. Health-check each
  dependency before starting what depends on it — an SPA that boots against a dead API produces
  QA findings that are artifacts of the launch, not defects.
- **`onPortBusy: "fail"` means do not work around a collision.** Report which process holds the
  port and stop. Do not pick another port: the other surfaces have the first one baked into their
  client config, and a silent move desynchronizes them. If the holder is an *earlier run of this
  same surface*, say so and offer `restart`.
- **`fixed: true` surfaces keep their port.** It is dictated by a toolchain (Metro's 8081 is baked
  into dev-client discovery and `adb reverse`). Never renumber one to fit a range.

`startByDefault: false` surfaces are started only when named explicitly.

## Launching

Delegate the mechanics to the **`launch-local`** skill — it owns detached launch, PID files, log
paths and the health-poll loop. Pass it the resolved command, cwd, port and health URL from the
manifest. Do not re-derive them.

**Read the manifest's `packageManager` and `packageManagerNote` first.** A package manager missing
from an agent shell's PATH is common and is **not** evidence it is uninstalled — resolve it before
reporting it absent (see `launch-local`).

## `status`

Cheap and read-only. For each surface report: listening or not, the owning PID and its command line,
and the health probe result. Then check for **drift**: compare each surface's manifest `port` against
the value in its `declaredIn` config file. A mismatch is worth flagging loudly — the manifest is a
*description* of the configs, not their source, so when they disagree the configs win at runtime and
every agent reading the manifest is wrong.

Do not start anything during `status`.

## `down`

Stop by PID file first (`.claude/stack-ops/<name>.pid`), then verify the port is actually free. If a
PID file is stale but the port is still held, identify the holder by port and stop that instead —
**and never decide "is it still running?" from a process name.** `pgrep -f <pattern>` matches its own
invoking shell and any other process carrying the string. Key on the listening socket.

Only stop surfaces this project owns. A port outside the manifest's `portRange` that you did not
start is somebody else's process — report it, do not kill it.

## Report back

Terse. One line per surface plus the URL to drive:

```
backend  7310  UP    PID 7316   health 200
admin    7312  UP    PID 1472   health 200
web      7311  DOWN  (not started)

Drive: http://localhost:7311/
```

Add, only when they apply: an `authNote` if the surface is auth-gated and the local store may have no
usable account; a drift warning; and the log paths for anything that failed to come up.

## Notes

- **Local data stores are not the deployed ones.** A surface backed by a local database has its own
  file, so accounts and settings from a shared test rig do not exist locally. When a user reports
  that known-good credentials fail against localhost, this is the first thing to check — surface the
  `authNote` rather than debugging auth.
- **Do not create a `.env.local` to point a Vite app at a local API.** Vite reads it in production
  mode too, so a stale override can be constant-folded into a deployed bundle. Set the variable
  per-invocation instead. (The manifest's `notes` may repeat this where it has already bitten.)
- Keep the manifest and its human-readable twin (`humanDoc`) in agreement. Changing a port is a code
  change: branch it.
