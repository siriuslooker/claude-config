---
name: work-order
description: The durable-brief convention — a numbered, tracked file that carries one unit of delegated work, its worktree boundary, its test baseline, and the agent's own report appended to the same file. Use when writing a brief for a subagent that is parallel, sequenced, or likely to be cited later; and use when you ARE that agent and must append your Report.
---

# Work orders: a brief that outlives the prompt that carried it

## Why this exists

⭐ **A brief passed as prompt text does its job and then ceases to exist.** It cannot be cited, re-read by
the next agent to touch that code, or audited without scrolling a transcript — and the reasoning that
justified a decision is exactly what someone needs six weeks later when the code looks wrong.

A work order is the same brief written as a **numbered, tracked file**. That single change buys three
things prompt text cannot:

- **It can be cited from source.** `/* CARDS, not horizontal rows (WO-12 §2) */` in a stylesheet points a
  future reader at the reasoning, not just the outcome.
- **It is the handoff between sequenced units.** A later work order can say *"read WO-2 and its `## Report`
  first — that work is already committed on this branch and you are extending it, not starting over."*
- **Intent and outcome live together.** The agent appends its report to the same file, so nobody has to
  correlate a brief with a result recorded somewhere else.

This is the same trade as `report-handoff`, one level up: that convention keeps *detail* out of the
caller's context; this one keeps *intent* out of a transcript that will be discarded.

---

## Where they live

`.claude/work-orders/WO-<n>-<short-slug>.md`, numbered sequentially and committed with the work.

⚠️ **Do not introduce work orders into a project that has no such directory.** Follow the project's own
convention. Where there is none, prompt briefs plus a phase journal already cover it, and a lone
work-order file nobody else writes is clutter rather than a pattern.

---

## Shape

```markdown
# Work Order 9 — <what and why, in one line>

**Ticket:** PROJ-123 · **Phase:** P8 · **Branch:** `PROJ-123-<short-slug>`
**Ledger:** `NUDGE-A11Y` (state lives there, not here)
**Worktree (your ONLY working directory):** <absolute path to the worktree>

**Read [`WO-2-...`](WO-2-...md) and its `## Report` first** — that work is already committed on this
branch and this order extends it. You are adding a commit, not starting over.

## Standing rules
1. Work only inside the worktree above. Never edit the main checkout.
2. No console narration. Your output is a `## Report` appended to this file.
3. Commit on the existing branch. No push, no PR, no merge, no main.
4. Do not edit `docs/` — and never edit the work ledger. Cite its ids; the controller sets state.
5. Gate with the <stack> stack only. Your baseline is <N>.

## The gap
<what is wrong or missing, with file:line citations — not a restatement of the task title>

## What to build
<acceptance criteria; the risk verbatim as a thing to check; explicit out-of-scope; stop conditions>

## Report
<the agent appends here>
```

### 🔴 A work order carries no status of its own

**Whether the work is done is a ledger fact.** The order records what was asked and what happened; it
never records where the work has got to. So it has no `status:` line, no checkbox, no ✅ beside its
title — and **the presence or absence of a `## Report` section is not a status signal either.** It used
to be the only way to tell, which meant an order whose agent stopped early read as unfinished work and an
order nobody had dispatched read the same, with nothing able to tell them apart.

Cite the ledger id in the header instead, and let the ledger answer the question. Where the project has
no ledger, the phase journal and the commit trail answer it — still not the order.

### The four parts that carry the weight

Everything else is scaffolding. These four are why the format works.

1. 🔴 **The worktree path, named as the ONLY working directory.** Running several agents against one repo
   is precisely when one edits the wrong tree, and prose in the order is what prevents it. Say it in the
   header *and* in the standing rules — this is the one duplication worth having.
2. 🔴 **An explicit test baseline, with its provenance.** *"Your baseline is 679, not 659 — WO-2 added 20
   tests on this branch. A drop below 679 is a finding, not a pass."*
   ⚠️ **A stale baseline is worse than no baseline**, because an agent that inherits one reports a real
   regression as a pass. If you cannot state it confidently, tell the agent to measure it first and record
   what it found.
3. ⭐ **Stop conditions, written as outcomes rather than failures.** *"If coalescing cannot be done without
   restructuring the drag handlers, stop and report — that is a finding."* This is what converts "an agent
   quietly patched a shared primitive" into "an agent surfaced a latent defect."
4. ⭐ **`## Report` appended to the same file**, not returned and lost.

### On the standing rules

They look like boilerplate and are not. Each one exists because its absence cost something:

- **No console narration** — an agent's progress chatter lands in the controller's context and stays there.
- **No push, no PR, no merge, no `main`** — the controller owns all git beyond the working commit. An agent
  that opens a PR has made a decision that was not its to make.
- **Do not edit `docs/`** — documentation is reconciled at the end, by whoever can see the whole phase. An
  agent editing docs mid-flight produces a doc describing one increment as if it were the state of things.
- **Never edit the ledger** — for the same reason agents never touch git. Several worktrees each editing
  one small file conflict on every phase, and state written from inside a worktree describes a tree
  nothing has merged yet.

---

## If you ARE the agent: writing the `## Report`

Append to the work order. Do not rewrite the sections above it — **the brief is a record of what was
asked, including anything it got wrong**, and correcting it in place destroys the evidence that it was
wrong. Say so in your report instead; that contradiction is often the most valuable thing you produce.

Cover, briefly:

- **What you changed**, by file, and what you deliberately did not. Cite the ledger id the order names —
  but **do not assert its state**; say what you did and let the controller set it.
- **Numbers from your own run** — before/after test counts, compile and lint state. ⚠️ **Never restate a
  count you were given without re-running it.**
- **Every decision you took without asking**, with its reasoning — and decisions **considered and
  rejected**, which is what stops the same question being re-litigated.
- **What you could NOT prove**, named explicitly. ⭐ Silence reads as coverage. If jsdom cannot judge it,
  if no suite exercises it, if you reasoned it rather than observing it — say which, because that list
  becomes someone's re-check list.
- **Anything the order asserted that turned out to be false.** This is the highest-value line you can
  write. A brief is a hypothesis about code it was not written against.

⚠️ **If a stop condition fired, the report is the deliverable and stopping was success.** Say what you
found and what it blocks. Do not improvise past it to have something to show.

---

## When NOT to write one

A work order costs a file and a review. For a small, self-contained, one-off change, prompt text is fine
and a work order is ceremony.

Write one when the work is:

- **Parallel** — the worktree boundary needs a home that both agents' briefs can point at.
- **Sequenced** — a later unit must read an earlier one's `## Report`.
- **Likely to be cited later** — which is most things that change behaviour a comment will need to justify.

**When in doubt, prefer writing one.** An unnecessary work order costs a few minutes; an undocumented
decision costs the next person a re-derivation, and this is the class of thing that is never written up
retroactively.
