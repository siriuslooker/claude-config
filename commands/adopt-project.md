---
description: One-time retrofit for an EXISTING project — mine the repo's own history and docs, interview only the gaps, then create the docs/ operating set and patch CLAUDE.md so /start-session, /save-context and /end-session work. Use instead of /init-project when the project already has code and history.
allowed-tools: Read, Glob, Grep, Edit, Write, Bash(git status:*), Bash(git log:*), Bash(git diff:*), Bash(git show:*), Bash(ls:*)
---

You are retrofitting an **existing** project — one with real code, real history, and probably its own
ad-hoc notes — so that the session commands (`/start-session`, `/save-context`, `/end-session`) work on
it. Those commands read and write a specific five-document operating set under `docs/`. Right now this
project doesn't have it, or has only part of it.

**This is not `/init-project`.** That command interviews a developer about a project that doesn't exist
yet and fills in pristine scaffolds. Here, most of the answers are already written down somewhere in the
repo — in `CLAUDE.md`, a `HANDOFF.md`, a `PLAN.md`, `prompts/`, a `.claude/TODO.md`, the commit trail.
**Your primary job is archaeology, not interviewing.** Mine first; ask only what the repo can't tell you.

Work in four phases: **survey → mine → interview the gaps → write.** Do not create or edit any file
until you've played back what you found.

## 0. Survey — what's already here

- `ls docs/` (or Glob `docs/**`) and check for each of the five operating docs by name:
  `1-documentation-index.md`, `2-project-status.md`, `3-project-roadmap.md`, `4-decision-log.md`,
  `5-deferred-items.md`.
- Read `CLAUDE.md` if it exists. Note whether it carries the **How we work / Session commands /
  document hierarchy** sections — if not, they need adding in phase 4.
- `git status` and `git log --oneline -30`.

Then branch:

- **No `CLAUDE.md` and no code** — this isn't an existing project. Recommend `/init-project` and stop.
- **`CLAUDE.md` carries the 🌱 *uninitialized template* banner** — it's a fresh template, not an
  existing project. Recommend `/init-project` and stop.
- **All five docs already exist and have real content** — the project is already adopted. Say so, offer
  a **gap audit** instead (phase 5 only: check each doc for staleness against git reality and report
  what drifted), and stop unless the developer asks for more.
- **Some docs exist** — adopt only the missing ones. **Never overwrite an existing doc with a
  scaffold.** If a doc exists but is thin, propose additions to it rather than replacing it.
- ⚠️ **A numbering collision** — the project already has `docs/1-*.md` etc. meaning something else.
  Stop and ask before touching them; the numbers are load-bearing for the session commands, so the
  resolution is either renaming the incumbents or (rarely) accepting different filenames and noting the
  deviation prominently in `CLAUDE.md`. Do not silently clobber.

## 1. Mine the repo

Read what's actually there. Cast a wide net, but read purposefully — you are looking for content that
*belongs* in one of the five docs and is currently homeless.

- **`CLAUDE.md`** — on a mature project this is usually the biggest find. It has very often accreted
  current-state narrative, phase-completion notes, and locked decisions that properly belong in STATUS
  and the decision log. Catalogue those passages; phase 4 relocates them.
- **Ad-hoc status/handoff docs** — `HANDOFF.md`, `STATUS.md`, `NOTES.md`, `TODO.md`, `.claude/TODO.md`,
  `docs/*plan*.md`, `prompts/`, `README.md`. These are your STATUS and roadmap raw material.
- **Git history** — `git log --oneline -50` for the work arc; read a few substantial commit messages in
  full (`git show --stat --no-patch <sha>`) where the subject suggests a decision was made. Merge
  commits and tags mark phase boundaries.
- **Auto-memory** — if `~/.claude/projects/<slug>/memory/MEMORY.md` exists for this project, read it.
  Memories written earlier may name files or flags that have since changed; **verify before repeating a
  memory as current fact.**
- **Uncommitted work** — `git status` plus `git diff --stat`. Anything mid-flight is an "Active now"
  candidate.

Assemble, internally: the current state, the phase arc with what's done, the dated decisions you can
evidence, the open threads, and anything consciously punted. **Note which claims you can evidence and
which you're inferring** — the difference matters in phase 3.

## 2. Interview only the gaps

Play back a short summary of what you mined, then ask about what the repo genuinely cannot tell you —
a few focused questions at a time, numbered so they can be answered by number. Typical real gaps:

1. **What's actually next** — the commit trail shows what's done, never what's next.
2. **Why**, for decisions visible only as their outcome in code.
3. **Blocked vs. abandoned** — indistinguishable from the outside.
4. **Off-limits / read-only areas** — vendored trees, generated files, external systems.
5. **Deferrals and their triggers** — a punt is invisible in a repo unless someone wrote it down.
6. **Phase/roadmap framing** — whether your inferred arc matches how they think about it.

Don't re-ask anything you found. Nothing is more annoying in a retrofit than being interviewed about
facts already written in the repo.

## 3. Play back, then write

Confirm your reconstruction before writing — especially the phase arc and anything inferred. Then create
each missing doc, in the established house format:

- **`docs/2-project-status.md`** — title `# Project Status`, then the preamble explaining it is the
  living now-state (read first, update last; maintained in place, not rewritten), a pointer to the
  roadmap and decision log, its one-way relationship with `5-deferred-items.md`, and a **`Last
  updated:`** line stamped today. Sections: **Where we are right now** / **Active now (immediate next
  actions)** / **Up next** / **Blocked / waiting** / **Open decisions**. On a retrofit you may also add
  a **`Done <date> (record)`** section summarizing already-completed phases — that's what gives the
  first `/start-session` its history.
- **`docs/3-project-roadmap.md`** — `# Project Roadmap`, purpose line, `Last updated:`, then
  **Framing** / **Phases / Workstreams** (a table: Phase | Item | Status, with completed phases marked
  ✅ and dated from git) / **Critical path & sequencing** / **Top risks & open questions**.
- **`docs/4-decision-log.md`** — `# Decision Log`, preamble stating it is **append-only** (supersede
  with a new dated entry; never rewrite), and that each entry is a dated **bold lead sentence** stating
  the decision followed by its rationale and consequence. Then **backfill the decisions you could
  evidence, oldest first**, grouped under headings (Scope & Strategy, Architecture, Repo & Tooling…).
  This is the highest-value part of the retrofit and the part most likely to be wrong — write only what
  you can evidence, attribute inferred rationale explicitly (e.g. *"rationale reconstructed from the
  implementation; not stated at the time"*), and get the set confirmed before writing.
- **`docs/5-deferred-items.md`** — `# Deferred Items`, preamble distinguishing it from the roadmap, the
  one-way STATUS relationship, `Last updated:`, and the **entry format** block (Current state / Why
  deferred / Trigger to revisit / Likely shape). Then the real deferrals, grouped by category. If none
  surfaced, leave the scaffold with the format block and say so.
- **`docs/1-documentation-index.md`** — `# Documentation Index`, `Last updated:`, the **status-mark
  legend** (✅ Verified / ⚠️ Suspect / 🔴 Obsolete / 📚 Historical / 🌱 Scaffold), a **▶ Start here**
  list, an **Operating set** table for the five docs, a **Project documents** table, and an **External
  references** table. Write this one **last** — it catalogues the others. **Every pre-existing doc in
  `docs/` gets a row**, with a purpose line and an honest status: docs describing completed work are
  📚 Historical, docs that predate later decisions are ⚠️ Suspect. Getting these marks right is most of
  this file's value, since it is what stops a fresh context relying on stale material.

## 4. Patch `CLAUDE.md` — and relocate what belongs elsewhere

Two edits, and the second is a judgment call.

**a. Add the operating-model sections** (auto-apply). `CLAUDE.md` needs to point at the new docs, or a
fresh context won't find them. Add, in the project's own voice and without disturbing its existing
content:

- **How we work** — the INDEX is the map, STATUS is the working memory.
- **Session commands** — `/start-session`, `/save-context`, `/end-session` and what each does.
- **The document hierarchy** — a table: STATUS = *now*, roadmap = *strategic*, deferred = *someday*,
  decision log = *permanent/append-only*, with the INDEX above them as the catalogue.

**b. Relocate the homeless current-state content** (confirm first). On a mature project `CLAUDE.md` has
usually become a de facto status doc — phase-completion narrative, "COMPLETE + verified" notes, locked
decisions with rationale. That content now has proper homes, and leaving it duplicated in `CLAUDE.md`
guarantees the two drift.

Propose a specific migration — *this passage moves to STATUS's "Where we are"; these locked decisions
become dated decision-log entries; this stays* — and apply it only on approval. **Guidance for the
split:** `CLAUDE.md` should keep what is **stable orientation** (what the project is, architecture,
layout, conventions, hard rules, environment facts). Anything that will be **false in a month** —
progress, phase status, what's next — belongs in STATUS. Do not delete anything until its replacement is
written, and never lose the *why* behind a decision in the move.

Also propose `.claude/settings.json` `deny` rules for any off-limits paths the developer named
(confirm the absolute paths first).

## 5. Verify the retrofit

Prove the thing you just built actually works, rather than assuming it:

- Walk `/start-session`'s read path yourself — `CLAUDE.md` → INDEX → STATUS → the last two decision-log
  sections → git state — and confirm each read lands on real content and that STATUS's "Active now"
  yields an unambiguous single next action.
- Confirm STATUS does not contradict the working tree (uncommitted work represented, no completed work
  still listed as active).
- Confirm nothing is now tracked in **both** STATUS and `5-deferred-items.md`.
- Confirm no pre-existing doc was overwritten, and that every doc in `docs/` has an INDEX row.

## 6. Report

Summarize: docs created, `CLAUDE.md` sections added, content relocated (and from where), and decisions
backfilled with how many are evidenced vs. reconstructed. Then flag, explicitly:

- Anything still thin — a section you could not fill from repo or interview.
- Anything **inferred** that the developer should sanity-check, especially backfilled decision rationale.
- Any pre-existing doc you marked ⚠️ Suspect or 🔴 Obsolete, since that's a claim about their work.

Suggest they run `/start-session` in a fresh context next to confirm the orientation reads cleanly, and
`/end-session` at the close of that one to exercise the write half. Don't commit unless asked.

> Use today's date for all stamps. **Match the project's own voice, not the template's** — these docs
> are read cold by future contexts of a project that already has a house style, and consistency with it
> matters more than your phrasing. Preserve the established format of each document.
