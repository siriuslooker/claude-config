---
description: Full session close-out — reconcile STATUS, append decisions, record deferrals, and stamp the doc index so the next /start-session is accurate. For quick mid-session saves use /save-context instead. Run at the genuine end of a session or when low on context.
allowed-tools: Read, Glob, Grep, Edit, Write, Bash(git status:*), Bash(git log:*), Bash(git diff:*), Bash(git add:*), Bash(git commit:*), Bash(pwsh:*)
---

You are closing out a working session on this project.
Your job is to bring the project docs into agreement with what actually happened this session,
so the next fresh context (`/start-session`) reads accurate state. This is the write half of the
loop that keeps the docs canonical.

> This is the **full** close-out. For a quick mid-session save that only freshens state — the
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

## 2. Reconcile the work ledger

Find the ledger (`docs/backlog.json`, or the path the project's `CLAUDE.md` names). You are the
controller; the ledger is yours to write. See the `work-ledger` skill for the field contract.

1. **Mark what moved** — `state` to `in-progress`, `landed` or `dropped` for every item this session
   touched.
2. 🔴 **Remove every `landed` and `dropped` item — and append its `id` and every one of its `aliases`
   to the ledger's top-level `retired` array in the same edit.** They are not marked and kept; the
   decision log and the commit trail are the history, and both are append-only and already work. A
   ledger you cannot read in one pass is the failure it replaced.

   ⚠️ **Removing without retiring is the one way to break the orphan-citation check**, and it degrades
   silently. Every live document that still cites the item you just removed becomes an unresolvable
   citation, so the next session's findings fill with noise about closed work and the check stops being
   read. Measured on the first real ledger: **30 orphan findings, 26 of them from live surfaces.**
   The two halves are one operation — never do the removal alone.
3. **Add what surfaced** — new items with all required fields, real named ids, `aliases` populated from
   whatever the session called them, and a `detail` pointer to the prose that explains each.
4. **Clear or refresh `waitingOn`** where a gate dissolved or a person answered. Never infer it.
5. **Re-render, then re-validate:**
   ```
   pwsh -NoProfile -File "$HOME/.claude/tools/work-ledger.ps1" -Render -Ledger <ledger> -Into docs/2-project-status.md
   pwsh -NoProfile -File "$HOME/.claude/tools/work-ledger.ps1" -Validate -Ledger <ledger>
   ```
   **Fix what it finds before you finish**, or name in your report each finding you are leaving and why.
   Exit 2 means the ledger is unreadable — stop and say so; do not write around it.

> ⚠️ **No ledger file?** Skip this section entirely and reconcile STATUS's own lists by hand, as this
> command always has. Most projects have no ledger; behaviour there is unchanged.

## 3. Determine the updates needed across these docs

- **`docs/2-project-status.md`** — update the narration: "Where we are", open decisions, anything
  mid-flight. ⚠️ **Never hand-edit inside the `<!-- BEGIN GENERATED: work-ledger -->` markers** — the
  queue comes from §2's render. Where there is no ledger, update the Active / Up next / Blocked lists
  directly and keep them current rather than append-only.
- **`docs/4-decision-log.md`** — append (never rewrite) any architectural or implementation
  decision made this session, in the established style: a dated, bold lead sentence followed by
  rationale. Match the existing voice exactly. Where a ledger item recorded a decision as owed
  (`kind: decision`), write it here now and set that item's `decidedIn` to the section you just added.
- **`docs/5-deferred-items.md`** — add any consciously-punted item, in the file's structure
  (Current state / Risk / Trigger to revisit / Likely shape). A deferred item that is still work keeps
  its ledger entry; the trigger lives here because no tool can evaluate it.
- **`docs/3-project-roadmap.md`** — update only if a phase materially moved (started, completed,
  re-scoped). Bump its "Last updated" line when you do.
- **`docs/1-documentation-index.md`** — for any doc created or meaningfully revised this session, update its
  Status and set Last Updated to today's date. Add a row for any new doc. If a doc became
  obsolete or suspect, reflect that.

⚠️ **Prose cites a ledger id; it never states the item's status.** No checkbox, no `status:` line, no ✅
beside an id in any document but the ledger.

## 4. Apply, or park — NEVER ask

🔴 **`/end-session` is terminal. The user's next command is `/exit` or `/clear`, then `/start-session`
when they return.** A question at close-out blocks a clean exit, and answering it starts a new round of
work that itself needs closing out — a loop. So this command **asks nothing**: no `AskUserQuestion`, no
"shall I…?", no "want me to commit?", no closing question of any kind. This overrides any general
preference for asking via `AskUserQuestion`.

**Apply** — everything that was decided or demonstrably happened this session:
- Ledger state changes, removal + retirement of landed items, new items, re-rendering.
- `Last Updated` stamps and INDEX rows.
- Decision-log entries for things clearly and explicitly decided this session.
- `waitingOn` changes the session itself proved (a gate observed to dissolve, a person who answered).
- STATUS narration — rewriting "Where we are" is the point of this command, not a judgment call.

**Park, don't apply** — anything that would otherwise have needed a yes:
- Marking a doc 🔴 Obsolete or ⚠️ Suspect, roadmap phase transitions, marking an item `dropped`, new
  deferred-item entries whose trigger is your invention, and anything you're unsure was decided rather
  than discussed.
- Write each one into STATUS's narration (outside the generated markers) under a
  **"⏸️ Parked at close-out — confirm next session"** heading: one line each, with the proposed change.
  `/start-session` briefs STATUS, so the question reaches the user when they are ready to answer it —
  at the start of a session, where an answer costs nothing.

## 5. Commit, then report

- **Commit the close-out** if the diff is documentation-only (`docs/`, markdown, the ledger JSON) —
  the global rule permits docs-only commits straight to the default branch, and on a feature branch it
  belongs on that branch anyway. If the working tree also holds code changes, commit only the doc
  paths and name the uncommitted code in the report. **Never push.**
- **Report** as a plain statement: what changed (ledger diff by id — moved / removed / added), the
  validator's final exit state with any findings left standing, the commit hash, what was parked, and
  the single most important thing for the next session's "Where we are."
- **The last line is a statement, never a question.** End with: *"Close-out complete — safe to
  `/exit` or `/clear`."*

> Use today's date for all stamps, including the ledger's `updated` field. Preserve each document's
> established format and voice — these docs are read cold by future contexts, so consistency matters
> more than your own phrasing.
