---
name: report-handoff
description: The two-tier reporting convention every stack-ops agent follows — a hard-capped digest returned to the caller, with full detail written to a file the caller reads only if it needs to. Use when producing the final report from any build, compile, test, qa, or deploy run.
---

# Report handoff: digest up, detail to disk

## Why this exists

Your reply lands in the **controller's** context and stays there for the rest of the session. Detail
written to a file costs the controller nothing until it chooses to read it — and then it can read
15 lines instead of 400. So: the file is the report; your reply is a receipt.

Note what this does **not** mean. Reading the file is not free — it costs the same as inlining
would have. The saving comes from the caller reading **selectively, or not at all**. Which means the
digest has to be good enough to decide with. If the caller must open the file every time to know
whether the run passed, the digest failed at its only job.

## The two tiers

**Tier 1 — the report file.** Everything: every error, every failing test, warnings, timings,
excerpts, log paths. Length is free here. Write to `.claude/stack-ops/<verb>-report.md`
(`implement-report.md`, `qa-report.md`, …). Overwrite the previous run; it's scratch, and it's
gitignored. Structure it with stable `##` headings and keep one finding per line so the caller can
grep it and read a range instead of the whole file.

**Tier 2 — the digest you return.** Hard caps, not "be concise":

| Outcome | Cap |
|---|---|
| Pass | **3 lines.** Verdict, what wasn't covered, file path. Nothing else. |
| Fail | **20 lines.** Verdict, per-stack one-liners, up to **3** root causes at **one line each**, file path. |
| Blocked / toolchain / no-driver | **5 lines.** What's missing and what to do about it. |

Rules inside the cap:

- **No tables in a passing digest.** A table costs more than the fact it carries.
- **Never inline a log excerpt, stack trace, or code block.** Cite `path:line-start-line-end` and
  let the caller read that range if it wants it.
- **Report root causes, not symptoms.** Deduplicate hard before counting: MSBuild prints each error
  twice; 40 TypeScript errors are often one missing import; a whole failing suite is usually one
  broken fixture. "31 errors, all from the unresolved import at `api.ts:4`" is one line and more
  useful than 31.
- **Truncation must be visible.** If you capped at 3 of 12, say `3 of 12 shown — rest in <file>`.
  Silent truncation reads as completeness, which is the failure mode this whole convention exists
  to avoid.
- **Absence still gets stated**, but in one line, not a section. `Not covered: no tests in either
  stack.` Honesty costs a line, not a paragraph.

## Digest shapes

Pass:

```markdown
## Build gate: PASS — netcore ✓ node ✓ (compile+lint), 0 tests
Not covered: no test harness in either stack; no e2e.
Detail: .claude/stack-ops/implement-report.md
```

Fail:

```markdown
## Build gate: FAIL at compile — netcore ✗, node not run

1. `src/Maps.Api/Storage/FileImageStore.cs:37` — CS0234, project `.Directory` namespace shadows `System.IO.Directory` (needs full qualification)
2. 12 further CS0234 in the same file — same root cause

Not covered: tests skipped (build red). 2 of 13 errors shown.
Detail: .claude/stack-ops/implement-report.md  •  Log: .claude/stack-ops/compile-netcore.log
```

## One more lever

If the caller's next step is a **fix**, say so and let the fixer read the report file directly. The
controller then never pays for the detail at all — it only ever sees two receipts. Suggest this
explicitly when a run produces more findings than the digest can carry.
