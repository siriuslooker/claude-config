---
name: stack-detect
description: Detect which technology stacks are present in the current repository and which stack-ops skills apply. Use at the start of any build, compile, test, qa, or deploy run so the right per-stack skill is chosen instead of guessed. Returns a stack manifest.
---

# Stack detection

Produce a **stack manifest** — the list of stacks present in this repo, each with the paths
and the stack-ops skill that handles it. Detect, don't assume; a repo may hold several stacks
(this is the normal case for a .NET app that serves an SPA).

## Rules

Do **not** shell out to a recursive `find`. Use Glob, and always exclude `node_modules/`,
`bin/`, `obj/`, `dist/`, `.git/`, and vendored or read-only reference checkouts (a nested
`.git`, or paths the project's `.claude/settings.json` `deny`-lists).

Run these globs and classify:

| Glob | Then check | Stack id | Skills |
|---|---|---|---|
| `**/*.slnx`, `**/*.sln` | — | solution root for `netcore`/`netfx` | — |
| `**/*.csproj`, `**/*.fsproj`, `**/*.vbproj` | contains `Sdk="Microsoft.NET.Sdk*"` **and** `<TargetFramework>net5.0`+ | `netcore` | `compile-netcore`, `test-netcore`, `deploy-netcore` |
| `**/*.csproj` | contains `<TargetFrameworkVersion>` (old-style, no `Sdk=` attribute) | `netfx` | *(none installed — see "Unhandled stacks")* |
| `**/package.json` | not under `node_modules/`; has a `scripts` block | `node` | `compile-node`, `test-node`, `deploy-node` |

For each detected stack record:

- **`root`** — the directory to run commands from (solution/`package.json` directory).
- **`entry`** — the file a build targets (`Foo.slnx`, `package.json`).
- **`scripts`** / **`projects`** — for `node`, the actual `scripts` keys present; for `netcore`,
  the project list. Never invent a script name — read `package.json` and use what is there.
- **`test_projects`** — `netcore`: projects whose name matches `*.Test*`/`*.Spec*` **or** that
  reference `xunit` / `nunit` / `MSTest`. `node`: a `test` script, or a `vitest`/`jest`/`mocha`
  devDependency. **Empty is a valid, reportable answer.**
- **`package_manager`** — `node` only: `pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn,
  `package-lock.json` → npm. Default npm. Never mix.

## Unhandled stacks

If you detect a stack with no installed skill (e.g. `netfx`, which needs MSBuild via `vswhere`,
not `dotnet build`), report it under `unhandled` with the reason. **Do not substitute a
different stack's skill** — running `dotnet build` on a `<TargetFrameworkVersion>` project
fails in confusing ways. Adding a stack means adding a skill; say so.

## Return this manifest

```markdown
## Stack manifest

- **Repo root:** <path>
- **Detected:** <comma-separated stack ids, or "none">

### <stack id>
- **Root:** <path>
- **Entry:** <file>
- **Package manager:** <npm|pnpm|yarn — node only>
- **Available scripts / projects:** <list>
- **Test projects:** <list, or "NONE — no test harness in this stack">
- **Skills:** <compile-x, test-x, deploy-x>

### Unhandled
- **<stack id>:** <why — what tooling it needs and which skill is missing>
```
