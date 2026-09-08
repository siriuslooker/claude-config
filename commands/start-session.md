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
5. `docs/5-deferred-items.md` — ⚠️ **not to list what is deferred, but to check whether any entry's
   stated revisit TRIGGER HAS ALREADY FIRED.** That file's own rule is that a fired trigger moves the item
   onto the working surface. A fired trigger nobody noticed is indistinguishable from a decision nobody
   made.
6. Git state — run `git status` and `git log --oneline -10` to see uncommitted work and the
   recent commit trail. If there's uncommitted work, look at `git diff --stat` to understand it.
   (If the project isn't a git repo yet, note that and move on.)

### 🔴 Read STATUS for OUTSTANDING WORK, not just for its queue

**The queue sits near the top of STATUS. Actionable work that drifted below it is invisible by default —
and being *recorded* is what makes it look handled.**

**So scan the whole file for work that is decided, promised or known-needed but is NOT in "Active now" or
"Up next".** The phrasings that mark it: *"decided … implementation outstanding"*, *"still unmade"*,
*"not yet built"*, *"do it before X"*, *"owed"*, and any **unchecked `- [ ]` box** outside the queue.

⚠️ **Check the code, not just the doc.** A recorded decision is not shipped code, and docs in a long-lived
project drift in both directions — some claim work is outstanding when it landed, some read as settled
when only the *decision* was.

⭐ **Measured failure this exists to stop:** an item reading *"decided, implementation outstanding"* sat
~1200 lines below the queue for two and a half weeks, never appeared in a briefing, and then complicated a
deployment. The developer's words were *"all this time when I asked what's next, you have never shown that
to me — otherwise I would have bumped it up."* **It was the third instance of the same failure in one
project.** Recording an item is not tracking it.

If anything in STATUS references a doc you need detail on, open that specific doc — but don't
read the whole `docs/` tree speculatively. The INDEX tells you what's worth opening.

## Then brief the user

Produce a concise briefing with these parts:

1. **Where we are** — one short paragraph from STATUS + recent decisions.
2. **The single next action** — the one thing to do first, drawn from STATUS "Active now".
3. **Active / Up next / Blocked** — the near-term lists from STATUS, tightened to what matters.
4. 🔴 **Decided but not built** — **this section is mandatory and must not be skipped or folded into
   another.** Every item found by the scan above: recorded decisions with no implementation, unchecked
   boxes outside the queue, and deferred entries whose trigger has fired. **One line each, with its
   `file:line` and whether it affects a deployment or a release.**
   - **If there are none, say "none" explicitly.** Silence here reads as "nothing outstanding", which is
     the exact failure this section exists to prevent.
   - ⭐ **Lead with anything that would bite at deploy time.** That is where this class of item does its
     damage, because it surfaces under time pressure and looks like a new problem.
5. **Working-tree state** — uncommitted changes or anything that looks mid-flight or drifted
   from what STATUS claims; flag discrepancies between STATUS and reality explicitly.
6. **Flags** — any open decisions awaiting the developer, and any doc gaps STATUS calls out.

Keep it tight and scannable. End by asking what they want to work on — then stop and wait.

⚠️ **The developer can only prioritise what you put in front of them.** An item you read, understood and
left out of the brief is, from their side, an item you hid. Section 4 is not a completeness ritual — it is
the one place a buried commitment gets a chance to be bumped up.
