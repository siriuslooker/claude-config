---
name: qa-expo-ios
description: Drive an Expo/React Native app on an iOS simulator hosted on a remote Mac and report defects — install, navigate by normalized taps, read the accessibility tree, exercise Dynamic Type. Encodes the simulator-rig constraints that silently invalidate a QA pass. Use when the stack manifest reports an expo-ios stack and the task is to exercise a running app.
---

# QA: Expo / React Native — iOS simulator

You exercise a **running** app and report what you observe. **Read-only: you never fix what you find.**
Tests prove the code does what the tests say; you find out whether the app does what a user needs.

Host facts — ssh alias, IP, simulator UDID, bundle identifier, helper/preview ports — live in
**`~/.claude/CLAUDE.machine.md`**. Read them there; never hardcode them here.

## The three rules that invalidate a pass if broken

Read these before touching the simulator. Each has already destroyed at least one QA session.

### 1. NEVER inject keystrokes

Injecting hardware keystrokes flips the simulator into **hardware-keyboard mode, which suppresses the
software keyboard system-wide** — not just in your app. This is real iOS behaviour, not a tool bug
(reproducible in Apple's own apps, which is how it was proven). There is **no toggle**: recovery is a
full `simctl shutdown` + `boot`. The installed app survives; do not erase or reinstall.

Consequences, which are not optional:

- **Test any keyboard-dependent behaviour BEFORE typing anything at all.** Once you have typed, the
  screen you most need to inspect no longer exists.
- To fill a field, use the clipboard: `xcrun simctl pbcopy` then long-press → Paste. **Taps and gestures
  are safe; keystrokes are not.**
- A persisted signed-in account is *valuable* precisely because it avoids the typing needed to reach a
  form. Preserve it (see rule 3).
- Keystroke injection also makes **adjacent-key substitution errors** during rapid entry, so it is
  unreliable for real data even where it is safe.

### 2. Installing the app ORPHANS the device-driver session

`simctl install` invalidates the driver's session, because that session is bound to the app process.
**After every install, restart the driver** — otherwise you are driving a ghost.

The symptoms are indistinguishable from a coordinate mistake unless you know them: **input calls exit 0
while changing nothing**, and the accessibility tree returns a frame from *before* the install (it will
happily report a screen the app left minutes ago). This derailed three consecutive QA passes before the
cause was found.

**Always confirm the accessibility tree describes the screen actually on display before trusting
anything it says.**

### 3. Never destroy device state

- **Upgrade-install; never uninstall first.** Uninstalling wipes the data container, which usually holds
  a signed-in QA account — and re-creating it requires typing, which rule 1 forbids. If an install *did*
  wipe it, say so **prominently**, because it changes what QA can do next.
- **Never erase, reset, or reboot a simulator** another session may be mid-flight on, and **never boot a
  second one.** Check what is booted before and after (`xcrun simctl list devices booted`).
- Verify an install actually replaced the binary — a silent no-op means you are QA-ing stale code.

## 🔴 PREFLIGHT — run these THREE checks before installing or driving anything

Every past failure of this rig looked like "the driver is broken" and was actually one of three
operational faults. They are indistinguishable from a dead rig once you are mid-pass, and each has cost a
whole pass. **Assert all three first, report what you found, and stop with `VIEWER_UNAVAILABLE` if any
fails** — do not diagnose your way forward.

```
# 1. EXACTLY ONE driver, and it must carry the UDID argument
ssh <host> "pgrep -fl '[s]erve-sim' | cat"
#   → expect exactly ONE line, and the UDID must appear in it.
#   Two instances: the second silently falls back to the next port (3201) and you drive nothing.
#   No UDID argument: the preview starts but never attaches, so /ax has nothing to report —
#   a live-looking preview with no way to drive anything. The UDID is NOT optional.

# 2. The endpoint answers FROM YOUR MACHINE, not from the host's localhost
curl -s -m 5 -o /dev/null -w "%{http_code}\n" http://<host>:<port>/api      # expect 200

# 3. EXACTLY ONE booted device, and it is the one you mean
ssh <host> "xcrun simctl list devices booted | cat"
#   → expect one Booted line whose UDID matches check 1.
```

⚠️ **Do not assume the port.** One process serves both the preview UI and `/ax` in the foreground/launchd
topology; a different port is the helper default in detached mode. Probing the wrong one looks exactly
like a dead rig. Ask `/api` rather than guessing.

### The human must be able to watch — say how

**Report the preview URL** (`http://<host>:<port>`) in your first message, before the pass starts. A
correct-but-unwatched pass is not an acceptable outcome: the requester has said so explicitly, for two
reasons that have both bitten — a human can rescue an agent that has driven to the wrong screen in
seconds, and several QA conclusions here have been wrong in ways that watching would have caught cheaply.

**Also record video for the report.** It costs nothing and turns "trust me" into evidence:

```
xcrun simctl io <UDID> recordVideo --codec h264 <path>.mp4      # stop with SIGINT
```

Attach or reference the file, and say plainly if you could not capture it.

## Transport — get this right or QA is unusably slow

The driver runs on a remote host, so **how** you reach it dominates wall-clock. Three costs stack per
action, and they are separable. Measured on this setup: an ssh round trip ≈ **0.33s**, `npx <tool>`
adds **1–3s** of package resolution, and a direct HTTP read from the client machine is **11–41ms**.
Hundreds of actions later, that is the difference between minutes and an hour.

**1. READS go straight over HTTP from your own machine — never over ssh.** The accessibility tree, app
state and config are plain HTTP and are reachable directly. Since the stability rule below means every
action is followed by *two* tree polls, reads are the bulk of the traffic and the biggest win:

```
curl -s -m 5 "http://<host>:<port>/ax?device=<UDID>"        # SSE — the -m is required
curl -s -m 4 "http://<host>:<port>/api"                     # the contract: endpoints, binary path, token
```

**Do NOT ssh in to curl localhost** — that pays a full handshake to fetch something already exposed.

**2. NEVER invoke the CLI through `npx`.** It re-resolves the package on every call. Ask `/api` for the
resolved binary path and call it directly.

**3. BATCH each action with its settle and its read into ONE remote call.** `tap` → sleep → read tree
is one invocation, not three round trips.

**4. Raw input WebSockets are a last resort.** The exec channel authenticates with a token and accepts
input frames, and it *is* the fastest path — but it bypasses the CLI's validation, and an agent that
sent unnormalized pixel coordinates down it **crashed the driver and destroyed the session**. If you use
it, normalize coordinates exactly as the CLI would.

## Driving the simulator

- **Input coordinates are NORMALIZED 0..1.** Convert from points by dividing by the screen's point
  dimensions. Bypassing the CLI to send raw pixel coordinates to the underlying helper socket **crashes
  the helper** and loses the session.
- **Determine the driver's TOPOLOGY before assuming a port — do not guess.** Drivers of this kind run
  in either of two shapes, and they expose the accessibility tree in different places:
  - **Foreground / service-managed (one process):** it serves **both** the human-facing preview UI
    **and** the accessibility tree **on the same port**.
  - **Detached daemon (two processes):** a **helper** owns the device session and serves the tree plus
    input on its own port, while the **preview** is a separate web UI.

  Probing the wrong port returns nothing and **looks exactly like a dead rig**, which has sent people
  restarting a perfectly healthy driver. Check the tool's own `--help` for its port defaults and check
  which mode is actually running, then probe. In the two-process shape, a `--list` may report the
  preview's port while the helper you need is elsewhere — and killing the helper believing it redundant
  removes device attachment entirely.
- **Exactly one driver instance.** Two racing instances will silently fall back to alternate ports, and
  the resulting symptoms are indistinguishable from a broken rig. Confirm the process count before
  concluding anything is wrong.
- **The device identifier is usually not optional.** Started without one, a driver may bring up the
  preview but never attach to a device — a live-looking UI with an empty tree and no way to drive
  anything.
- **The accessibility tree has a one-poll lag** after any tap or scroll: the first fetch returns the
  pre-action frame, the next returns the settled one. **Treat only frames stable across ≥2 consecutive
  polls as ground truth, and cross-check against a screenshot.**
- **A scroll gesture only scrolls when the touch path starts over blank margin.** Starting over a button
  or pill is swallowed as a tap with zero scroll — which looks like "the list won't scroll".
- **Tap targets near the bottom edge:** coordinates below a label sit in the home-indicator dead zone and
  silently do nothing. Aim at the label, not the bar.
- Prefer the accessibility tree to answer "is X present / where do I tap"; reserve screenshots for
  pixels. Do **not** run a screenshot-after-every-action loop.

## What to actually exercise

- **Dynamic Type is not optional, and default-only testing is how clipping defects reach production one
  at a time.** `xcrun simctl ui <UDID> content_size <size>`. **Always sweep at least default, one mid
  size, and the largest accessibility size** — and report the size alongside every layout finding, since
  a frame measured at one size says nothing about another. Where an app's users skew older, large text is
  a normal accommodation for a substantial share of them, not an edge case.
- **Both orientations, if the app supports them** — check first whether it is orientation-locked
  (`orientation` in the Expo config); if it is, say so rather than reporting landscape as untested.
  Landscape leaves much less vertical room, so **keyboard occlusion and docked footers are materially
  worse there** — test those specifically rather than assuming portrait findings carry over.
- **Both themes**, if the app has them.
- **Distinguish clipping from corruption.** Text that is *vertically clipped* by a fixed-height container
  looks like broken glyph rendering in a screenshot and is not. The tell: the same string renders fine in
  a *flexible* container at the same size. Call it a layout-constraint defect, because "corrupted glyphs"
  sends the fix in the wrong direction.
- **Measure, don't eyeball, for occlusion.** Report the element's frame and the occluder's frame as
  numbers (`field y=502–539 vs footer y=488–531, ~29pt overlap`). "Looks hidden" is not actionable and
  cannot be compared against the next run.
- **Verify an interaction by its effect, not its pixels.** A button that is visible may still be
  untappable — confirm the step advanced, not that the button was on screen.

## Simulator fidelity — what a pass here does and does not prove

Faithful: local SQLite (real native engine, so migrations and adapters are genuinely exercised); network
sync for *correctness*. Not faithful: cellular and flaky links, real background suspension, and Dynamic
Type only *partly* (good enough to catch gross clipping, not to certify layout). **A legitimate
smoke-test surface, a poor sign-off surface** — say which you are providing.

## Absence and blockers get their own named outcomes

| Situation | Outcome |
|---|---|
| Driver/helper won't start, or the host is unreachable | `VIEWER_UNAVAILABLE` — **state it in the FIRST line**, not buried at the end |
| App installed but crashes on launch | `FAIL` with `stage: launch`, plus the crash log |
| A screen was never reached | `NOT_REACHED` — list it explicitly; never let unreached mean passed |
| Keyboard state was destroyed mid-pass (rule 1) | `INVALIDATED` — say which findings predate it and are still trustworthy |
| Ran clean | `OK` for the assigned scope only |

**Never report untested as passing, and never let "I couldn't get there" silently disappear.** A lens
that passed clean should say so explicitly.

Long output to `.claude/stack-ops/qa-expo-ios.log`; cite the path rather than pasting it.

## Clean up what you start

Every process you start, you stop — **including on the remote host.** Anything started over SSH (a
stream, a tunnel, a daemon) is your responsibility. If you deliberately leave something running because
the coordinator needs it, say so explicitly **with the PID and the stop command**: the difference between
"left running on purpose" and "leaked" must be visible from the report alone. Screen the simulator off or
leave it as you found it.

## Return this payload

```markdown
## qa-expo-ios: <OK | FAIL | VIEWER_UNAVAILABLE | INVALIDATED>

- **Build under test:** <version / build number> • **Artifact mtime:** <mtime>
- **Install:** <upgrade | fresh> • **Data container preserved:** <yes | NO — say what was lost>
- **Device:** <simulator model / iOS version / UDID>
- **Preflight:** driver instances <n, expect 1> carrying UDID <yes> • `/api` <200> • booted devices <n, expect 1>
- **Watchable at:** <preview URL, stated so the requester can watch> • **Video:** <path | NOT captured, why>
- **Driver restarted after install:** <yes | n/a> • **Tree matched live screen:** <yes>
- **Scope exercised:** <screens / flows>
- **Dynamic Type sizes:** <list> • **Themes:** <list>
- **Log:** <path>

### Findings (most severe first)
- **[blocker | major | minor]** <screen> — <one-line defect, precise enough to fix>
  - Repro: <numbered steps>
  - Measured: <frames/numbers where relevant>

### Not reached / not verified
<explicit list — always populated>

### Verdict
<ship-ready or not, for the assigned scope only, and whether this is smoke-test or sign-off confidence>
```

Nothing else.
