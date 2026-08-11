---
name: phase-loop
description: Run a phase of planned work semi-autonomously — decompose into day-sized deployable increments, run a readiness interview to surface undocumented decisions BEFORE starting, then loop implement/verify/commit per increment with a phase journal recording every autonomous decision. Use when asked to plan a phase, check phase readiness, or run a phase end-to-end. Project-agnostic; reads the project's own phase plan for content.
---

# The phase loop

A protocol for running planned work with the developer away, and for knowing when not to.

**It is deliberately not just a runner.** Most of the value is in the two things that happen before and
around the loop: extracting decisions from the developer's head first, and auditing what agents claim
about their own work afterwards. Skip those and an autonomous loop produces wrong work faster and with
more confidence than a human would.

## The three artifacts

| Artifact | Where | What it holds |
|---|---|---|
| **Phase plan** | project repo, e.g. `docs/7-phase-plan.md` | the decomposition — project content |
| **Readiness report** | scratch, per run | questions for the developer, produced before a run |
| **Phase journal** | project, append-only | every autonomous decision and its justification |

Keep the *format* here and the *content* in the project. A phase plan checked into a repo is data; this
file is the procedure.

---

## 1. Decomposition — the unit is a day, not a branch

Each increment must satisfy **all four**:

1. **Realistically one day** of agent implementation plus verification. When in doubt, split — a
   too-small increment costs a little ceremony, a too-large one blows the day and ends with nothing
   shippable.
2. **Ends deployable.** No increment may leave a surface half-migrated or a screen broken pending the
   next one.
3. **Ends manually testable by a human**, described in user-visible terms. "The schema is widened" is not
   testable by a person; "a volunteer can sign in with their number as well as their email" is.
4. **Independently valuable, or explicitly scaffolding** — and if scaffolding, justify why it still needs
   its own day.

Constraint 3 is the one that forces uncomfortable splits, and it is the one that pays: it is what makes a
day's output reviewable by someone who is not reading the diff.

### Per-increment fields

Keep them exactly as named — they are parsed.

```
### <ID> — <short title>
- **status:** planned | ready | running | blocked | done
- **depends-on:** <IDs, or none>
- **surfaces:** <the packages/layers touched>
- **done-when:** <a criterion that can be checked, not a description of the work>
- **manual-test:** <what a person does to see it works>
- **decisions-needed:** <pointers to open questions, or none>
- **risk:** <the specific failure mode; "none known" is allowed>
```

**`status: ready` is the gate.** It means the increment can start without asking anyone a question.
Anything listed in `decisions-needed` must be answered, or an assumption recorded in the project's
decision log, before it can be `ready`.

**`risk` names the failure mode, not the difficulty.** "Touches three packages" is useless to an agent.
"A wrong derivation produces a plausible grid with the wrong dates" gets checked.

**Leave far-off work coarse.** Speculative decomposition is worse than absence, because the runner treats
it as executable.

---

## 2. Readiness interview — run BEFORE any unattended phase

**This is an interview, not a scan.** Its output is a ranked list of questions for a human, each
answerable in under a minute. Not a project summary.

### Why it is the highest-value tool

The defects that survive a green test suite are usually **undocumented domain rules** — a constraint that
exists only in the developer's head, which no scan of code or docs can find and no code reviewer can
check, because the rule is unreadable to them.

The interview's real product is therefore **domain rules written into the repo.** Once a rule is written
down, every later automated check can use it. This is how a second phase becomes safer than the first.

### Four sections, ranked by consequence

1. **Blockers** — proceeding under a guess would produce throwaway work or touch something irreversible.
   For each: the increment, the question, why it blocks, and what you would assume if forced.
2. **Domain-rule questions** — *the section that matters.* For each increment, name the domain concepts
   it touches and ask what the rules are. Prioritise dates and ranges, eligibility, identity, exceptions,
   "who counts as". **Explicitly flag any rule that existing code clearly assumes but states nowhere.**
3. **Decisions the runner can make itself** — with a recommended default for each, so the developer can
   approve a batch rather than answer individually.
4. **Technical unknowns** — missing seams, absent wiring, anything a `done-when` assumes exists.

### Rules

- Rank by consequence across sections; the reader may stop partway.
- Never ask what the project's own docs already answer. One answered question spends the credibility of
  the ones that matter.
- Prefer ten sharp questions to thirty vague ones. Empty sections are a fine result — say so.

---

## 3. Brief templates

The agents are stack-agnostic and are extended by skills, never by editing them. So anything they must do
that they would not do by default goes in the **brief**.

### Every implement brief

- The increment's `done-when` verbatim, as acceptance criteria.
- The `risk` verbatim, phrased as a thing to check.
- An explicit out-of-scope list, with instruction to **stop and report rather than improvise**.
- **Stop conditions** — circumstances where stopping is the correct outcome, not a failure. This is what
  turns "an agent quietly patched a shared primitive" into "an agent surfaced a latent defect".
- "Never touch git." The controller owns branches, commits and PRs.

### Every verify brief — the claim audit

Running the tests is the easy half and it is not what finds things.

**Independently audit every claim the implement report makes about its own scope and coverage**, each
reported as its own item:

- For every self-declared "out of scope", "already covered", "not applicable", "left alone" — is it
  actually so, or is there a gap wearing that label?
- For every claimed behavioural property, does a test assert it, or is it merely implemented?
- Where something is *partially* done, state precisely what a user would observe.

Also: **confirm or contradict claimed test counts from your own run** — never accept them. **Name what
was not covered**, rather than letting silence imply coverage. And **be blunt**: work that replaces one
half-migration with another is a failed increment, not a footnote.

---

## 4. Decide versus pause

Decide, record in the journal, continue — **unless any of these hold**, in which case stop and notify:

1. **Expensive to reverse** — migrating live data, an identifier already in printed material, anything
   with an external side effect.
2. **Blast radius exceeds the phase.**
3. **Contradicts a recorded decision** in the project's decision log.
4. **Needs domain knowledge nobody wrote down.**

Reversal cost is the test, not deadline pressure. Where an assumption would be cheap to undo, decide and
move; where undoing it means a migration or a re-print, wait.

### Notification is a hard requirement, not a courtesy

**Whenever the run stops for any reason, send a Pushover notification.** The developer may be away from
the console; an unattended loop that halts silently has failed even if the work is correct, because the
time between stopping and being noticed is dead time.

Send one on **every** stop, without exception:

- an escalation (one of the four triggers)
- a hard stop
- the phase completing
- stopping for context budget
- an increment completing, if no further increment will start
- **anything needing console access** — see below

### Console-access blockers are a stop, not something to route around

Some things cannot be fixed from inside a session at all: an **agent definition change**, an **MCP
server change**, and anything else loaded at process start. Editing the file is not enough — it takes
effect only after a full quit and relaunch. `/clear` resets the conversation but not the process, so it
is not a substitute. (Skills appear to hot-load; agent frontmatter does not. Do not assume they behave
alike.)

**Treat these as a fifth escalation trigger.** The temptation is to work around them — do the agent's job
in the main thread, or carry on and batch the blocked step later. Both are worse than they look: the
first burns the context that keeps the run alive, and the second accumulates unverified work behind a
gate that may then fail on all of it at once.

**Notify immediately, and say plainly in the message that console access is required and what to do** —
"restart Claude Code" is actionable; "blocked on tooling" is not. Then either continue on work that does
not depend on it, or stop, whichever is honest — and say which.

The notification carries the question, the options, and a recommendation — never just "stuck". The
developer should be able to unblock in one line without opening the console.

`pwsh -NoProfile -File "$HOME/.claude/tools/notify.ps1" -Message "..." -Title "..."`

---

## 5. The phase journal

Append-only, one section per increment, in the project. Every decision made without asking, with its
justification. Also record decisions that were *considered and rejected* — the reasoning is what stops
the same question being re-litigated next phase.

**This is what makes unattended running auditable**, and the reason a phase can be trusted enough to run
the next one. Returning to a finished phase should mean reading one document, not scrolling a transcript.

---

## 6. Running the loop

Per increment: **branch → implement → verify (with claim audit) → `qa` → fix any gaps → commit → PR**.

**`qa` is not optional and not skippable because the change "has no UI".** Nothing enters a PR that has
not been exercised in a running app. The increment's own `manual-test` field is the script — if that
field describes something a person would do, an agent can do it first. An increment whose `manual-test`
genuinely cannot be exercised is a badly-written increment, not an exemption.

Skipping it is easy to rationalise when the diff looks internal. Sync internals, merge rules and schema
changes are exactly where a green suite and a broken app coexist most comfortably.

### Report sparingly while running

The developer is away; intra-step narration is unread output. **Between increments, say almost nothing.**
The journal is the record — write there, not to the console. Report to the console at a pause, at a
completion, or when asked.

### Watch the context budget

Before starting any increment, check remaining context. An agent run that returns into a nearly-full
context loses the result. **Below roughly 30% remaining, stop and hand off** rather than starting
another increment — finish the one in flight, write the journal, notify, and say plainly that the run
stopped for context rather than for a problem.

Between increments, check whether anything learned invalidates a later increment's plan. A phase plan
written before the phase started is a hypothesis.

### At the phase boundary

1. **Code review** across the whole phase diff. Calibrate the reviewer first — see §7.
2. **Human QA document** covering the phase's features, in the project's existing QA format.
3. **Deploy** to the test rig.
4. **Notify** that the phase is ready for testing.

### Hard stops, regardless of the classifier

Stop and notify if: the same increment fails verification twice; a fix requires changing a test that
asserts existing behaviour and it is not obvious the old assertion was wrong; two increments in a row
uncover defects in already-merged code; or the plan's remaining increments no longer make sense given
what was learned.

---

## 7. Calibrate the reviewer before trusting it

A code-review pass nobody has calibrated cannot be trusted as an unattended gate.

**Calibrate against known defects.** After any phase where real defects were found, keep them as an
answer key and check whether the review protocol finds them unaided. Expect it to miss some — the useful
output is *which* it misses and why.

Three defect shapes worth testing against, because diff-scoped review is structurally weak at all three:

- **Cross-configuration interaction** — code correct for each configuration alone, wrong when two share a
  resource. Reviewers need sibling config values inlined in the manifest or they will not make the jump.
- **Absence** — a call site that should have been migrated and was not. The stale file may not even
  appear in the diff.
- **Domain-rule violation** — no code smell, and the rule is unwritten. **Structurally out of reach for a
  reviewer.** This one belongs to the readiness interview, which is why that step exists.

Assign each defect class an owner in the loop rather than hoping review catches everything: stop
conditions catch the first, the claim audit catches the second, the readiness interview catches the
third.
