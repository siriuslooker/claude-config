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

## 2b. Work orders — the durable form of a brief

⭐ **A brief passed as prompt text does its job and then ceases to exist.** Where a project keeps work
orders (`.claude/work-orders/`), write one per parallel unit and pass the agent its path instead of a
wall of prompt — a numbered tracked file can be cited from a source comment months later, read by the
next agent to touch that code, and it is where the agent appends its own report.

**They pair directly with the fan-out in §6: one work order per worktree**, and the file is where that
worktree boundary is written down.

🔴 **The format, the four parts that carry the weight, and how an agent writes its `## Report` are in the
`work-order` skill. Load it rather than reproducing them here** — it is referenced by the agents too, so
an agent appending a report can reach the convention without loading this whole process.

⚠️ **Do not introduce work orders into a project that has no such directory.** Prompt briefs plus the
phase journal already cover it there.

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

### Parallelise by REGION, not by file

Default to parallel, and **default hard**. Give each concurrent agent its own **worktree**
(`isolation: "worktree"`), and **partition the work by the regions it touches**, naming the boundary in
every brief: *"agent B is editing X and Y concurrently — do not touch them."* Where the project keeps work
orders, that boundary belongs in one — see §2b.

🔴 **A shared file is NOT a reason to serialize.** Two increments editing distinct regions of one large
component are ordinary parallel work, and taking their diffs across merges fine. Big components are
exactly where the work piles up, so "same file → one at a time" serializes almost every real phase — the
wrong default, and it costs most of the point of running a phase unattended.

**So partition the file and run them together.** A region partition is a table: increment, the symbols and
line ranges it owns in each shared file, and what it owns outright. Put the *whole* table in *every*
brief, not just each agent's own row — an agent that cannot see its neighbours' territory cannot avoid it.

⚠️ **What actually breaks a concurrent round is not co-editing, it is churn.** Make these non-negotiable
in every brief:

- **No refactoring shared helpers. No reordering imports. No reformatting, re-indenting or re-wrapping any
  region you are not changing.** A cosmetic reflow of a neighbour's region is a semantic collision a clean
  conflict check cannot see.
- **Everyone adding tests to one test file adds them inside their own `describe` block**, at their own
  region — nobody restructures the file or touches its shared helpers.
- **Nobody touches shared config, design tokens, or lockfiles.**
- **Name the specific cross-increment interactions**: two agents extending the same UI affordance, two
  timing constants that must stay clear of each other, two edits near one shared call site. Say which
  agent owns which, and that it gets verified on the merged tree.
- **An agent that genuinely needs another's region STOPS and reports.** That is a real finding about the
  partition — re-plan rather than merge a guess.

**Reserve serialization for real dependencies:** B needs A's output to exist, or B's change is meaningless
until A's has landed. ⚠️ **Check that second one honestly — a dependency on the user-visible OUTCOME is not
a dependency on the code.** If both land in the same merge they can be built at the same time; say so in
the brief, and tell the agent that its neighbour's absence from its worktree is expected rather than a
broken checkout.

🔴 **Never predict a file set — read it.** Two increments were serialized on a real phase because their
briefs *said* both touched the big component. One turned out to live entirely in a different module and
the other had deliberately stayed out of it: **they were disjoint, and the round was serialized for
nothing.** If you are about to serialize, open the files first.

⭐ **Investigation parallelises even when implementation does not.** Read-only probes — tracing a call
path, inventorying which tests a change will break, measuring a layout budget — have no file conflicts at
all, so fan out as many as the question has independent parts. On a real phase, probes run before any code
was written turned up four false claims in the plan. **That is the cheapest parallelism available and it
is routinely left on the table.**

🔴 **Then gate on the MERGED tree** — see below. Concurrency's cost is paid there, not at dispatch, and
that check is what makes an aggressive fan-out safe rather than lucky.

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

**In a concurrent round the shape is the same, just wider:** dispatch every increment's `implement` at
once, then **land them one at a time, running the full suite after each landing** so a break is attributed
to the diff that caused it rather than to the pile. Then `verify` with a claim audit over the merged
result, and `qa` the merged app — a per-worktree QA pass proves nothing about what ships, because no
worktree contains the others' work.

⚠️ **The claim audit gets MORE important as the fan-out widens, not less.** Each agent reports a count
measured in its own worktree, and none of those numbers is the suite total. **Reconcile arithmetically on
the merged tree and never adopt an agent's figure as the phase's.**

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
