---
description: Lightweight mid-session checkpoint — sync STATUS (where we are / active now) to current reality, nothing more. Safe to run repeatedly. Use it as a backup-save when stepping away without clearing context; it does NOT touch the decision log, roadmap, or deferred-items.
allowed-tools: Read, Glob, Grep, Edit, Write, Bash(git status:*), Bash(git log:*), Bash(git diff:*), Bash(pwsh:*)
---

You are saving a quick checkpoint of the current working session on this
project — **not** closing it out. The goal is to make the project's work state reflect reality right
now, so that if context is later cleared the next `/start-session` is accurate. This is the
lightweight counterpart to `/end-session`: fast, repeatable, and safe to run several times in a
session.

## What this does — and does NOT do

- **Does:** update item state in the work ledger and re-render the generated views; freshen the
  narration in `docs/2-project-status.md` (plus trivial INDEX date hygiene for a brand-new doc, if one
  was created this session and isn't listed yet).
- **Does NOT:** append to `docs/4-decision-log.md`, edit `docs/3-project-roadmap.md`, or add to
  `docs/5-deferred-items.md`. Those are `/end-session`'s job — the append-only decision log
  especially must not be touched here, to avoid duplicate entries across repeated saves.

## Steps

1. **Quick reconstruct.** Run `git status` and `git log --oneline -5`. Scan the conversation since
   the last checkpoint for: work completed, new actions/bugs surfaced, things now blocked or
   unblocked. Keep it brief — this is a save-point, not a full audit.

2. **Write the ledger.** Find the ledger (`docs/backlog.json`, or the path the project's `CLAUDE.md`
   names) and edit it directly — you are the controller, and the controller owns the ledger.
   - Set `state` on items that moved: `open` → `in-progress` → `landed`.
   - Add an item for anything new that surfaced, with all required fields. Give it a real `id` — a
     name, never an ordinal — and populate `aliases` with whatever the conversation has been calling it.
   - Set or clear `waitingOn` where a human or external gate appeared or dissolved. **Never infer it**;
     if nobody said they were waiting on someone, it is `null`.
   - **Leave landed items in place for now.** `/end-session` removes them; removing them here loses
     work that a later close-out needs to reconcile.
   - Then re-render and re-check:
     ```
     pwsh -NoProfile -File "$HOME/.claude/tools/work-ledger.ps1" -Render -Ledger <ledger> -Into docs/2-project-status.md
     pwsh -NoProfile -File "$HOME/.claude/tools/work-ledger.ps1" -Validate -Ledger <ledger>
     ```
     Report the validator's findings in your summary. Exit 2 means the ledger is unreadable — say so
     rather than continuing as if the write landed.

3. **Sync the narration in `docs/2-project-status.md`.**
   - Update "Where we are" only if it has drifted from reality.
   - ⚠️ **Never hand-edit inside the `<!-- BEGIN GENERATED: work-ledger -->` markers.** Edit the ledger
     and re-render; that is the only path.
   - Keep it current, not append-only.

4. **INDEX hygiene (only if needed).** If a brand-new doc was created this session and isn't in
   `docs/1-documentation-index.md`, add a row and stamp today's date. No status reclassification.

5. **Anything owed to `/end-session` goes in the ledger, not in a sentence.** A decision to write up, a
   roadmap phase that moved, a deferral to record: add a ledger item with the matching `kind`
   (`decision` · `doc`) and a `detail` pointer to where it will be written. **Do not park it as a "for
   next `/end-session`:" line in STATUS** — a pending update stored as prose inside the document it is
   meant to update is exactly the drift this ledger exists to remove.

> ⚠️ **No ledger file?** Skip step 2 and the generated-block rule in step 3, and do what this command
> always did: freshen STATUS's own Active / Up next / Blocked lists by hand, and park heavy items as a
> short "for next `/end-session`:" line in STATUS. Most projects have no ledger; behaviour there is
> unchanged.

## Report

Give a short summary of the ledger items you changed (by id), the validator's result, what you synced
in STATUS narration, and anything left for `/end-session`. Don't commit unless asked. Remind the user
this was a checkpoint, not a close-out.

> Use today's date for any stamp — including the ledger's `updated` field. Preserve STATUS's
> established format and voice.
