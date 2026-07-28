---
description: Lightweight mid-session checkpoint — sync STATUS (where we are / active now) to current reality, nothing more. Safe to run repeatedly. Use it as a backup-save when stepping away without clearing context; it does NOT touch the decision log, roadmap, or deferred-items.
allowed-tools: Read, Glob, Grep, Edit, Write, Bash(git status:*), Bash(git log:*), Bash(git diff:*)
---

You are saving a quick checkpoint of the current working session on this
project — **not** closing it out. The goal is to make `docs/2-project-status.md` reflect reality
right now, so that if context is later cleared the next `/start-session` is accurate. This is the
lightweight counterpart to `/end-session`: fast, repeatable, and safe to run several times in a
session.

## What this does — and does NOT do

- **Does:** freshen `docs/2-project-status.md` only (plus trivial INDEX date hygiene for a
  brand-new doc, if one was created this session and isn't listed yet).
- **Does NOT:** append to `docs/4-decision-log.md`, edit `docs/3-project-roadmap.md`, or add to
  `docs/5-deferred-items.md`. Those are `/end-session`'s job — the append-only decision log
  especially must not be touched here, to avoid duplicate entries across repeated saves.

## Steps

1. **Quick reconstruct.** Run `git status` and `git log --oneline -5`. Scan the conversation since
   the last checkpoint for: work completed, new actions/bugs surfaced, things now blocked or
   unblocked. Keep it brief — this is a save-point, not a full audit.
2. **Sync `docs/2-project-status.md`:**
   - Update "Where we are" only if it has drifted from reality.
   - Check off completed "Active now" items; move finished ones out.
   - Add newly-surfaced actions/bugs to Active now (with a grounded one-line lead where you have it).
   - Move items between Active / Up next / Blocked as their state changed.
   - Keep it current, not append-only.
3. **INDEX hygiene (only if needed).** If a brand-new doc was created this session and isn't in
   `docs/1-documentation-index.md`, add a row and stamp today's date. No status reclassification.
4. **Park the heavy stuff.** If you notice something that belongs in the decision log, roadmap, or
   deferred-items, do NOT write it there — instead note it inline in STATUS (e.g., a short
   "for next `/end-session`:" line) so it's captured for the real close-out.

## Report

Give a short summary of what you synced in STATUS and anything you parked for `/end-session`.
Don't commit unless asked. Remind the user this was a checkpoint, not a close-out.

> Use today's date for any stamp. Preserve STATUS's established format and voice.
