---
name: qa-expo-android
description: Drive an Expo/React Native app on a tethered Android device via scrcpy-mcp and report defects — install, navigate by accessibility hierarchy, exercise font scale and keyboard-overlay layout, confirm sync moved real bytes. Encodes the IME and edge-to-edge constraints that silently invalidate a pass. Use when the stack manifest reports an expo-android stack and the task is to exercise a running app.
---

# QA: Expo / React Native — Android device

You exercise a **running** app on real hardware and report what you observe. **Read-only: you never fix
what you find.** Tests prove the code does what the tests say; you find out whether the app does what a
user needs.

Host facts — device serial, MCP server name, env-var setup, bundle identifier — live in
**`~/.claude/CLAUDE.machine.md`**. Read them there; never hardcode them here.

## ⚠️ The IME trap — read this before any keyboard test

A QA station may have a **headless IME installed for convenience** (e.g. ADBKeyBoard), which accepts text
over a broadcast and **renders no on-screen keyboard at all.** It makes text entry fast and is the right
default for most QA.

**But it makes every keyboard-overlay layout test produce a confident FALSE PASS.** With no visible
keyboard there is nothing to occlude a field, so a genuine occlusion defect cannot manifest, and the run
reports clean. This is the worst possible failure mode: a green result on the exact defect class you were
asked to check.

**So, before testing anything keyboard-related — occlusion, scroll-into-focus, pinned footers, keyboard
dismissal, focus chains — swap back to a real soft keyboard.** Do not assume; check.

```
adb -s <serial> shell settings get secure default_input_method   # what is active NOW
adb -s <serial> shell ime list -s                                # enabled IME ids
adb -s <serial> shell ime set <real-keyboard-ime-id>             # swap to a real one
adb -s <serial> shell ime reset                                  # restore the device default
```

**Enumerate with `ime list -s` and pick — never hardcode an IME id**, which varies by vendor and ROM.
`ime reset` is the clean way back to the device default afterwards.

Rules that follow:

- **State in your report which IME was active** for the findings you are reporting. A keyboard finding
  without that context is unverifiable.
- If you swapped the IME, **swap it back** in your teardown (see below) — the next session expects the
  fast-entry default.
- With a real keyboard active, text entry is slower and the keyboard covers part of the screen; re-read
  coordinates from a fresh hierarchy dump after it opens.
- **Autofill can hijack fields** on a real keyboard (a password manager offering to fill). Disable it for
  the run with `settings put secure autofill_service null`, and restore the previous value in teardown.

## Edge-to-edge: why keyboard bugs look impossible here

On modern Expo (SDK 54+), **edge-to-edge is forced with no supported opt-out**, so:

- **The window never shrinks when the keyboard opens.** With the keyboard up, the accessibility root
  stays full-height. Declaring `softwareKeyboardLayoutMode`/`adjustResize` does nothing, because there is
  no window to resize — insets arrive via `WindowInsets` instead.
- Therefore **an app must lift content explicitly**, and "Android handles this for free" is false on this
  stack. Do not accept it as an explanation for a defect.
- **`endCoordinates.height` excludes the system navigation-bar inset** while the keyboard visually covers
  it, so an app lifting by that value alone undershoots by roughly the gesture-nav inset — presenting as
  a thin sliver of content still occluded. Report the sliver's measured height; it is a real clue, not a
  rounding artefact.

**Verify an interaction by its effect, not its pixels.** A visible button may still be untappable — a
partially-occluded button has been visible and non-functional at the same time. Confirm the step actually
advanced.

## Driving the device

The device is driven by the **scrcpy-mcp** MCP server (tools `mcp__android__*`; load schemas via
ToolSearch). Prefer the **real `scrcpy` executable** for the viewer rather than a video-stream tool that
pipes MJPEG into a passive player: an interactive window lets a human grab the mouse and correct an agent
that has driven to the wrong place, which has been needed repeatedly.

```
scrcpy -s <serial> --stay-awake --max-size 900 --window-title "QA"
```

⚠️ **Unresolved constraint — do not assume either way.** There is **one scrcpy encoder session per
device**, so a manual `scrcpy` window and an active scrcpy-mcp session **may** conflict; this has never
been tested. Two workable shapes:

1. Manual `scrcpy` for the view **plus `stop_session`**, letting input fall back to plain adb — always
   safe, but markedly slower.
2. Both at once, *if* they coexist.

Prefer (1) until someone tests it, **say which you used**, and if you do test it, record the answer
rather than leaving it to be rediscovered.

Tool discipline:

- **`ui_find_element` / `ui_dump` answer "is X present / where do I tap"** — deterministic, and preferred.
  Reserve `screenshot` for pixels. **Never run a screenshot-after-every-action loop.**
- **Coordinates drift** across scroll and keyboard state — re-read from a fresh dump immediately before
  each tap.
- **Install and uninstall are host-side adb**, not scrcpy-mcp: `adb install -r <apk>`. scrcpy-mcp only
  drives on-device interaction.
- **Log, network and crash forensics** go through `shell_exec` or host adb; there is no dedicated tool.

## What to actually exercise

- **Font scale** — `settings put system font_scale <1.0|1.3|2.0>`; restore it afterwards. Sweep default,
  mid, and maximum. This is where layout defects concentrate, and it matters disproportionately for an
  older user base.
- **Distinguish clipping from corruption.** Text vertically clipped by a fixed-height container looks
  like broken glyph rendering in a screenshot and is not. The tell: the same string renders fine in a
  *flexible* container at the same size. Call it a layout-constraint defect — "corrupted glyphs" sends
  the fix in the wrong direction.
- **Measure occlusion in numbers**, not impressions: report the element's bounds and the occluder's
  bounds (`field [0,502][1080,539] vs footer [0,488][1080,531]`). "Looks hidden" is not actionable and
  cannot be compared against the next run.
- **Migrations over existing data.** A fresh install does not run `ALTER TABLE`. To exercise an upgrade
  path you must **install over the previous build without clearing data**, and say that you did.
- **Sync**, if the app syncs: a **release build refuses `run-as`**, so the database cannot be read
  directly, and if the app logs little, **network byte deltas are the only reliable signal that a sync
  happened** — `dumpsys netstats detail`, comparing the app UID's rx/tx before and after. Report the
  deltas. Zero bytes on an action that should sync is a finding.

## Absence and blockers get their own named outcomes

| Situation | Outcome |
|---|---|
| Viewer/MCP session won't start, device unauthorized or offline | `VIEWER_UNAVAILABLE` — **state it in the FIRST line**, not buried at the end |
| App crashes on launch | `FAIL` with `stage: launch`, plus the logcat excerpt |
| Install silently no-opped (same or lower versionCode) | `STALE_BUILD` — **you tested the old code; findings are void** |
| A screen was never reached | `NOT_REACHED` — list it; never let unreached mean passed |
| Keyboard finding gathered under a headless IME | `INVALIDATED` for those findings — say so plainly |
| Ran clean | `OK` for the assigned scope only |

**Never report untested as passing.** A lens that passed clean should say so explicitly.

Long output to `.claude/stack-ops/qa-expo-android.log`; cite the path rather than pasting it.

## Teardown — unconditional, on the happy path AND on any error or abort

Neither scrcpy nor scrcpy-mcp cleans up after itself, and every setting you changed is still changed.

- Restore **IME** (`ime reset`), **font scale**, and **autofill** to what you found.
- Close the `scrcpy` process you launched; `stop_session` if you started one; `screen_off`.
- Anything started over adb or SSH is yours to stop.

**Exception:** if a human asked for a live view (a demo or a call), leave it up and say so explicitly
**with the PID and the stop command**. The difference between "left running on purpose" and "leaked" must
be visible from the report alone.

## Return this payload

```markdown
## qa-expo-android: <OK | FAIL | VIEWER_UNAVAILABLE | STALE_BUILD | INVALIDATED>

- **Build under test:** versionName <x> / versionCode <n> — **confirmed from the artifact, not the manifest**
- **Install:** <upgrade over vN (migration path exercised) | fresh> • **Data cleared:** <yes|no>
- **Device:** <model / Android version / serial>
- **IME active:** <id> — <headless | real soft keyboard>
- **Font scales:** <list> • **Themes:** <list>
- **Viewer shape:** <manual scrcpy + stop_session | mcp session> 
- **Log:** <path>

### Findings (most severe first)
- **[blocker | major | minor]** <screen> — <one-line defect, precise enough to fix>
  - Repro: <numbered steps>
  - Measured: <bounds / byte deltas / scale where relevant>

### Not reached / not verified
<explicit list — always populated>

### Restored in teardown
<IME, font scale, autofill, processes — or what you deliberately left and why>

### Verdict
<ship-ready or not, for the assigned scope only>
```

Nothing else.
