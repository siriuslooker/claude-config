---
description: Orient a fresh context — read the project's status docs and git state, then brief where we are and what's next. Run this first.
allowed-tools: Read, Glob, Grep, Bash(git status:*), Bash(git log:*), Bash(git diff:*), Bash(pwsh:*)
---

You are starting a fresh working session on this project. Your job right now
is **orientation only** — get up to speed and brief the user. Do **not** start implementing
anything until they direct you.

> **If the project is still an uninitialized template** — `CLAUDE.md` carries the 🌱 *uninitialized
> template* banner and STATUS says "Uninitialized" — don't produce a full brief. Tell the user the
> project hasn't been set up yet and recommend running **`/init-project`** first. Then stop.

## Read, in this order

1. `CLAUDE.md` (project root) — operating model and key facts. Note whether it names a work ledger.
2. `docs/1-documentation-index.md` — the documentation map. Note especially the "Start here" section and any
   docs marked ⚠️ Suspect or 🔴 Obsolete so you don't rely on stale material.
3. `docs/2-project-status.md` — the living current-state. Read it fully.
4. `docs/4-decision-log.md` — read the **last two dated sections** (most recent decisions) so you
   know what changed most recently. Don't re-read the whole file.
5. `docs/5-deferred-items.md` — ⚠️ **not to list what is deferred, but to check whether any entry's
   stated revisit TRIGGER HAS ALREADY FIRED.** That file's own rule is that a fired trigger moves the item
   onto the working surface. A fired trigger nobody noticed is indistinguishable from a decision nobody
   made. **No tool can evaluate a trigger written in prose — this one is yours to read.**
6. Git state — run `git status` and `git log --oneline -10` to see uncommitted work and the
   recent commit trail. If there's uncommitted work, look at `git diff --stat` to understand it.
   (If the project isn't a git repo yet, note that and move on.)

## The work ledger — run the validator

Look for the project's ledger: `docs/backlog.json`, unless the project's `CLAUDE.md` names another
path. Then run it (see the `work-ledger` skill for the contract):

```
pwsh -NoProfile -File "$HOME/.claude/tools/work-ledger.ps1" -Validate -Ledger <ledger path>
```

- **Exit 0** — clean. Say so.
- **Exit 1** — findings, one per line, severity first. These are briefing material, not noise.
- **Exit 2** — the ledger itself is unreadable. **Say that plainly and fall back to reading STATUS as
  prose.** Do not guess at its contents.

Read the ledger's own `items` for the queue, and read the generated block in STATUS
(`<!-- BEGIN GENERATED: work-ledger -->`) for the rendered view. Items marked **not-checkable** are their
own outcome — report them as such, never as clean.

> ⚠️ **No ledger file? Skip this whole section.** Read the queue out of STATUS as prose, exactly as this
> command has always done. Most projects have no ledger; that is not a defect and nothing below depends
> on one.

## Then brief the user

Produce a concise briefing with these parts:

1. **Where we are** — one short paragraph from STATUS + recent decisions.
2. **The single next action** — the one thing to do first: the top item of the ledger's `kind: code`
   queue (severity descending, then size ascending), or STATUS "Active now" where there is no ledger.
3. **The queue** — open work, `kind: code` first and separately from config/infra/doc/qa. Plus anything
   `waitingOn` a person, named with who and since when.
4. **Ledger findings** — the validator's output, grouped by severity, one line each. Lead with anything
   that would bite at deploy time; that is where this class of item does its damage, because it surfaces
   under time pressure and looks like a new problem.
   - **Exit 0: say "clean" explicitly.** Silence here reads as "nothing outstanding".
   - **No ledger:** say so, and instead list what STATUS records as decided-but-not-implemented, one line
     each with its `file:line`.
5. **Deferred triggers that have fired** — from step 5 above, or "none".
6. **Working-tree state** — uncommitted changes or anything that looks mid-flight; flag discrepancies
   between the docs and reality explicitly.
7. **Flags** — any open decisions awaiting the developer, and any doc gaps STATUS calls out.

Keep it tight and scannable. End by asking what they want to work on — then stop and wait.
