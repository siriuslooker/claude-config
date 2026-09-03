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

## 2b. Work orders — the DURABLE form of a brief, one per parallel unit

⭐ **A brief passed as prompt text does its job and then ceases to exist.** A work order is the same brief
as a **numbered, tracked file** — so it can be cited from a source comment months later
(`/* CARDS, not horizontal rows (WO-12 §2) */`), read by the next agent that touches the same code, and
audited without scrolling a transcript. **Where a project keeps them (`.claude/work-orders/`), write one
per parallel unit of work and pass the agent its path instead of a wall of prompt.**

They pair naturally with the fan-out in §6: **one work order per worktree**, and the file is where that
worktree's boundary is written down.

### Shape

```markdown
# Work Order 9 — <what and why, in one line>

**Ticket:** EN-957 · **Phase:** P8 · **Branch:** `EN-957-fb11-nudge-a11y`
**Worktree (your ONLY working directory):** F:\...\maps-wt-fb11-nudge-a11y

## Standing rules
1. Work only inside the worktree above. Never edit the main checkout.
2. Use the phase-loop skill. This work order is its readiness answer sheet.
3. No console narration. Your output is a `## Report` appended to this file.
4. Commit on the existing branch. No push, no PR, no merge, no main.
5. Do not edit docs/.
6. Gate with the <stack> stack only. Your baseline is <N>.

## The gap        <- what is wrong or missing, with citations
## What to build  <- acceptance criteria, the risk verbatim, out-of-scope, stop conditions
## Report         <- the agent appends here
```

### The three parts that carry the weight

- 🔴 **The worktree path, named as the ONLY working directory.** Parallel agents on one repo is exactly
  when an agent edits the wrong tree, and prose is what prevents it.
- 🔴 **An explicit test baseline, with its provenance.** *"Your baseline is 679, not 659 — the previous
  work order added 20 on this branch. A drop below 679 is a finding, not a pass."* ⚠️ **A stale baseline
  is worse than none**, because an agent that inherits it reports a real regression as a pass.
- ⭐ **`## Report` appended to the same file.** Brief and outcome live together, so the record survives the
  session and the next reader gets both the intent and what actually happened.

### When NOT to write one

A work order costs a file and a review. For a genuinely small, self-contained change, prompt text is
fine. Write one when the work is **parallel** (the boundary needs a home), **sequenced** (a later order
must read an earlier one's Report), or **likely to be cited later** — which is most things that change
behaviour a comment will need to justify.

⚠️ **Do not invent work orders in a project that has no `.claude/work-orders/` directory.** Follow the
project's own convention; if it has none, prompt briefs and the phase journal already cover it.

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

### Ask with AskUserQuestion, not with prose

**When you stop for input, put it in `AskUserQuestion` — never in a closing paragraph.** A question
buried in prose at the end of a long run is easy to miss and impossible to answer in one tap.

- **Batch related decisions into one call** (up to four) rather than stopping repeatedly. A phase that
  interrupts four times has not run semi-autonomously.
- **Recommended option first, labelled `(Recommended)`**, and give each option a description that states
  the trade-off rather than restating the label.
- ⭐ **Ask the question the code raised, not the question the plan expected.** The best questions in a
  real phase came from source contradicting a recorded claim — *"the schema already has this field, so do
  you want a second concept or should the code honour the first?"* — not from the plan's own
  `decisions-needed` list.
- ⚠️ **If the developer is away, an AskUserQuestion still blocks.** Send the notification too (below), so
  the question reaches a phone. The notification carries the question and a recommendation; the tool
  carries the options.
- **A decision they already made is not a question.** If a concern was raised and they chose anyway,
  proceed and say so once — re-asking reads as not listening.

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

**Run the whole phase to completion in one go, at the maximum parallelism the work honestly allows.**
Cut ONE branch for the phase, fan out, and do not stop for approval between increments. The only
reasons to stop are in §4 and at the end of this section — a blocker, a question, or an issue.

### Parallelise by FILE, and be honest about what that permits

Default to parallel. Give each concurrent agent its own **worktree** (`isolation: "worktree"`), and
**partition the work by the files it touches**, naming the boundary in every brief: *"agent B is editing
X and Y concurrently — do not touch them."* Where the project keeps work orders, that boundary belongs in
one — see §2b.

⚠️ **"Maximum parallelism" is a target, not a licence to pretend disjointness that is not there.** Two
increments editing the same file are not parallel work with a merge at the end; they are one queue with
extra steps. Measured on a real phase: five increments, four of which all edited the same 6,000-line
component and its stylesheet and its test file — only the fifth (a different subsystem entirely) could
run alongside. **Running the other four concurrently would have bought merge conflicts and, worse, the
semantic collisions a clean conflict check cannot see.**

So each round: take the largest set of increments whose file sets are disjoint, run those together, land
them, then take the next set. **A file-disjoint increment is free parallelism — take it every time.** If
nothing is disjoint, run one at a time and say so in the journal rather than faking a fan-out.

⭐ **Investigation parallelises even when implementation does not.** Read-only probes — tracing a call
path, inventorying which tests a change will break, measuring a layout budget — have no file conflicts at
all, so fan out as many as the question has independent parts. On a real phase three such probes run
before any code was written turned up four false claims in the plan. **That is the cheapest parallelism
available and it is routinely left on the table.**

### Landing an agent's work — the trap that looks like success

Implementation agents are told never to touch git, so **their work is UNCOMMITTED in the worktree.**
`git merge <worktree-branch>` therefore reports *"Already up to date"* and lands **nothing**, silently,
looking exactly like success.

Take the diff across instead, and remember `git diff` omits untracked files:

```
cd <worktree> && git status --short && git diff > /tmp/inc.patch
cd <main tree> && git apply --check /tmp/inc.patch && git apply /tmp/inc.patch
# then copy any `??` files listed by status --short — new modules and new test files
```

⚠️ **Never `git add -A` after applying.** A running local rig writes runtime data into the tree, and a
blanket add commits it. Add the paths the patch named.

### Verify the MERGED tree, not each branch

Every agent verifies its own worktree, which contains none of the others' work. **Run the full suite on
the combined tree after each landing** and reconcile the count arithmetically (baseline − retired +
added). Two green branches have put a `main` red on a real project; a clean conflict check is not
evidence.

### Per increment

**implement → land → verify (with claim audit) → `qa` → fix any gaps → commit.**

**PR, merge, deploy and the QA doc happen ONCE, at the end of the phase — not per increment.**

**`qa` is not optional and not skippable because the change "has no UI".** Nothing enters a PR that has
not been exercised in a running app. The increment's own `manual-test` field is the script — if that
field describes something a person would do, an agent can do it first. An increment whose `manual-test`
genuinely cannot be exercised is a badly-written increment, not an exemption.

Skipping it is easy to rationalise when the diff looks internal. Sync internals, merge rules and schema
changes are exactly where a green suite and a broken app coexist most comfortably.

### 🔇 Console silence while building — a hard rule, controller AND subagents

**Say NOTHING to the console between the start of the phase and its end.** Not progress, not "increment
3 landed", not a summary of what an agent reported, not a restatement of the plan. The developer is away;
intra-step narration is unread output that costs context and buries the two moments that matter — a
question, and the finish.

- **The controller is silent.** Land the work, verify, commit, move on. **The journal is the record —
  write there, not to the console.**
- **Subagents are silent too.** Put it in every brief: *report the capped digest and write detail to the
  report file; do not narrate progress.* The `report-handoff` convention already caps the reply; the
  brief is what stops an agent padding it.
- **Never echo a subagent's report back to the console.** Read it, act on it, record what mattered in the
  journal.

**The only things that may break silence, ever:**

1. An **AskUserQuestion** — see §4.
2. The **end-of-phase summary** — see below.
3. A genuine **hard stop** from the list at the end of this section.

⭐ **A tool call is not console output.** Running commands, spawning agents and editing files are all
silent by this rule; it governs prose written *to the developer*.

### Watch the context budget

Before starting any increment, check remaining context. An agent run that returns into a nearly-full
context loses the result. **Below roughly 30% remaining, stop and hand off** rather than starting
another increment — finish the one in flight, write the journal, notify, and say plainly that the run
stopped for context rather than for a problem.

Between increments, check whether anything learned invalidates a later increment's plan. A phase plan
written before the phase started is a hypothesis.

### At the phase boundary — run ALL of it, in order, without stopping to ask

Only when every increment is landed. Do not pause between these steps for approval; a phase that stops
at step 3 has delivered nothing a human can look at.

1. **Code review** across the whole phase diff. Calibrate the reviewer first — see §7. ⚠️ **Expect it to
   find real bugs in already-merged, already-green code** — on a real phase it found four, one of which
   erased a session's undo history. **Fix what it finds before the PR**, and re-verify.
2. **Full `verify` gate** over the whole repo — every stack, including ones no agent touched. Agents test
   the package they edited; nothing has yet built the rest against their work.
3. **Phase journal** — every autonomous decision, everything considered and rejected, and everything
   knowingly left wrong so a later session does not "fix" it as a bug.
4. **Commit, push, open the PR, merge it.** Follow the project's own PR policy from its `CLAUDE.md`; if
   that policy requires asking, ask — otherwise merge.
5. **Deploy to the local test rig, standing it up if it is not running.** Follow the project's own
   procedure (a `local-env.json` manifest, or the bring-up steps in its QA/rig doc). ⭐ **Then prove the
   rig is serving the build you just merged** — a version/health endpoint carrying a commit is the only
   honest check, and a stale bundle has invalidated real QA passes. **Never start a surface whose port is
   already listening.**
6. **Write the human QA document** in the project's existing QA format, as a tracked file in its `docs/`
   (plus an index line if the project has one). ⭐ **Lead it with a section naming what is genuinely
   UNCERTAIN and telling the reader to spend attention there** — a passing suite is the document's input,
   not its subject. Separate *undecided* (a judgement call you deliberately did not guess) from
   *unverified* (nobody has looked). Include anything no test can settle — visual, layout, feel — and any
   defect shipped knowingly, with its reason.
   ⚠️ **Never write "measured" for a number you estimated.** That word is a claim; one estimate dressed as
   a measurement sent a developer to inspect a non-problem on a real phase.
7. **End-phase summary to the console** — the one time prose is wanted. Keep it tight, and it MUST carry
   **two clickable links**: the **QA document** and the **rig's entry point** (the URL a human actually
   opens, not the API's health endpoint). Use `file:///` URLs for repo docs so they are ctrl-clickable.
   Then: what shipped, test counts before/after, what needs their eyes, and anything left knowingly wrong.
8. **Notify** — phase complete and ready for QA, naming the QA doc and the rig URL, so it is actionable
   from a phone without opening the console.

```
pwsh -NoProfile -File "$HOME/.claude/tools/notify.ps1" -Message "..." -Title "..."
```

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
