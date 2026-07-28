---
description: Full session close-out — reconcile STATUS, append decisions, record deferrals, and stamp the doc index so the next /start-session is accurate. For quick mid-session saves use /save-context instead. Run at the genuine end of a session or when low on context.
allowed-tools: Read, Glob, Grep, Edit, Write, Bash(git status:*), Bash(git log:*), Bash(git diff:*)
---

You are closing out a working session on this project.
Your job is to bring the project docs into agreement with what actually happened this session,
so the next fresh context (`/start-session`) reads accurate state. This is the write half of the
loop that keeps the docs canonical.

> This is the **full** close-out. For a quick mid-session save that only freshens STATUS — the
> kind of backup-save you do when stepping away without clearing context — use **`/save-context`**
> instead. Reserve `/end-session` for the genuine end of a session (or when low on context): it
> also touches the decision log, roadmap, and deferred-items, which `/save-context` deliberately
> leaves alone.

## 1. Reconstruct what happened

- Run `git status`, `git log --oneline` (since the session start if you can tell, else last few),
  and `git diff --stat` to see what changed on disk.
- Review this conversation for: decisions made, work completed, things tried and abandoned, new
  problems discovered, and anything deferred.
- Write yourself a short internal summary before touching any file.

## 2. Determine the updates needed across these docs

- **`docs/2-project-status.md`** — the main one. Update "Where we are"; check off completed "Active now"
  items; add newly-discovered actions; move things between Active / Up next / Blocked; update
  open decisions. Keep it current, not append-only — stale items should be removed or resolved.
- **`docs/4-decision-log.md`** — append (never rewrite) any architectural or implementation
  decision made this session, in the established style: a dated, bold lead sentence followed by
  rationale. Match the existing voice exactly.
- **`docs/5-deferred-items.md`** — add any consciously-punted item, in the file's structure
  (Current state / Risk / Trigger to revisit / Likely shape).
- **`docs/3-project-roadmap.md`** — update only if a phase materially moved (started, completed,
  re-scoped). Bump its "Last updated" line when you do.
- **`docs/1-documentation-index.md`** — for any doc created or meaningfully revised this session, update its
  Status and set Last Updated to today's date. Add a row for any new doc. If a doc became
  obsolete or suspect, reflect that.

## 3. Apply vs. confirm

**Auto-apply** (low-risk, mechanical) — just do these and report them:
- Checking off completed TODO items in STATUS.
- Stamping `Last Updated` dates and adding INDEX rows for new docs.
- Appending a decision to the decision log when it was clearly and explicitly decided this
  session.
- Moving finished items out of Active.

**Confirm before applying** (judgment calls) — propose, then wait for the user's yes:
- Marking any doc 🔴 Obsolete or ⚠️ Suspect.
- Roadmap phase transitions.
- New `5-deferred-items.md` entries (the trigger condition is a judgment call).
- Rewording "Where we are", or removing/superseding existing content.
- Anything you're unsure was actually decided vs. just discussed.

## 4. Report

Show a summary of everything you changed, grouped into **Auto-applied** and
**Needs your confirmation**. For the confirmation group, show the proposed text and apply it
only after the user approves.

Finish by asking whether to commit (don't commit unless asked) and noting the single most
important thing for the next session's "Where we are."

> Use today's date for all stamps. Preserve each document's established format and voice —
> these docs are read cold by future contexts, so consistency matters more than your own phrasing.
