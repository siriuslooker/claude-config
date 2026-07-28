---
description: Multi-agent fan-out/fan-in security & best-practices review. Dispatches 10 independent reviewer sub-agents (one per perspective), consolidates by overlap, gates one-offs against hallucination, and writes a single ranked report. Use --quick for a 5-perspective pass.
argument-hint: "[--quick] [paths/globs | repo dirs | nothing to auto-resolve diff]"
---

You are the **orchestrator** for a fan-out / fan-in code review. You dispatch **10 independent reviewer sub-agents**, each reviewing the target from a *single distinct perspective*, then consolidate their findings into one ranked report. Use **Sonnet** sub-agents (model: sonnet) for the reviews. Run reviewers in parallel (one message, multiple Agent tool calls).

`$ARGUMENTS` may contain a `--quick` flag and/or explicit scope (paths, globs, or one-or-more repo directories). Anything else is scope. If `$ARGUMENTS` is empty, auto-resolve the diff per §0.

Write all artifacts under a `review/` directory at the current working root: diffs in `review/diffs/`, raw findings in `review/raw/`, the manifest at `review/_manifest.md`, the final report at `review/REVIEW.md`.

## 0. Scope resolution (do this first)

Establish the review target before dispatching anything.

1. Determine the diff/scope, in this priority order:
   1. **Explicit scope in `$ARGUMENTS`** (paths, globs, or repo dirs). For each repo dir, resolve its own diff (next bullet). For loose paths/globs, review those files.
   2. **Upstream branch.** Resolve the upstream tracking branch: `git rev-parse --abbrev-ref --symbolic-full-name @{u}`. If it resolves AND its merge-base with HEAD is behind HEAD, diff `base=$(git merge-base HEAD @{u})` → `git diff "$base"...HEAD`.
      - **Watch the just-pushed trap:** if `@{u}` resolves but equals HEAD (you just pushed the feature branch, so `origin/<branch> == HEAD`), the diff is empty. Do NOT stop — fall through to the base-branch comparison below using the branch the feature was cut from (`origin/development` if it exists, else `origin/main`/`origin/master`).
   3. **Default-branch fallback.** If `@{u}` fails or was empty, try `origin/development`, then `origin/main`, then `origin/master`: `base=$(git merge-base HEAD <ref>)` → `git diff "$base"...HEAD`.
   4. **No remote at all → explicit paths.** If none resolve and no scope was given, list the changed files in the working tree and **ask the user to confirm scope** before proceeding.
   - If the resolved change set is empty, **stop and ask**.
2. **Multi-repo:** if scope spans several repos (e.g. a workspace with multiple clones), resolve each repo's diff separately and write one diff file per repo (`review/diffs/<repo>.diff`). Prefix file paths with the repo name in the manifest and in fingerprints so identical filenames in different repos don't collide.
3. Produce a **file manifest** (path, language, LOC changed) and a one-paragraph description of what the change set does, plus any security-relevant context (auth model, PII flows, irreversible operations). Persist to `review/_manifest.md`. Note which changed files are the actual feature vs. incidental (generated, test-only, unrelated cleanup) so reviewers prioritize.
4. Cap per-reviewer reading: if the diff exceeds ~4k changed lines, chunk by directory/module and note in the report that coverage was partitioned.

Do **not** skip scope resolution — every reviewer must see the same manifest so findings are comparable.

## 1. The 10 reviewer perspectives

Dispatch exactly these ten (or the quick subset, §4). Each runs blind to the others. Each gets: the manifest, the diff file(s), and **only its own lens prompt**. Tell each agent its working directory, that it may open full source for context but must only report issues pointable in the diff, and the strict output contract below.

| # | Perspective | Primary focus |
|---|-------------|---------------|
| 1 | **Injection & input handling** | SQLi, command/LDAP/XPath injection, deserialization, SSRF, path traversal, unsafe reflection, header/CRLF injection |
| 2 | **AuthN / AuthZ** | Missing/incorrect access checks, broken object-level auth (IDOR), privilege escalation, session/token/key handling |
| 3 | **Secrets & configuration** | Hardcoded credentials, keys in source, insecure defaults, env/config leakage, secrets/PII in logs |
| 4 | **Crypto & data protection** | Weak/home-rolled crypto, bad randomness, plaintext PII at rest, TLS misuse, password hashing |
| 5 | **Error handling & resilience** | Swallowed exceptions, info-leaking error messages, missing timeouts/retries, unhandled edges, fail-open logic |
| 6 | **Concurrency & resource mgmt** | Races, deadlocks, unclosed resources/handles, connection/socket leaks, thread-safety of shared state |
| 7 | **API contract & data integrity** | Validation gaps, type/null contract violations, idempotency, pagination/limit abuse, mass-assignment |
| 8 | **Dependency & supply chain** | Known-vulnerable packages, unpinned/floating versions, transitive risk, feed/registry trust, build-script trust |
| 9 | **Maintainability & idioms** | Language/framework idioms, naming, dead code, complexity hotspots, duplication, test coverage of the change |
| 10 | **Performance & scalability** | N+1, unbounded allocations, hot-path inefficiency, missing indexes/caching, sync-over-async |

### Reviewer output contract (strict)

Each reviewer returns **only** a JSON array (no prose) written to `review/raw/P<N>.json`. This is parsed mechanically. Each finding:

```json
{
  "id": "P1-001",
  "perspective": 1,
  "title": "short title",
  "file": "repo-prefixed path",
  "line": 142,
  "severity": "critical|high|medium|low|info",
  "confidence": 0.9,
  "category": "short-kebab issue-class e.g. sql-injection",
  "evidence": "what in the diff shows this",
  "recommendation": "the fix",
  "fingerprint": "<category>:<file>:<symbol-or-block>"
}
```

Rules for reviewers (put these in every reviewer prompt):
- `severity` ∈ {critical, high, medium, low, info}. `confidence` ∈ [0,1].
- `fingerprint` is a **stable location+issue-class key** the orchestrator uses to detect overlap: `<category>:<file>:<symbol-or-block>` — **no line number**, so the same issue spotted by two reviewers collides even if line estimates differ.
- Report only issues pointable in the diff. No speculative "you should also consider…" essays.
- If nothing in the lens, write exactly `[]`.

## 2. Consolidation (orchestrator, main thread)

After all reviewers return, read every `review/raw/P<N>.json`.

### 2a. Cluster by fingerprint
Group findings sharing a `fingerprint` (or clearly the same issue at the same location across categories). Each cluster = one consolidated finding.

### 2b. Score
```
overlap   = number of DISTINCT perspectives reporting the cluster
base      = severity_weight(max severity in cluster)   // critical=5, high=4, medium=3, low=2, info=1
score     = base * (1 + 0.5 * (overlap - 1)) * mean_confidence
```
Corroborated findings (overlap ≥ 2) rank above one-offs of equal severity.

### 2c. Adjudicate one-offs (the hallucination gate)
For every cluster with `overlap == 1`, **independently verify before it enters the report**:
1. Open the cited file/line; confirm the evidence actually holds.
2. Classify as **confirmed**, **needs-human-judgment**, or **rejected (likely false positive)**.
3. Only **confirmed** one-offs proceed to the main report. **needs-human-judgment** and **rejected** go to an appendix with your reason — not silently dropped, so the user can audit the gate.

The main findings table contains only **confirmed** (verified one-off) and **corroborated** (overlap ≥ 2). Corroborated findings are trusted without re-verification but still get a one-line sanity check — and if you find a corroborated finding's severity is overstated once you read the code, say so and adjust (note the correction).

### 2d. Deduplicate recommendations
Merge multiple fixes for one cluster into the single best recommendation.

## 3. Final report

Write `review/REVIEW.md`:

1. **Summary** — change description, files reviewed, counts by severity, count of one-offs rejected/deferred at the gate.
2. **Findings table**, sorted by score desc, severities `critical`–`low` (hold `info` for Appendix A):

   | Rank | Severity | Score | Seen by | Title | File:Line | Status |

   *Seen by* = perspective numbers; *Status* ∈ {confirmed, corroborated} — nothing else.
3. **Detailed findings** — one section per finding: evidence, why it matters, recommended fix, which perspectives flagged it.
4. **Appendix A: Info-severity findings** (same column format, out of the main table).
5. **Appendix B: Gated one-offs** — every one-off that did NOT reach the report: the finding, which reviewer raised it, the gate classification, and your reason.
6. **Appendix C: Coverage notes** — partitioning/chunking, files skipped, scope caveats, anything not reviewed.

Do not auto-apply any fix. Present the report and stop. The user decides actions.

## 4. Run modes

Default to **full** unless `$ARGUMENTS` contains `--quick` (or the user says "quick pass").

- **Full (default):** all 10 perspectives. ~11 model passes. Use for PRs, release branches, anything touching auth/crypto/data, or any change the user wants signed off.
- **Quick (`--quick`):** perspectives **1, 2, 3, 5, 9** (injection, authN/authZ, secrets/config, error-handling, maintainability — highest security-signal-to-cost). ~6 passes. Everything downstream is identical (same clustering, scoring, gate, report). The report summary must state `mode: quick (perspectives 1,2,3,5,9)` and Appendix C must note that 4, 6, 7, 8, 10 were not run — so absence of crypto/concurrency/API-contract/dependency/performance findings is not mistaken for a clean bill on those axes.

When invoked full on a diff large enough to be expensive (>4k changed lines × 10 reviewers), warn the user and offer `--quick` before proceeding.

## 5. Determinism & independence

- All reviewers get the same manifest input so results are comparable run-to-run.
- If parallel dispatch isn't available, run sequentially but keep each reviewer's context isolated — never let a later reviewer see an earlier one's findings, or you destroy the overlap signal that makes corroboration meaningful.
- Each reviewer prompt must be self-contained (working dir, files to read, its single lens, the strict JSON contract, where to write). Do not let reviewers narrate — the only output that matters is their `review/raw/P<N>.json`.
