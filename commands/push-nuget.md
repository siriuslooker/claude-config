---
description: Push a built .nupkg to the private work NuGet feed via dotnet nuget push (VPN + gated).
argument-hint: <path-to.nupkg> [--source <name-or-url>] [--skip-duplicate]
allowed-tools: Bash(dotnet nuget push:*), Bash(jq:*), Bash(ls:*), Bash(test:*), Bash(curl:*), Read
---

Publish a NuGet package to the private work feed — its host is the `hosts[0]` of the `credentials.json` entry whose label contains "Nuget". There is no built-in NuGet-push tool; this wraps the established manual method (`dotnet nuget push` with the API key stored in `~/.claude/credentials.json`) plus the VPN pre-check and a publish gate.

## Arguments

`$ARGUMENTS` = the path to the `.nupkg`, optionally followed by flags. Example: `/push-nuget src/eventsential-sitefinity-integration-library/artifacts/RDMobile.Sitefinity.2026.1.728.900.nupkg`

- First token: absolute or relative path to the `.nupkg` to push.
- `--source <name-or-url>` (optional): defaults to the feed host from `credentials.json` (see Notes), which is also the source name registered in the user NuGet.Config → `https://<feed>/nuget`.
- `--skip-duplicate` (optional): pass through to allow re-running without failing if the version already exists.

If no `.nupkg` path was given, ask the user for it and stop. If a directory or glob was given, list matching `*.nupkg` and confirm which one before proceeding.

## Steps

1. **Verify the package exists** (`test -f "<path>"`). If missing, report and stop. Echo the resolved filename so the version being pushed is explicit.

2. **VPN pre-check** — the private feed is only reachable on the corporate VPN. Test reachability (do NOT push if it fails):
   ```
   FEED=$(jq -r '[.credentials[]|select(.label|test("Nuget"))][0].hosts[0]' ~/.claude/credentials.json)
   curl -s -o /dev/null -w "%{http_code}" --max-time 8 "https://$FEED/nuget"
   ```
   A timeout / connection failure (empty or `000`) means the VPN is down → tell the user to start the VPN and wait for confirmation before pushing. Any HTTP response (even 401/403 to the bare URL) proves reachability.

3. **Gate before publishing** — pushing to a shared feed is an outward publish. Present the package filename, version, and target source, and get explicit approval (AskUserQuestion) before running the push. Do not push on your own initiative.

4. **Push** via the **Bash tool** (dotnet CLI). Read the key inside the command — NEVER echo it; redact it from any echoed output:
   ```
   FEED=$(jq -r '[.credentials[]|select(.label|test("Nuget"))][0].hosts[0]' ~/.claude/credentials.json)
   KEY=$(jq  -r '[.credentials[]|select(.label|test("Nuget"))][0].accessKey' ~/.claude/credentials.json)
   dotnet nuget push "<path-to.nupkg>" --source "$FEED" --api-key "$KEY" 2>&1 | sed -E "s/$KEY/<redacted>/g"
   ```
   (append `--skip-duplicate` if requested).

5. **Verify** the package is live on the feed (read-only GET; no auth needed for the query):
   ```
   curl -s "https://$FEED/nuget/FindPackagesById()?id='<PackageId>'" | grep -oE "<d:Version>[^<]+</d:Version>"
   ```
   Confirm the just-pushed version appears. Report success with the package id + version + feed.

## Notes

- **API key:** `~/.claude/credentials.json`, the entry whose label contains **"Nuget"**, field **`accessKey`** (NOT `password`). The feed host is that entry's `hosts[0]`, and its `notes` confirm VPN is required. Never print the key.
- **Duplicate version:** the feed rejects re-pushing an existing version (HTTP conflict). Bump `<Version>` in the source `.csproj` and rebuild/repack, or pass `--skip-duplicate` if a no-op re-run is intended.
- **Where packages are built:** SDK-style libs with `GeneratePackageOnBuild=true` emit the `.nupkg` to their `PackageOutputPath` (often `../artifacts`) on `dotnet build -c Release`. `dotnet pack` alone can fail `NU5026` when packaging is bound to the build target — build instead.
- **A local folder feed is not the shared one:** copying a `.nupkg` into a local `nupkgs` directory only serves restores on that machine; publishing for CI or anyone else requires this push to the shared feed.
- Run pushes only after explicit approval, consistent with the repo's gated-publish rule.
