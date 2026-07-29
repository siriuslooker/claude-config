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

## Driving the simulator

- **Input coordinates are NORMALIZED 0..1.** Convert from points by dividing by the screen's point
  dimensions. Bypassing the CLI to send raw pixel coordinates to the underlying helper socket **crashes
  the helper** and loses the session.
- **Two driver processes have distinct roles**, and confusing them is a known trap: the **helper** owns
  the device session and serves the accessibility tree plus input; the **preview** is only a web UI a
  human watches. A `--list` may report the preview's port while the helper you need is elsewhere.
  Killing the helper believing it redundant removes device attachment entirely.
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

- **Both themes**, if the app has them, and **both orientations** if supported.
- **Dynamic Type** — `xcrun simctl ui <UDID> content_size <size>`. Sweep at least default, one mid size,
  and the largest accessibility size. This is where layout defects concentrate.
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
