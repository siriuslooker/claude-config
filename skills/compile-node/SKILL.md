---
name: compile-node
description: Install dependencies and build a Node/TypeScript project (Vite, tsc, webpack, Next, etc.), plus lint and typecheck, reporting compiler and lint diagnostics. Use when the stack manifest reports a node stack.
---

# Compile: Node / TypeScript

Mechanical. You install, build, and report. **You do not edit source code to make the build pass.**

## Preflight

```
node --version
npm --version
```

Compare against `engines` in `package.json` if present. If Node is older than required, stop and
report `TOOLCHAIN_MISSING`. Use the package manager from the manifest — **never** mix
(`npm` in a repo with `pnpm-lock.yaml` rewrites the lockfile).

## Install

Run from the manifest's `root`, using an absolute path or a single `cd` in the same command.

- **CI / clean / lockfile present and you want it respected:** `npm ci` (`pnpm i --frozen-lockfile`,
  `yarn install --immutable`).
- **Local dev, or `npm ci` fails on a lockfile mismatch:** `npm install`. If you fall back, say so
  in the payload — a lockfile mismatch is a real finding, not a footnote.

Skip install only if `node_modules/` exists **and** is newer than the lockfile.

## Build, typecheck, lint

Read the `scripts` block and run what is actually there. Never invent a script name; if the one
you want is absent, say so rather than guessing at an equivalent.

| Goal | Script, in order of preference | Direct fallback |
|---|---|---|
| Build | `build` | `npx vite build` / `npx tsc -b` — only if no `build` script |
| Typecheck | `typecheck`, `tsc`, `check` | `npx tsc --noEmit` if a `tsconfig.json` exists |
| Lint | `lint` | none — report "no lint script" |

Note that many `build` scripts already chain the typecheck (`tsc -b && vite build`). If so, don't
run typecheck twice; say it was covered by the build.

Run each separately so you can attribute failures. Write long output to
`.claude/stack-ops/compile-node.log` and cite the path rather than pasting it.

Also run the advisory check and report it — do **not** run `npm audit fix`, which changes the
lockfile:

```
npm audit --omit=dev
```

## Reading the result

- **TypeScript errors** — `file(line,col): error TS####`. Report each with `file:line` and message.
- **Lint** — report error-level findings individually; collapse warnings by rule (`9 × no-unused-vars`).
- **Build tool errors** (Vite/webpack resolve failures) — report the unresolved specifier verbatim;
  these are usually a missing dependency, not broken code.
- **Vulnerabilities** — report counts by severity and whether they are runtime (`--omit=dev`) or
  dev-only. Dev-only high findings are not a build gate; say which kind you found.

## Return this payload

```markdown
## compile-node: <OK | FAIL | TOOLCHAIN_MISSING>

- **Root:** <path>  •  **Package manager:** <npm|pnpm|yarn>  •  **Node:** <version>
- **Install:** <ci | install (fallback — lockfile mismatch) | skipped (up to date)>
- **Build:** <script run> → <ok | failed>
- **Typecheck:** <script run | covered by build | not available> → <ok | failed>
- **Lint:** <script run | not available> → <ok | N errors, M warnings>
- **Audit:** <N runtime / M dev-only, by severity>
- **Output size:** <bundle sizes, if the build printed them>
- **Log:** <path, if written>

### Errors
- `<file>:<line>` — <message>

### Warnings
- <rule> × <count> — <one-line gist>

### Notes
<lockfile/toolchain anomalies, or "none">
```

Nothing else.

## A build or sweep that outlasts one Bash call — own it, don't hand it back

A full install, a monorepo build or a whole-repo test sweep can exceed the 10-minute cap on a single
Bash call. **That cap is per CALL, not per turn**, so own it rather than returning with the work pending:

```
bash ~/.claude/tools/job.sh start "pnpm build" "pnpm -r build"
  -> JOB=<id>
bash ~/.claude/tools/job.sh wait <id> 480     # status=running  — call it again
bash ~/.claude/tools/job.sh wait <id> 480     # status=done exit=0
```

⚠️ **Put the `wait` in a Bash call by ITSELF** — combining it with other commands blows the tool budget
and loses the poll.

**`status=vanished` is NOT success** — the pid is gone with no exit file, i.e. killed or the machine
restarted. Report it as a failure; killed and completed are different outcomes.
