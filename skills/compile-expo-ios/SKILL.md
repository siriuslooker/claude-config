---
name: compile-expo-ios
description: Build an Expo/React Native iOS app for the simulator on a remote macOS host over SSH — tree sync, expo prebuild, pod install, xcodebuild Release — and report the artifact with its real identity. Covers CocoaPods deployment-target normalisation and Hermes-bundle fingerprinting. Use when the stack manifest reports an expo-ios stack.
---

# Compile: Expo / React Native — iOS simulator

Mechanical. You sync, prebuild, pod-install, build, and report what came out. **You do not edit source
to make the build pass**, and you never report a build you did not see succeed.

Host facts — ssh alias, IP, UDIDs, bundle identifier, working directory — live in
**`~/.claude/CLAUDE.machine.md`** under the relevant host. Read them there; never hardcode them here.

## Preflight

The toolchain is on a **remote Mac**. Every failure below has cost a wasted run:

- **`-o ConnectTimeout=60` on every ssh call.** Shorter handshakes fail whenever the Mac is loaded.
- **`export PATH=/opt/homebrew/bin:$PATH` in every remote shell.** A non-interactive SSH shell does not
  get Homebrew on PATH, so `node`/`pnpm`/`npx` appear missing when they are installed.
- **`timeout` does not exist on macOS.** Do not reach for it.
- **A Mac that has idle-slept stops answering ARP**, which looks exactly like a dead network — the link
  reports active at full speed with zero errors on both ends. If the host is unreachable, report
  `HOST_UNREACHABLE` and say to check for a sleep assertion (`pmset -g assertions`). Diagnose sleep from
  **`pmset -g log`** (history), never `pmset -g` (an instant snapshot, which lies).

```
ssh -o ConnectTimeout=60 <alias> 'export PATH=/opt/homebrew/bin:$PATH; sw_vers -productVersion; xcodebuild -version; node --version; pnpm --version'
```

If Xcode or the simulator runtime is absent, report `TOOLCHAIN_MISSING`. **Never install a simulator
runtime** — runtime sets are curated deliberately.

## Sync the tree

The local working tree is the source of truth, so **uncommitted changes are included and you never need
to commit to build.**

- **Use tar-over-ssh, not rsync.** On a Windows host, `rsync` fails with *"source and destination cannot
  both be remote"*, and macOS ships openrsync/BSD whose flags differ from GNU's. Tar avoids both.
- **Exclude `ios/` and `android/`** from the sync. `ios/` must survive so its `Pods/` do; `android/` is
  irrelevant here and large.
- Also exclude `node_modules/`, `.git/`, build output, and `.local-builds/`.

## Install dependencies on the Mac

Use the package manager the lockfile names — never mix. For pnpm:

```
pnpm install --frozen-lockfile
```

**pnpm ≥ 10 declares `patchedDependencies` in `pnpm-workspace.yaml`, not `package.json`.** If a build
depends on a patch, check there; `package.json` will look as though no patch is tracked. Confirm
`patches/` exists and the lockfile carries the matching `patch_hash` — a patch that silently failed to
apply produces a build failure with no mention of patching.

Native modules compile during install on Apple Silicon; a failure here is `TOOLCHAIN_MISSING`, not a
code failure.

## Prebuild — and what it destroys

```
CI=1 npx expo prebuild --platform ios --no-install
```

`CI=1` is mandatory: prebuild prompts interactively otherwise and will hang the session.

**Prebuild regenerates `ios/` wholesale.** Everything that follows from that:

- A hand edit to `ios/Podfile`, a podspec, or the Xcode project **silently disappears.** The only
  durable mechanism is an **Expo config plugin** referenced from `app.json`. If you find yourself
  wanting to edit a generated file, that is a signal to report it, not to edit it.
- `CFBundleShortVersionString` comes from `app.json`, so a project that has not been prebuilt since the
  version changed produces **correctly-built but mislabelled artifacts.** Check the built app's version
  against the manifest rather than assuming.

## `pod install` — mandatory, and again after any move

```
cd <repo>/packages/<mobile-pkg>/ios && pod install
```

Run it after every prebuild, **and after the tree ever moves on disk.** CocoaPods bakes **absolute
paths**; after a move, stale references break pods with misleading errors (a missing macro-plugin error,
not a path error). Re-podding is the fix and takes seconds.

### Verify deployment targets before spending a build

`expo-build-properties`' `ios.deploymentTarget` raises **only the app targets** — pods keep their own
podspec floors. A pod compiling for an old target against a much newer SDK **crashes the Swift
compiler** rather than producing an error. Measure it in seconds instead of discovering it in a cold
build:

```
grep -c 'IPHONEOS_DEPLOYMENT_TARGET = <expected>' ios/Pods/Pods.xcodeproj/project.pbxproj
grep -o 'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]*' ios/Pods/Pods.xcodeproj/project.pbxproj | sort | uniq -c
```

Every pod target should sit at the expected version. If most sit lower, the raising mechanism (normally
a config plugin adding a `post_install` step) is not working — report it and stop. **Do not fix this by
passing `IPHONEOS_DEPLOYMENT_TARGET` on the `xcodebuild` command line**: it leaks into pods' nested
`xcodebuild` invocations through the environment and breaks their platform resolution.

## Build — Release, never Debug

```
cd <repo>/packages/<mobile-pkg>/ios && xcodebuild \
  -workspace <App>.xcworkspace -scheme <App> \
  -configuration Release -sdk iphonesimulator \
  -destination "id=<UDID>" -derivedDataPath <build-dir> \
  CODE_SIGNING_ALLOWED=NO build
```

Simulator builds need **no Apple account and no signing** — `CODE_SIGNING_ALLOWED=NO` is sufficient.

**Release, not Debug, and the generic RN reasoning does not apply.** The usual advice — "Debug is better
for iterating because reload beats rebuild" — is wrong on a **bare** Expo project that does not have
`expo-dev-client` installed. `expo start` without `--dev-client` serves an *Expo-Go-flavoured* bundle
into a bare app; JS throws at module init, so nothing registers, and you get a deterministic redbox:

```
[runtime not ready]: TypeError: Cannot read property 'default' of undefined
[runtime not ready]: Error: Non-js exception: AppRegistryBinding::startSurface failed. Global was not installed.
```

Neither error mentions Expo, so it reads as a code bug and is not one. **Check whether
`expo-dev-client` is in the manifest before ever suggesting Debug.** If it is absent, Debug is not an
option — say so rather than offering it.

Timing: expect ~1–2 min incremental, ~8–30 min cold (much longer if the project sets
`buildReactNativeFromSource`). Cold builds exceed a foreground tool timeout — run them backgrounded and
**never write "I'll wait for it" and end your turn.** End with an explicit
*"verification is PENDING, not done"* status naming what you will check on re-invocation. If re-invoked
while a build is still live, re-state pending status; check for a running `xcodebuild` and **never start
a second concurrent build.**

## Reading the result

- **A failure with zero `error:` lines means the compiler CRASHED**, not that code was rejected. Grep
  for `BUILD FAILED` and `Command … failed`, and read the stack trace — `swift-frontend` inside
  `clang::ASTReader::ReadASTBlock` means it died reading a precompiled module (a deployment-target or
  compilation-mode problem, not your source).
- **Use `grep -F`.** The literal `**` in `** BUILD FAILED **` is an invalid regex and silently matches
  nothing — a search that cannot succeed reads as a pass.
- **Locate the artifact by mtime, never an assumed path.** Derived-data layout varies between
  invocations; a hardcoded path has twice produced a false "build FAILED" on a build that succeeded.
- **Beware partial products.** A `.app` from a failed attempt can linger with no `Info.plist`. Trust a
  product only if its mtime is fresh **and** its version string checks out.

## Prove the change is in the artifact

The JS bundle is **Hermes bytecode**, not minified JS. Only Hermes' **string table** is greppable:
string literals and identifier/property *names* survive; **source syntax does not** — a `prop: value`
pair compiles to binary instructions with keys and values in separate buffers, so grepping for
`numberOfLines:2` returns nothing even when the code is present.

Choose a fingerprint that **cannot pass by accident**:

- ✅ A string literal **new in this change** — a `testID` works well.
- ❌ A symbol that exists in a framework's own source (it passes regardless).
- ❌ A string added several rounds earlier (proves the bundle is recent, not that *this* fix is in).
- ❌ Source syntax (ungreppable, per above).
- ❌ **A version string composed from a template literal** — it is assembled at runtime and never
  appears as one string-table entry, so the grep returns 0 on a perfectly good build.

**A check that cannot fail is worse than no check.** If the change adds no new literal, say so plainly
rather than substituting a fingerprint that always passes.

## Absence and failure get their own named outcomes

| Situation | Outcome |
|---|---|
| Remote host does not answer | `HOST_UNREACHABLE` (say whether sleep was checked) |
| No Xcode / no simulator runtime / package manager missing | `TOOLCHAIN_MISSING` — not a code failure |
| No `app.json`/`app.config.*` with an `expo` key, or no iOS-capable manifest | `NO_IOS_PROJECT` (list what you checked) |
| `expo prebuild` fails | `FAIL` with `stage: prebuild` |
| `pod install` fails | `FAIL` with `stage: pods` |
| `xcodebuild` fails with `error:` lines | `FAIL` with `stage: compile` |
| `xcodebuild` fails with **no** `error:` lines | `FAIL` with `stage: compiler-crash` |
| Build succeeded, artifact not found or stale | `FAIL` with `stage: artifact` — never `OK` |

**Never deploy or distribute.** Producing the artifact is the job; installing it on a simulator belongs
to QA, and publishing it is a separately-approved step.

Write long output to `.claude/stack-ops/compile-expo-ios.log` and cite the path rather than pasting it.

## Return this payload

```markdown
## compile-expo-ios: <OK | FAIL | TOOLCHAIN_MISSING | HOST_UNREACHABLE | NO_IOS_PROJECT>

- **Host:** <alias> • **macOS:** <ver> • **Xcode:** <ver>
- **Sync:** <method> → <files/bytes>, exclusions honoured <yes/no>
- **Install:** <command> → <ok | skipped> • **Patches:** <n applied | none declared>
- **Prebuild:** <ok | skipped (ios/ present and current)>
- **Pods:** <n installed> • **Deployment targets:** <n at expected / m below>
- **Build:** <configuration>/<sdk> → <ok | failed at stage>
- **Artifact:** <path> • <bytes> • <mtime> • version <CFBundleShortVersionString>
- **Fingerprint:** <literal searched> → <found | not found | none available this round>
- **Elapsed:** <duration> • **Log:** <path>

### Errors
- `<file>:<line>` — <message>   (or the crash signature, for a compiler crash)

### Not verified
<what you could not confirm — always populated, never "n/a">
```

Nothing else.
