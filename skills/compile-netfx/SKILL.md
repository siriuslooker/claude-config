---
name: compile-netfx
description: Compile a .NET Framework project or solution (old-style csproj with TargetFrameworkVersion) using MSBuild located via vswhere, plus NuGet restore. Covers ASP.NET MVC 5 / WebForms web projects. Use when the stack manifest reports a netfx stack. Not for SDK-style net5.0+ projects, which use the dotnet CLI — see compile-netcore.
---

# Compile: .NET Framework (old-style csproj)

Mechanical. You compile and report. **You do not edit source code to make the build pass.**

⚠️ **`dotnet build` does not work here.** Old-style `.csproj` files (no `Sdk=` attribute, a
`<TargetFrameworkVersion>` element) need real MSBuild. `dotnet build` fails on them in ways that read as
source errors — missing types, unresolvable namespaces — which is the whole reason this skill exists.
If you find yourself reaching for `dotnet`, stop.

## Preflight — find MSBuild with vswhere, never by guessing

```
"C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" -latest -requires Microsoft.Component.MSBuild -find "MSBuild\**\Bin\MSBuild.exe"
```

Use the path it returns. Take the **first** result.

⚠️ **Do not use `where MSBuild.exe`, and do not hardcode a path.** A machine commonly has several
MSBuilds — a full Visual Studio install *and* a standalone BuildTools install — and `where` finds whichever
is first on PATH, which is frequently the wrong one. **BuildTools installs often lack
`Microsoft.WebApplication.targets`**, so a web project fails with `MSB4019: The imported project ... was not
found` — an error that looks like a broken repo and is a wrong-toolchain problem. `vswhere -latest` prefers
the full VS install, which is what you want.

If `vswhere` is absent or returns nothing, report `TOOLCHAIN_MISSING` with what you looked for. Do not
fall back to `dotnet`, and do not fall back to a guessed path.

Record the resolved MSBuild path and version (`MSBuild.exe -version -nologo`) in the payload — a build
that succeeds or fails under an unexpected MSBuild is the single most misleading result this skill can
produce.

## Restore

```
nuget restore <solution>
```

⚠️⚠️ **`nuget restore` does its OWN MSBuild auto-detection, and it will happily pick the wrong one —
silently, with exit code 0.** This is independent of the `vswhere` preflight above: resolving MSBuild for
the *build* does nothing to constrain what `nuget.exe` chooses for *restore*. Observed 2026-08-03 on the
first real run of this skill: nuget selected a broken `VS\18\BuildTools` install, **exited 0**, and restored
**1 package out of 31 projects' worth** — a clean success that left the solution unrestored. The build then
failed with missing-assembly errors that read exactly like source problems.

**Always pin it** to the same MSBuild directory vswhere resolved:

```
nuget restore <solution> -MSBuildPath "<dir of the vswhere-resolved MSBuild.exe>"
```

**And never trust restore's exit code alone.** Check that the restore actually did something proportionate
to the solution — package count, or `packages/` populated — and say so in the payload. A zero exit with one
package restored is the failure mode this note exists to catch.

- `nuget.exe` may be on PATH (Chocolatey installs it there) — check with `where nuget.exe`. If it is
  absent, report `TOOLCHAIN_MISSING`; do not download it.
- **Prefer `nuget restore <solution>` over `MSBuild -t:restore`.** A solution of this age is frequently
  **mixed**: most projects on `PackageReference` with a couple still carrying `packages.config`.
  `-t:restore` handles only the former, so the `packages.config` projects fail later at compile time with
  missing-assembly errors that look like source problems. `nuget restore` on the solution handles both.
- Restore separately and report its outcome separately. A restore failure is `FAIL` with
  `stage: restore` — **not** a compile failure, and not something to retry by building anyway.

## Build

Prefer the solution over individual projects — it catches cross-project breakage.

```
MSBuild.exe <solution> -nologo -v:m -m -p:Configuration=Debug
```

- `-v:m` (minimal) keeps output readable while still printing errors and warnings; `-q` hides warnings
  you are meant to report.
- `-m` builds projects in parallel. If a failure looks non-deterministic or the log interleaves
  confusingly, re-run **once** without `-m` and say you did — parallel builds scramble output ordering.
- `-p:Configuration=Release` only if the caller asked for Release.
- **Never pass `-t:Rebuild` unless asked.** It is slow and discards incremental state for no diagnostic gain.
- ⚠️ **Never pass a publish/deploy target** (`-t:Package`, `-t:MSDeployPublish`, `DeployOnBuild=true`).
  Compiling is not deploying; see `deploy-*` for that.
- Long output goes to `.claude/stack-ops/compile-netfx.log`. Cite the path; do not paste the output.

## Non-interactive

MSBuild and `nuget restore` do not prompt, but two things can still hang a session:

- **A NuGet feed needing credentials** blocks on a credential-provider prompt. If restore stalls or
  reports a 401 against a private feed, report `TOOLCHAIN_MISSING` naming the feed and the fact that it
  needs authentication (VPN or credentials) — do not retry in a loop.
- Set `CI=true` so any tooling that honours it stays non-interactive.

## Reading the result

Exit code is the signal. Then:

- **Errors** (`error CS####`, `error MSB####`, `error NU####`) — report every distinct one with
  `file:line` and the message. **Deduplicate:** MSBuild prints each error inline *and* in the summary,
  and with `-m` a shared project's error repeats once per referencing project. Report it once, and say
  how many projects it surfaced through if that is load-bearing.
- **Warnings** — only about code in this repo. Drop noise from `packages/`, `obj/`, and generated files.
  Cap at 8; above that summarize by rule id (`31 × CS0618 obsolete`).

Failure modes worth naming explicitly, because each looks like a source bug and is not:

- **`MSB4019: The imported project "...\WebApplications\Microsoft.WebApplication.targets" was not
  found`** — wrong MSBuild. A BuildTools install without the web workload cannot build MVC/WebForms
  projects. Re-resolve via `vswhere -latest` and report which install you used.
- **`MSB3644: The reference assemblies for .NETFramework,Version=vX.Y were not found`** — the targeting
  pack for that framework version is not installed. A toolchain gap, not a code error.
- **Missing assembly / `CS0246` on a package type** — check restore actually ran for *that* project;
  a `packages.config` project in a mixed solution is the usual culprit (see Restore above).
- **`CS0234`/`CS0246` on a type you can see in the repo** — check the file is tracked and present
  (`git ls-files <path>`, `git check-ignore -v <path>`). A `.gitignore` rule differing from a source
  folder only by case silently excludes source on Windows.
- **Binding-redirect and package-version conflicts (`MSB3277`)** — report the conflicting versions.
  ⚠️ Do **not** "fix" a binding redirect or bump a package to silence it: an old solution's redirect
  baseline is deliberate, and changing it can break unrelated projects at runtime rather than compile time.

## Absence gets its own outcome

| Situation | Outcome |
|---|---|
| No `.sln` and no `.csproj` found | `NO_ENTRY` — list what you globbed for |
| `vswhere` missing, or no MSBuild found | `TOOLCHAIN_MISSING` — name what you looked for |
| `nuget.exe` unavailable | `TOOLCHAIN_MISSING` — do not download it |
| Restore fails | `FAIL`, `stage: restore` — not a compile result |
| Restore exits 0 but restores implausibly few packages | `FAIL`, `stage: restore` — nuget picked the wrong MSBuild; pin `-MSBuildPath` and retry once |
| Private feed needs credentials | `TOOLCHAIN_MISSING` — name the feed; do not retry |
| Targeting pack absent (`MSB3644`) | `TOOLCHAIN_MISSING` — not a code error |

Never report a pass you did not observe, and never smooth an absence into one.

## Return this payload

```markdown
## compile-netfx: <OK | FAIL | NO_ENTRY | TOOLCHAIN_MISSING>

- **Entry:** <path>  •  **Configuration:** <Debug|Release>
- **MSBuild:** <version> at <resolved path>  •  **Resolved by:** vswhere
- **Restore:** <OK | FAIL | skipped>  •  **Elapsed:** <seconds>
- **Log:** <path, if written>
- **Errors:** <count>  •  **Warnings (this repo):** <count>
- **Projects built:** <n of m>

### Errors
- `<file>:<line>` — `<code>` <message>

### Warnings
- `<file>:<line>` — `<code>` <message>

### Notes
<toolchain anomalies, which MSBuild install was used and why, retries, or "none">

### Not verified
<what this run did not cover — e.g. tests were not run, Release not built, no project excluded from the solution was checked>
```

Nothing else. No preamble, no "I have completed".

## Related

- **Tests are a separate skill.** A `netfx` solution's test projects need VSTest
  (`vstest.console.exe`, also locatable via `vswhere`), not `dotnet test`, when they target
  `net4x`. If the caller wants tests and no `test-netfx` skill exists, report that rather than
  improvising — see `authoring-stack-ops-skills`.
- **Build order:** if the repo also has a `node` stack whose bundle is embedded by the .NET app, the
  node build runs first. See `compile-node`.
