---
description: Orient a fresh context — read the project's status docs and git state, then brief where we are and what's next. Run this first.
allowed-tools: Read, Glob, Grep, Bash(git status:*), Bash(git log:*), Bash(git diff:*)
---

You are starting a fresh working session on this project. Your job right now
is **orientation only** — get up to speed and brief the user. Do **not** start implementing
anything until they direct you.

> **If the project is still an uninitialized template** — `CLAUDE.md` carries the 🌱 *uninitialized
> template* banner and STATUS says "Uninitialized" — don't produce a full brief. Tell the user the
> project hasn't been set up yet and recommend running **`/init-project`** first. Then stop.

## Read, in this order

1. `CLAUDE.md` (project root) — operating model and key facts.
2. `docs/1-documentation-index.md` — the documentation map. Note especially the "Start here" section and any
   docs marked ⚠️ Suspect or 🔴 Obsolete so you don't rely on stale material.
3. `docs/2-project-status.md` — the living current-state. Read it fully.
4. `docs/4-decision-log.md` — read the **last two dated sections** (most recent decisions) so you
   know what changed most recently. Don't re-read the whole file.
5. Git state — run `git status` and `git log --oneline -10` to see uncommitted work and the
   recent commit trail. If there's uncommitted work, look at `git diff --stat` to understand it.
   (If the project isn't a git repo yet, note that and move on.)

If anything in STATUS references a doc you need detail on, open that specific doc — but don't
read the whole `docs/` tree speculatively. The INDEX tells you what's worth opening.

## Then brief the user

Produce a concise briefing with these parts:

1. **Where we are** — one short paragraph from STATUS + recent decisions.
2. **The single next action** — the one thing to do first, drawn from STATUS "Active now".
3. **Active / Up next / Blocked** — the near-term lists from STATUS, tightened to what matters.
4. **Working-tree state** — uncommitted changes or anything that looks mid-flight or drifted
   from what STATUS claims; flag discrepancies between STATUS and reality explicitly.
5. **Flags** — any open decisions awaiting the developer, and any doc gaps STATUS calls out.

Keep it tight and scannable. End by asking what they want to work on — then stop and wait.
