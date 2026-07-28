---
description: One-time setup for a freshly-cloned project template — interview the developer about the project, then fill in CLAUDE.md and the docs/ baseline so future sessions start oriented. Run once, at the very start.
allowed-tools: Read, Glob, Grep, Edit, Write, Bash(git status:*), Bash(git log:*)
---

You are initializing a new project created from the Claude Code project template. The repo currently
carries placeholder scaffolds; your job is to **interview the developer** and then **fill those
scaffolds in** so that every future `/start-session` reads accurate, project-specific state.

Work in two phases: **interview first, write second.** Do not edit any file until you've gathered the
answers and played them back.

## 0. Confirm this is an uninitialized template

Read `CLAUDE.md`. If the 🌱 *uninitialized template* banner is already gone and the project sections
are filled in, this project has been initialized — stop, say so, and ask whether they really want to
re-run setup (which would overwrite project content). Otherwise continue.

## 1. Interview

Ask the developer about the project conversationally — a few focused questions at a time, not a wall
of them. Lead with the essentials (name + what it is), then go deeper. Cover, at minimum:

- **Name** — the project / product name (and a short namespace or repo slug if relevant).
- **What it is** — what you're building, for whom, and why it exists. The one-paragraph orientation a
  fresh context needs most.
- **Goals & success** — what done/working looks like; the near-term objective vs. the longer arc.
- **Tech stack & shape** — languages, frameworks, runtime, how the repo is structured; anything a
  fresh context should know before touching code.
- **Hard constraints** — cost, timeline, scale, compliance, or other first-class limits.
- **Off-limits / read-only areas** — vendored code, generated files, external systems, anything an
  agent must not modify.
- **External dependencies** — services, APIs, other repos, related systems this leans on.
- **How they want to work** — review/commit habits, environment quirks, anything that should shape
  day-to-day behavior. (Their user-level `CLAUDE.md` preferences already apply — capture only
  project-specific additions here.)
- **Kickoff decisions already made** — any approach/architecture calls already settled, with the why.
  These seed the decision log.

Use judgment — skip what doesn't apply, dig where answers are thin. If the developer points you at
existing material (a brief, a related repo, notes), read it and fold it in rather than re-asking.

## 2. Play back, then write

Summarize what you heard in a few lines and confirm before writing. Then populate:

- **`CLAUDE.md`** — fill in *What this project is* and *Facts worth knowing before you touch anything*;
  set the title; **remove the uninitialized-template banner.** Keep the operating-model sections
  (how-we-work, session commands, command discipline, doc hierarchy) intact.
- **`docs/2-project-status.md`** — replace the "uninitialized" block with a real "Where we are right
  now" (project kickoff state), and set "Active now" to the genuine first actions. Stamp today's date.
- **`docs/3-project-roadmap.md`** — fill in *Framing* and a first phase/workstream outline from the
  goals. Stamp the date.
- **`docs/4-decision-log.md`** — write the first dated entry (or entries) capturing the kickoff
  decisions and their rationale, in the file's append-only style.
- **`docs/5-deferred-items.md`** — add any consciously-punted items surfaced in the interview (only if
  real); otherwise leave the scaffold.
- **`docs/1-documentation-index.md`** — flip operating-set rows from 🌱 Scaffold to ✅ Verified as they
  fill in, stamp dates, and add rows for any project/reference docs the developer pointed at.
- **`.claude/settings.json`** — if the developer named off-limits/read-only areas, propose adding
  `deny` rules for those paths (confirm the absolute paths first). Add any safe project-specific
  `allow` entries they want.

## 3. Report

Summarize what you filled in and flag anything still thin (a section you couldn't complete from the
interview). Suggest the developer run `/start-session` next session to confirm the orientation reads
cleanly. Don't commit unless asked.

> Use today's date for all stamps. Preserve each document's established voice — these are read cold by
> future contexts, so consistency matters.
