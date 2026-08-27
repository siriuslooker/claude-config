---
name: compile-expo-android
description: Build an Expo/React Native Android release APK — typically via a repo build script running Gradle inside WSL2 on an ext4 working copy — and verify the artifact's real versionCode/versionName from the APK itself. Covers the un-bumped-versionCode footgun and long-build reporting. Use when the stack manifest reports an expo-android stack.
---

# Compile: Expo / React Native — Android APK

Mechanical. You build and report what came out. **You do not edit source to make the build pass**, and
you never report a build you did not see succeed. **You do not distribute** — producing the artifact is
the job; publishing it is a separately-approved step, so never copy it to a downloads/release location
and never run a deploy script.

Host facts — WSL distro, device serial, signing-credential location — live in
**`~/.claude/CLAUDE.machine.md`**. Read them there; never hardcode them here.

## Use the repo's own build script if it has one

Prefer an existing entry point (e.g. `scripts/wsl/build.sh`, a `Makefile` target, a `package.json`
script) over an invented `gradlew` invocation — same rule `compile-node` follows. Read it before running
it, because its choices change what is true downstream. Things worth knowing about a typical script of
this shape:

- **It syncs the working tree to a native Linux filesystem** (Gradle on a `/mnt/…` DrvFs path is
  crippling slow). That sync is normally `rsync` **inside WSL**, which is fine — the
  "rsync is broken" caveat in `CLAUDE.machine.md` applies to Windows→remote copies, not to this.
- **It syncs the working tree, not git HEAD**, so **uncommitted changes are included and you never need
  to commit to build.** Say so rather than asking anyone to commit first.
- **It usually excludes `android/` and re-runs `expo prebuild`**, regenerating the native project every
  time. Consequence: **the Expo manifest (`app.json`/`app.config.*`) is the single source of truth for
  `versionCode`** and nothing stale can survive — but equally, **any hand edit under `android/` is
  destroyed.** A durable native change must be an Expo config plugin.
- **Progress markers**: scripts of this kind print stage markers (`### [n/5] …`) and end with an
  artifact path plus a completion marker. Grep for the failure signatures too, not only the happy-path
  markers — a filter matching only success stays silent through a crash, and silence is
  indistinguishable from "still running".
- **Signing** may fall back to a throwaway debug keystore, which is fine for on-device verification.
  **Never print or echo signing values.**

If there is no script, the underlying sequence is `pnpm install` → `expo prebuild --platform android
--no-install` (with `CI=1`, or it prompts and hangs) → `./gradlew assembleRelease`. Set `CI=true`.

## Mandatory pre-build check — the versionCode footgun

**Read the Expo manifest and confirm `android.versionCode` is greater than the last build's.** An
un-bumped `versionCode` makes the install **silently no-op** on-device; QA then tests the *old* build and
reports confident findings about code that was never there. It is the single most expensive failure mode
on this stack.

If it looks un-bumped, **stop and report** — do not bump it yourself; that is a versioning decision.

## Mandatory post-build check — verify the artifact, not the manifest

Confirm the APK exists and report **path, size, and mtime**. A script exiting 0 is not proof an artifact
exists: **stat the file.**

Then read the identity **out of the APK**, because that is what will actually install:

- **`aapt` is frequently absent** from `$ANDROID_HOME/build-tools/` in a minimal WSL image, and
  `apkanalyzer` can fail under the installed JDK. What works is the **`aapt2`** binary from Gradle's own
  transforms cache — **find it rather than hardcoding a hash-bearing path**:

```
AAPT2=$(find ~/.gradle/caches -name aapt2 -type f 2>/dev/null | head -1)
"$AAPT2" dump badging <path-to.apk> | head -3
```

Report `versionCode` and `versionName` exactly as printed. **A prerelease suffix in `versionName`
(e.g. `1.2.3-dev.13`) is correct, not malformed** if the project's scheme carries a build number.

If you genuinely cannot run any badging tool, say so plainly and report the file stat alone — but
**never silently skip this check.** It is the only thing that proves the install won't no-op.

## Long builds: own them yourself with the job runner

**A cold Android build (~13-16 min) exceeds the 10-minute cap on a single Bash call. That cap is per
CALL, not per turn** — so you can own a build of any length by starting it detached and polling in
bounded chunks. **Do not hand a build back to the caller, and do not end your turn with verification
pending, unless the job runner is genuinely unavailable.**

```
bash ~/.claude/tools/job.sh start "APK <version>" "wsl -d Ubuntu-24.04 -u root -- bash -lc 'bash /mnt/<path>/scripts/wsl/build.sh'"
  -> JOB=<id>
bash ~/.claude/tools/job.sh wait <id> 480     # status=running  — just call it again
bash ~/.claude/tools/job.sh wait <id> 480     # status=done exit=0
```

`start` returns immediately. `wait` polls to a budget under the cap and **is meant to be called
repeatedly** — two or three calls covers a cold build. Also `status`, `log <id> [n]`, `stop`.

⚠️ **Put the `wait` call in a Bash call by ITSELF.** Combining it with other commands is how you blow
the tool budget and lose the poll — that happened the first time this runner was used in anger.

**`status=vanished` is NOT success.** It means the pid is gone with no exit file — killed, or the machine
restarted. Killed and completed are different outcomes; report it as a failure, never smooth it into a
pass.

Then verify the artifact and report: APK mtime, and **`aapt2 dump badging`** for the real
versionCode/versionName. Reading identity from the artifact is mandatory — never install it somewhere
just to ask what version it is.

**Fallback only if the job runner is missing:** background the command and say so explicitly —

> Build running in background (task `<id>`), cold build, expect ~N minutes. My turn ends here by design —
> I'll be re-invoked when the process exits and will then run the post-build verification (APK mtime +
> `aapt2` versionCode). **Verification is PENDING, not done.**

**Never write "I'll wait for it to complete" and then end your turn.** The caller cannot tell whether
verification is pending by design or was silently dropped. If re-invoked while a build is still live,
**re-state the pending status rather than relaunching** — check for a live gradle process first and
**never start a second concurrent build.**

Two traps when watching a build:

- **Output can buffer through a `wsl -- bash -lc` pipe** — the capture file can sit at 0 bytes while
  Gradle is demonstrably running. Line-buffer the script's output (`stdbuf -oL`, or a pty wrapper) if you
  need live stage markers, or accept that you get nothing until exit.
- **Do NOT decide "is it still building?" from a process name — match on evidence of work instead.**
  Two distinct failures bite here, and the well-known one is the lesser:
  - `pgrep -f "<pattern>"` matches **its own invoking shell** when the pattern appears in the command
    string, so the check never fires. The usual fix is a pattern that cannot match the matcher
    (`[b]uild.sh`).
  - **That fix is not enough.** The bracket trick only excludes the matcher itself — it still matches
    *any other* process whose command line contains the string, such as a second agent monitoring the
    same build, or an ssh command with the tool name in it. Observed costing 30 minutes: a watcher
    reported `BUILDING` for half an hour after the build had finished, because it was matching another
    monitor's command line rather than a compiler.
  - **Key on artefacts, not names:** the build log's mtime and byte size, compiler CPU
    (`ps -Ao pid,%cpu,comm | grep -E "[s]wift-frontend|[c]lang"`), or the output artefact's mtime. A
    log that stopped growing ten minutes ago is finished, whatever `pgrep` says — and the log's last
    line tells you whether it succeeded.
  **Verify a watcher actually fires before trusting it**, and cross-check a long "still running" claim
  against the log mtime before reporting it.

## Absence and failure get their own named outcomes

| Situation | Outcome |
|---|---|
| WSL distro / Android SDK / JDK absent | `TOOLCHAIN_MISSING` — not a code failure |
| No Expo manifest, or no Android-capable config | `NO_ANDROID_PROJECT` (list what you checked) |
| `versionCode` not greater than the last build | `VERSION_NOT_BUMPED` — **stop, do not build** |
| `expo prebuild` fails | `FAIL` with `stage: prebuild` |
| Gradle fails | `FAIL` with `stage: assemble`, plus the real error lines |
| Build reported success, APK missing or stale mtime | `FAIL` with `stage: artifact` — never `OK` |
| Built, but badging tool unavailable | `OK` with an explicit **unverified identity** note |

Write long output to `.claude/stack-ops/compile-expo-android.log` and cite the path rather than pasting
it. **Do not pipe raw Gradle output into your report** — it is a redrawing terminal UI that becomes
thousands of lines when captured.

## Return this payload

```markdown
## compile-expo-android: <OK | FAIL | TOOLCHAIN_MISSING | NO_ANDROID_PROJECT | VERSION_NOT_BUMPED>

- **Command:** <exact command run> • **Waiting pattern:** <foreground | background>
- **Manifest versionCode:** <n> (previous <n-1>) → <bumped | NOT bumped>
- **Stages reached:** <e.g. 5/5>
- **Artifact:** <path> • <bytes> • <mtime>
- **APK identity (from `aapt2 dump badging`):** versionCode <n>, versionName <x> — <or "UNVERIFIED: tool unavailable">
- **Signing:** <configured creds | fallback debug keystore> (values never printed)
- **Elapsed:** <duration> • **Log:** <path>

### Errors
- <real error lines, trimmed to the meaningful ones>

### Not verified
<what you could not confirm — always populated, never "n/a">
```

Nothing else.
