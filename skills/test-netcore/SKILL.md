---
name: test-netcore
description: Run .NET tests with the dotnet CLI (xUnit/NUnit/MSTest), report pass/fail counts and each failure's assertion, and report honestly when no test project exists. Use when the stack manifest reports a netcore stack.
---

# Test: .NET

Mechanical. You run tests and report what happened. **Never edit tests or source to make them pass,
and never report a pass you did not observe.**

## If there are no test projects

This is a common and legitimate outcome, and the only wrong response is a green report. Confirm it
before claiming it — glob for `**/*.Test*.csproj`, `**/*.Spec*.csproj`, and grep project files for
`xunit` / `nunit` / `MSTest`. Then return `NO_HARNESS` with the projects you checked and stop.
Do not scaffold a test project unless the caller explicitly asked for one.

## Run

```
dotnet test <entry> --nologo -v q --logger "trx;LogFileName=test-results.trx"
```

- `<entry>` is the solution, so every test project runs. Target a single project only if asked.
- Add `--no-build` **only** when a compile step in this same run already succeeded — it saves a
  rebuild. Otherwise let it build; a stale binary producing a green run is worse than a slow one.
- Filter with `--filter "FullyQualifiedName~<pattern>"` when asked to narrow.
- Coverage, if asked: `--collect:"XPlat Code Coverage"` (needs `coverlet.collector` in the test
  project — if it is missing, report that instead of silently skipping).

Long output goes to `.claude/stack-ops/test-netcore.log`; cite the path.

## Reading the result

Distinguish these three, because they mean different things:

- **Failed assertions** — real test failures. Report the test's fully-qualified name, the
  assertion message, and the top repo frame from the stack trace (skip framework frames).
- **Build failure** — the tests never ran. Report `FAIL` with `stage: build` and hand the compiler
  errors back; do not describe this as a test failure.
- **Zero tests discovered** despite a test project existing — usually a missing test SDK/adapter
  package or a `[Fact]`-less class. Report it as `NO_TESTS_DISCOVERED`, not as a pass. `dotnet test`
  can exit 0 here, so check the discovered count, not just the exit code.

Also surface **skipped** tests with their skip reasons — a suite that is 40% skipped is not the
same as a green suite.

## Return this payload

```markdown
## test-netcore: <OK | FAIL | NO_HARNESS | NO_TESTS_DISCOVERED>

- **Entry:** <path>  •  **Built:** <yes | reused prior build>
- **Total:** <n>  •  **Passed:** <n>  •  **Failed:** <n>  •  **Skipped:** <n>
- **Elapsed:** <seconds>
- **Coverage:** <line % | not collected>
- **Log:** <path, if written>

### Failures
- `<Namespace.Class.Test>` — <assertion message>
  - `<file>:<line>` (first repo frame)

### Skipped
- `<Namespace.Class.Test>` — <reason>

### Notes
<e.g. "no test projects; checked src/**/*.csproj — none reference xunit/nunit/MSTest">
```

Nothing else.
