---
name: authoring-stack-ops-skills
description: Write a new per-stack skill for the stack-ops agents when a repository uses a stack they don't yet handle (Python, Go, Rust, .NET Framework, Java, Ruby…). Use BEFORE running the build/compile/test/qa/deploy/verify agents on such a repo — they must not substitute another stack's skill. Also use when stack-detect reports anything under "Unhandled".
---

# Authoring a stack-ops per-stack skill

The `stack-ops` agents (`build`, `compile`, `test`, `qa`, `deploy`, `verify`) are deliberately
**stack-agnostic**. They decide *what* to do; a per-stack skill knows *how*. Today only two stacks are
implemented — `netcore` and `node` — so the first time a repo uses anything else, the skill has to be
written before an agent can do useful work.

**The failure this prevents:** an agent meeting an unhandled stack either reports `INCOMPLETE` (correct
but useless) or improvises with the nearest skill it has, which produces confident nonsense —
`dotnet build` against an old-style `.csproj` fails in ways that look like source errors. `stack-detect`
is explicit: *"Do not substitute a different stack's skill. Adding a stack means adding a skill."*
This skill is how you add it.

## When this triggers

- `stack-detect` returns anything under **`### Unhandled`**.
- You are about to run any stack-ops agent on a repo whose primary language has no `compile-*` skill.
- A stack that *is* handled acquires a second toolchain that behaves differently enough to need its own
  skill (e.g. a `node` repo that switches to Bun, or Deno).

Do this work **first**, as its own step. Do not start the real task and hope.

## Step 1 — decide the scope

One stack usually needs three skills: `compile-<stack>`, `test-<stack>`, `deploy-<stack>`. Write only
what the task needs — `test-python` alone is a perfectly good increment if you're only running tests —
but name it to the same pattern so the agents find it.

Skills live in the plugin repo, which is the source of truth:

```
<local-path>\skills\<verb>-<stack>\SKILL.md
```

Do **not** hand-write these into `~/.claude/skills/` — that forks the tooling. Extend the plugin by
adding skills, never by editing the agents (the agents are stack-agnostic on purpose; `netfx` is left
detected-but-unhandled as the worked example of this seam).

## Step 2 — learn the toolchain from the repo, not from memory

Read the actual project files before writing a single instruction. For a Python repo that means
`pyproject.toml` / `setup.cfg` / `requirements*.txt` / `tox.ini`, and whether there's a `uv.lock`,
`poetry.lock`, `Pipfile.lock`, or bare `pip`. **The lockfile decides the package manager** — the same
rule `stack-detect` already applies to npm/pnpm/yarn.

Never invent a command. If the repo has a `Makefile` or a `[tool.poe.tasks]` block, prefer the entry
points it already defines, exactly as `test-node` prefers an existing `test` script.

## Step 3 — write the skill, matching the house style

Read `skills/test-node/SKILL.md` and `skills/compile-netcore/SKILL.md` first and mirror their shape.
The non-negotiable parts:

**Frontmatter.** `name` matches the directory. `description` says what it does, names the runners it
covers, and ends with the dispatch cue: *"Use when the stack manifest reports a `<stack>` stack."*

**A one-line framing.** These skills are mechanical: *"You run X and report what happened. Never edit
tests or source to make them pass, and never report a pass you did not observe."*

**Absence gets its own named outcome — the single most important rule.** Absence is never smoothed into
a pass. Enumerate what you checked before claiming nothing exists:

| Situation | Outcome |
|---|---|
| No test runner configured at all | `NO_HARNESS` (list what you checked) |
| Runner present, zero tests collected | `NO_TESTS_DISCOVERED` — not a pass |
| Runner not installed / venv missing | `TOOLCHAIN_MISSING` — not a failure of the code |
| Import/collection error | `FAIL` with `stage: collection` — the tests never ran |
| Placeholder task that just exits non-zero | no harness, not a failing suite |

**Non-interactive is mandatory.** Anything that can watch, page, or prompt will hang the session. Name
the exact flags: `pytest` needs no watch flag but `pytest-watch` does; `cargo test` is fine; `go test
./...` is fine; interactive `poetry install` prompts on a missing venv. Set `CI=true`. Force
`--no-input` / `--non-interactive` where the tool offers it.

**A runner table** — one row per tool you support, with the exact command.

**Log path convention.** Long output to `.claude/stack-ops/<verb>-<stack>.log`, and cite the path in
the payload rather than pasting the output.

**A strict "Return this payload" template**, ending with `Nothing else.` Status enum first, then counts,
the exact command invoked, elapsed, log path, then failures with `file:line` and the assertion diff
trimmed to the meaningful lines. The agents parse these payloads; freeform prose breaks the contract.

**Say what you did not verify.** Every payload ends with the gaps.

## Step 4 — teach stack-detect about the stack

**This step is the one that gets forgotten, and skipping it makes the new skill unreachable.** Add a
row to the detection table in `skills/stack-detect/SKILL.md`:

| Glob | Then check | Stack id | Skills |
|---|---|---|---|
| `**/pyproject.toml`, `**/requirements*.txt` | not under `.venv/`, `site-packages/` | `python` | `compile-python`, `test-python`, `deploy-python` |

Also extend its exclusion list if the stack has a vendored/artifact directory the globs would otherwise
walk — for Python that's `.venv/`, `__pycache__/`, `*.egg-info/`, `site-packages/`; for Rust `target/`;
for Go `vendor/`.

If the stack has a build-order relationship with another (as `node` → `netcore` does, where the SPA
must build before the .NET app that embeds it), state it in the compile skill.

## Step 5 — register and verify

Skills and agents are **only loaded at startup**. After adding the files:

1. `claude plugin validate` in the plugin repo.
2. **Restart Claude Code.** The new skill will not resolve in the current session — this is the same
   reason the stack-ops plugin itself needed a restart when it was first installed.
3. Run `stack-ops:compile` (or `verify`) on the target repo and confirm the manifest now lists the
   stack under `### <stack id>` rather than `### Unhandled`.
4. Commit the plugin repo and push, so other machines get the skill:
   `git@bitbucket.org:<work-org>/claude-agents-plugin.git`.

Then, and only then, run the agent that needed it.

## Checklist

- [ ] Read the repo's real manifest/lock files; package manager derived from the lockfile
- [ ] Commands taken from the repo's own entry points where they exist, never invented
- [ ] `name` matches the directory; `description` ends with the "stack manifest reports" cue
- [ ] Every absence has its own named outcome; none can be reported as a pass
- [ ] Non-interactive flags specified for every runner
- [ ] Log path `.claude/stack-ops/<verb>-<stack>.log` cited, output not pasted
- [ ] `Return this payload` template, status enum, ends `Nothing else.`
- [ ] Payload ends with what was not verified
- [ ] `stack-detect` gained a detection row **and** any needed exclusions
- [ ] `claude plugin validate` clean, session restarted, manifest confirms the stack
- [ ] Plugin repo committed and pushed
