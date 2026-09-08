---
name: work-ledger
description: The single source of truth for work-item state in a project — a JSON ledger, a validator whose every check maps to an observed failure, and the rule that prose may cite an item but never assert its status. Load when tracking, briefing, or reconciling what is left to build.
---

# The work ledger

**State lives in exactly one place. Prose cites an item; it never states the item's status.**

That single rule is the whole design. Everything below is machinery to make it hold.

## Why this exists, and why a stronger reminder is not the answer

A documentation set that tracks work in prose has no state — it has **position within prose.** An item's
status becomes *which heading it currently sits under*, so a status change is a hand-edit in several places
with nothing detecting a miss, no way to diff it, and nothing that can be wrong in a checkable sense.

⭐ **Audited on one real project, that structure produced these — and the numbers are the argument:**

- **Duplication was the normal case, not the tail.** Across 88 sampled item ids: **median 4 documents
  asserting the same item's state**, worst case **10**, only ten items single-homed.
- **30 substantive contradictions**, of which **26 claimed work was *less* complete than it was.** One
  phase plan marked **31 already-merged increments** as `ready`/`planned`. The status document contradicted
  **itself** three times. One item was filed simultaneously as *"next priority"* and under a heading
  reading *"waiting on other people — nothing here is work we can do."*
- **12 mutually-incompatible state vocabularies**, 624 checkboxes and ~2,861 emoji state markers — and
  **zero machine-readable state fields anywhere.**
- **An item fully designed, correctly filed, and never briefed**, because its state lived in one document
  and the briefing read another. It was reported to the developer as missing entirely.
- **A real deployment blocker buried for 18 days** among configuration edits, because the queue drew no
  distinction between code and config.
- **A dissolved blocker that outlived three separate corrections**, because it lived in four places and
  each correction fixed the sentence in front of it.
- The status document had grown to **2,326 lines, 36% of which preceded the first actionable line**, and
  roughly half was archive. A **125-line** derived list said more about remaining work than **~11,600
  lines** across the eight tracking surfaces — a ~93× compression.

🔴 **The response to each failure had been to write a stronger instruction.** Audited across one
configuration tree: **31 pure-discipline instructions, 14 of which cite the very incident that had already
defeated them** — including a briefing section whose own comment records that the failure it prevents had
by then occurred three times. **That approach has a measured 0-for-3 record on the case it was written
for.**

⭐ **A reminder cannot fix a structure in which being wrong is not a detectable condition.** The ledger
exists to make drift *computable*, so the finding arrives whether or not anyone remembered to look.

## The pattern is not new — it is `local-env.json` applied to work

Where a project already carries a `local-env.json` (see the `local-env` skill), it has typed per-surface
fields, a `dependsOn` graph, a `declaredIn` provenance pointer, a prose twin, and a real drift comparison.
**All of that already exists for ports.** The ledger is the same pattern pointed at the thing that actually
keeps failing. Adopting it is a generalisation, not an import.

---

## 1. The file

`docs/backlog.json`. **JSON, not YAML** — a validator must run with zero installs on any machine, and
PowerShell 7 parses JSON natively while YAML needs a module.

```json
{
  "schema": 1,
  "project": "<short project name>",
  "updated": "<ISO date>",
  "ignoredNamespaces": ["WO"],
  "retired": ["MGMT-1", "MGMT-2", "SESS-8"],
  "items": [ ... ]
}
```

### 🔴 `retired` and `ignoredNamespaces` are what stop the orphan check dying in its first week

Rule 4 says landed items are **removed** from the ledger. That is right — but it means every citation of
closed work in a live document becomes a permanent orphan finding. Measured on the first real ledger: **30
orphan findings, and only 4 came from history documents.** The other 26 were the live status doc, the
index and the phase plan legitimately referring to work that had shipped.

⚠️ **Do not "fix" this by scoping the scan to fewer documents** — that hypothesis was tested and was wrong;
the noise is in exactly the files you most need scanned.

- **`retired`** — ids and legacy aliases of work that was tracked and is now closed. A citation matching one
  is **not** an orphan. ⭐ **When a session removes a landed item, it appends that item's `id` and
  `aliases` here.** That is the whole cost of keeping the check precise, and it makes removal lossless.
- **`ignoredNamespaces`** — prefixes that are *never* ledger items. Work-order numbers are the canonical
  case: a work order is an artifact, not a unit of work, so `WO-27` must never be expected in the ledger.

**An orphan finding should mean "a citation nobody can resolve."** Once it means anything else, the check
gets switched off, and every check that follows it inherits that distrust.

### An item

```json
{
  "id": "IMG-DELETE",
  "title": "Image delete, with the environment-prefix guard",
  "kind": "code",
  "state": "open",
  "repo": "<repo short name>",
  "size": "day",
  "severity": "data-loss",
  "dependsOn": [],
  "waitingOn": null,
  "paths": ["src/web/src/api.ts", "src/Api/Program.cs"],
  "aliases": ["P11", "STATUS item 6", "object storage for uploaded rasters"],
  "decidedIn": "docs/4-decision-log.md#2026-08-06",
  "detail": "docs/9-remaining-build-work.md#6",
  "jira": "PROJ-1028",
  "opened": "2026-09-08"
}
```

| Field | Required | Meaning |
|---|---|---|
| `id` | ✅ | Stable, unique, uppercase-kebab. **Never reuse, never renumber, never positional.** |
| `title` | ✅ | One line. What a person would call it. |
| `kind` | ✅ | `code` · `config` · `infra` · `decision` · `doc` · `qa` |
| `state` | ✅ | `open` · `in-progress` · `landed` · `dropped` |
| `repo` | ✅ | Which repository. Multi-repo work gets **one item per repo**, linked by `dependsOn`. |
| `size` | ✅ | `one-line` · `hour` · `half-day` · `day` · `phase` · `unknown` |
| `severity` | ✅ | `data-loss` · `security` · `correctness` · `ux` · `debt` · `none` |
| `priority` | — | Integer, 1 = highest. **Explicit human ordering.** Omit or `null` when unranked. |
| `dependsOn` | ✅ | Ledger ids only. **Machine-checkable.** `[]` when none. |
| `waitingOn` | ✅ | `null`, or `{"who": "...", "what": "...", "since": "<ISO date>"}`. **A human or external gate. Never checkable.** |
| `paths` | ✅ | Files the work will touch. **Drives the drift check.** `[]` if genuinely unknowable. |
| `aliases` | ✅ | Every legacy identifier and prose name this item has been called. `[]` if none. |
| `decidedIn` | — | Where it was decided. Presence means *decided*; absence means *not yet agreed*. |
| `detail` | ✅ | Pointer to the prose that explains it. **Prose holds detail; the ledger holds state.** |
| `jira` | — | Outward ticket key. |
| `opened` | ✅ | ISO date. The baseline the drift check measures from. |

### ⚠️ `id` must never be positional, and `aliases` is not optional bookkeeping

Both fields are here because of the same measured failure. In the audited project, the status document
numbered its items **by position** — and those numbers were renumbered in place while being cited *by
number* from three other documents, leaving at least three citations silently pointing at the wrong item.
Meanwhile eight separate id spaces had grown up with no cross-walk: they never collided by *symbol*, but
they collided by *referent*, one piece of work carrying **five different identifiers**.

So: **an id is a name, never an ordinal**, and **`aliases` is what lets a validator tell a stale citation
from a legitimate old name.** Without it the orphan-citation check drowns in false positives on its first
run and gets switched off, which is how these things die.

### 🔴 `severity` is not priority, and without `priority` the biggest work sinks

This field exists because its absence was caught on the first real ledger, and the failure was the one
this whole structure is meant to prevent.

`severity` describes **how bad it is if this is wrong** — a leak, a breach, a broken screen. Feature work
with no defect behind it is honestly `severity: none`. But sorting by severity then means **a project's
single largest and most-committed effort sorts to the bottom of the file**, because building something new
is not a defect. On the first ledger that was ten items of the next planned feature, ranked below every
piece of debt.

Worse, an explicit human instruction — *"do this one first, then that one"* — had **nowhere to live at
all**. A structure that cannot record the developer's own stated ordering is not a tracking system.

So: **`priority` is the only field a human sets by fiat**, it needs no justification, and it overrides
every computed order. Leave it `null` for everything you have not deliberately ranked; a ledger where
every item has a priority is a ledger where priority means nothing.

⚠️ **Never derive `priority` from `severity`, `size`, or position.** If it was not stated, it is `null`.

### ⚠️ One alias MAY be claimed by several items — do not add a check for it

An alias shared across items is an **umbrella**, and umbrellas are legitimate. On the first real ledger a
single phase id was an alias on **ten** items, and a legacy id was an alias on two after one piece of work
was correctly split by repo. Both are honest: that is simply what happens when an old coarse name meets a
finer decomposition.

🔴 **A "duplicate alias" check was proposed and rejected.** It cannot distinguish the umbrella from the
ambiguity — they are structurally identical — so it would fire on correct data. The consequence to accept
instead: **a citation of an umbrella alias resolves to a set, not to one item.** That is fine for the
orphan check, which only asks whether a citation resolves *at all*.

### ⚠️ `dependsOn` and `waitingOn` are different fields on purpose

This is the fix for `blocked` meaning three unrelated things — waiting on a person, an increment that
cannot start, and a tool run that failed:

- **`dependsOn`** — this item cannot start until another *ledger item* lands. Fully checkable, and a
  dependency on something already landed is a **defect the validator reports**.
- **`waitingOn`** — a person, a decision, another team's review. **Nothing can verify it**, so it is never
  inferred and never auto-cleared; a human clears it. Naming it separately is what stops an unverifiable
  gate from masquerading as a tracked dependency.
- **A tool run that failed is not work state at all.** It belongs in an agent's report. Keep it out.

🔴 **Never infer `waitingOn` from where an item sits in a document.** The audited status file contained a
heading literally titled *"Commonly mistaken for blocked, and not"* — section membership was wrong for one
item and right for the next, with only prose separating them. Position is not data.

### Rules that keep it honest

1. 🔴 **No other file may assert an item's state.** Prose cites `IMG-DELETE` and describes it; it does not
   say whether it is done. A checkbox, a `status:` line, or a ✅ beside an id is a validator failure.
2. **Never key state on emoji.** In a documentation set of any maturity `⚠️ 🔴 ✅` are rhetorical emphasis
   on nearly every line — one audit counted ~2,861 of them. Anything reading them as state reads prose as
   data.
3. ⭐ **The controller owns the ledger; implementation agents never write it.** Same reason agents never
   touch git — concurrent worktrees would each edit one file and conflict on every phase.
4. **Keep it readable in full every session.** Open items only. Landed items are **removed**, not marked —
   the decision log and the commit trail are the history, and they are append-only and already work. A
   ledger you cannot read in one pass is the failure it replaced.
5. **One item per repo.** Cross-repo work links with `dependsOn` rather than hiding two efforts in one row.

---

## 2. The validator

`~/.claude/tools/work-ledger.ps1`. **Every check exists because of an observed failure** — a check that
maps to no real incident is speculative and belongs out.

| Check | Catches | Built from |
|---|---|---|
| Schema and enum validity | typos, missing fields | — |
| `dependsOn` resolves, no cycles | dangling and circular refs | — |
| **Phantom blocker** — `dependsOn` names a `landed`/`dropped` item | a dissolved blocker still gating work | the blocker that outlived three corrections |
| **Probably shipped** — `state: open` but every `paths` entry has commits since `opened` | documents that disagree with git | 31 merged increments marked `ready`/`planned` |
| **Orphan citation** — an id or alias cited in `docs/**` that no ledger item claims | renamed or dropped items still referenced | eight id spaces with no cross-walk |
| **Dangling detail** — `detail` points nowhere | an item nobody can act on | — |
| **Undecided in flight** — `state: in-progress` with no `decidedIn` | building before agreeing | — |
| **Decided but not built** — `decidedIn` set, `state: open` | the class that reached a deploy three times | the recurring "recorded is not tracked" failure |
| **State in prose** — a status assertion beside an id outside the ledger | the duplication returning | median 4 homes per item |
| **Stale `waitingOn`** — `since` older than 30 days | an unverifiable gate nobody revisited | the 18-day buried blocker |

**Exit codes:** `0` clean · `1` findings · `2` the ledger itself is unreadable. Findings print one per
line, machine-greppable, severity-first.

⚠️ **A check that cannot be computed must say so rather than pass.** An item with `paths: []` is
**not-checkable**, is reported as such, and is never counted as clean — absence of evidence is its own
outcome, never a pass. This is the same rule the stack-ops agents follow, and for the same reason.

### `paths` may name files the work will CREATE

A path that does not exist yet is **not an error** on an `open` item — plenty of work exists precisely to
create a file. The drift check reports such a path as *yet to be created*, which is consistent with `open`
and is real information.

⭐ **This is why the rule is "may not exist" rather than "must exist".** On the first real ledger, an item
whose entire job was to create one manifest had to declare `paths: []` to satisfy a must-exist rule — and
so reported **not-checkable forever**, which is strictly less informative than one path that is honestly
absent. The moment every path on an item is missing, the item is not-checkable *for a named reason*, and
that reason is different from having declared nothing.

### ⚠️ Two limits worth stating so nobody "fixes" them wrongly

- **A path inside a gitignored reference clone cannot be drift-checked.** Where a project vendors
  read-only clones of sibling repositories, `git log` in the outer repo knows nothing about them, and the
  clone is usually parked on its own default branch rather than the branch the work lives on. Items in
  that repo report **not-checkable**, correctly. The fix is not to point the paths somewhere checkable —
  that would trade an honest gap for a false pass.
- **The drift check measures commits, never the working tree.** Uncommitted work in progress is invisible
  to it, by design; a dirty tree is a different question and belongs in the session brief.

⭐ **Expect real findings on the first run in any project.** A first pass that reports nothing means the
checks are not wired up, not that the tree is clean.

---

## 3. Generated views — the queue is output, not prose

The human status document keeps its narration, which is genuinely useful, and **loses its queue.** The
queue is regenerated between markers:

```
<!-- BEGIN GENERATED: work-ledger -->
...
<!-- END GENERATED: work-ledger -->
```

Nothing inside is hand-edited. Editing the ledger and re-rendering is the only path, which is what makes a
stale queue structurally impossible rather than merely discouraged.

⭐ **`kind: code` renders first and alone by default.** Config, infra, doc and qa items render in their own
sections underneath. That partition is the fix for a genuine blocker drowning among configuration edits — a
queue that mixes them has no signal, and one audited queue tracked three config edits while omitting the
project's two largest remaining efforts.

**Order:** `severity` descending, then `size` ascending, so the cheap dangerous things surface first.

⚠️ **Narration and archive are not the queue's problem to carry.** Where a status document has accumulated
prior-session narration, move it to an archive file rather than letting it sit above the generated block.
One audit found 36% of the file preceding the first actionable line.

---

## 4. Where each skill plugs in

| Skill | What it does with the ledger |
|---|---|
| `start-session` | **Reads it and runs the validator.** The brief's queue and its findings section both come from output, not from reading prose. |
| `save-context` | **Writes item state, re-renders the views.** This retires the deferred-write-as-a-prose-sentence antipattern, in which a pending update was parked as a sentence inside the very document it was meant to update. |
| `end-session` | Reconciles, **removes landed items**, appends to the decision log, re-runs the validator. |
| `phase-loop` | Increments **cite ledger ids**. Its own `planned\|ready\|running\|blocked\|done` enum is retired in favour of `state` — that enum was declared "parsed" and **nothing ever parsed it.** |
| `work-order` | A work order **cites ledger ids** and carries no status of its own. Whether it is done is a ledger fact, not something inferred from whether a `## Report` section exists. |

## 5. Adopting it in a project

1. Write `docs/backlog.json` with **open items only**, populating `aliases` from every legacy id space.
2. Strip every status assertion from prose, leaving id citations.
3. Insert the generated markers into the status document; move prior-session narration to an archive.
4. Run the validator and fix what it finds.
5. Record the adoption in the decision log, and note in the project's `CLAUDE.md` that the ledger is
   authoritative for state.

⚠️ **A project with no `docs/backlog.json` is not broken.** Every skill degrades to its prose behaviour, so
this is adopted per project and never assumed.
