---
name: compile-netcore
description: Compile a modern .NET (net5.0+ SDK-style) project or solution with the dotnet CLI — restore, build, and report errors and actionable warnings. Use when the stack manifest reports a netcore stack. Not for .NET Framework projects, which need MSBuild.
---

# Compile: .NET (SDK-style, net5.0+)

Mechanical. You compile and report. **You do not edit source code to make the build pass.**

## Preflight

```
dotnet --version
```

If `dotnet` is missing, or the SDK major version is lower than the highest `<TargetFramework>`
in the solution, stop and report `TOOLCHAIN_MISSING` with both versions. Do not attempt a
downgrade or a `global.json` edit.

## Build

Prefer the solution over individual projects — it catches cross-project breakage.

```
dotnet build <entry> --nologo -v q
```

- `<entry>` is the `.slnx`/`.sln` from the manifest; fall back to the `.csproj` if there is no
  solution. Use the path as given — do not `cd` first.
- `dotnet build` restores implicitly. Only run `dotnet restore` separately if the build fails
  with NU\* package-resolution errors; then retry the build once and say you did.
- Add `-c Release` only if the caller asked for Release.
- If output is long, keep it out of your reply — write it to `.claude/stack-ops/compile-netcore.log`
  and cite the path.

## Reading the result

Exit code is the signal. Then:

- **Errors** (`error CS####`, `error NU####`, `error MSB####`) — report every distinct one with
  `file:line` and the message. Deduplicate: MSBuild prints each error twice (once inline, once
  in the summary); report it once.
- **Warnings** — report only ones about code in this repo. Drop package/framework/analyzer noise
  from `~/.nuget` or generated `obj/` files. Cap at 8; above that, summarize by rule id
  (`12 × CS8618 nullable`).

Two failure modes worth naming explicitly, because they look like source bugs and are not:

- **`CS0234` / `CS0246` on a type you can see in the repo** — check whether the file is actually
  tracked and present (`git ls-files <path>`, `git check-ignore -v <path>`). A `.gitignore` rule
  that differs from a source folder only by case will silently exclude source on Windows.
- **A namespace in the project shadowing a BCL one** (a project namespace ending `.Directory`
  shadows `System.IO.Directory`). Report it as needing a fully-qualified reference — say so;
  don't fix it.

## Return this payload

```markdown
## compile-netcore: <OK | FAIL | TOOLCHAIN_MISSING>

- **Entry:** <path>  •  **Configuration:** <Debug|Release>  •  **SDK:** <version>
- **Elapsed:** <seconds>
- **Log:** <path, if written>
- **Errors:** <count>
- **Warnings (this repo):** <count>

### Errors
- `<file>:<line>` — `<code>` <message>

### Warnings
- `<file>:<line>` — `<code>` <message>

### Notes
<toolchain/tracking anomalies, or "none">
```

Nothing else. No preamble, no "I have completed".
