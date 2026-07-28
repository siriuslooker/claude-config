---
name: test-node
description: Run Node/TypeScript tests (Vitest, Jest, Mocha, node:test) non-interactively, report pass/fail counts and each failure's assertion diff, and report honestly when no test harness exists. Use when the stack manifest reports a node stack.
---

# Test: Node / TypeScript

Mechanical. You run tests and report what happened. **Never edit tests or source to make them pass,
and never report a pass you did not observe.**

## If there is no test harness

Common and legitimate — the only wrong response is a green report. Confirm before claiming: check
`package.json` for a `test` script, for `vitest`/`jest`/`mocha`/`@playwright/test` in
`devDependencies`, and glob for `**/*.{test,spec}.{ts,tsx,js,jsx}` outside `node_modules/`. Then
return `NO_HARNESS` listing what you checked. Do not scaffold a harness unless asked.

Watch for a placeholder `"test": "echo \"Error: no test specified\" && exit 1"` — that is
**no harness**, not a failing suite.

## Run — non-interactive is mandatory

Watch mode is the default for Vitest and will hang the session. Always force a single run:

| Runner | Command |
|---|---|
| Vitest | `npx vitest run --reporter=verbose` |
| Jest | `npx jest --ci --colors=false` |
| Mocha | `npx mocha --reporter spec` |
| node:test | `node --test` |
| Playwright | `npx playwright test --reporter=list` |

Prefer the `test` script if it already runs once (`vitest run`, `jest --ci`). If the script is bare
`vitest` or `jest --watch`, bypass it and call the runner directly with the flags above — and say
in the payload that you did, since it is a `package.json` smell worth fixing.

Set `CI=true` in the environment; most runners key their non-interactive behavior off it.

Coverage, if asked: `npx vitest run --coverage` / `npx jest --coverage`. If the coverage provider
is not installed, report that rather than skipping silently.

Long output goes to `.claude/stack-ops/test-node.log`; cite the path.

## Reading the result

- **Failed assertions** — report the test name (with its `describe` path), the expected/received
  diff trimmed to the meaningful lines, and `file:line`.
- **Suite-level failure** (import error, config error) — the tests never ran. Report `FAIL` with
  `stage: collection` and the unresolved specifier or config error. Not a test failure.
- **Zero tests found** — report `NO_TESTS_DISCOVERED`, not a pass. Usually an `include` glob that
  doesn't match where the tests actually live.
- **Skipped / todo** — surface counts and names; a mostly-skipped suite is not green.

## Return this payload

```markdown
## test-node: <OK | FAIL | NO_HARNESS | NO_TESTS_DISCOVERED>

- **Root:** <path>  •  **Runner:** <vitest|jest|mocha|node:test|playwright>
- **Invoked:** <exact command>  •  **Via:** <package script | direct (script was watch-mode)>
- **Files:** <n>  •  **Total:** <n>  •  **Passed:** <n>  •  **Failed:** <n>  •  **Skipped:** <n>
- **Elapsed:** <seconds>
- **Coverage:** <line % | not collected>
- **Log:** <path, if written>

### Failures
- `<describe > test name>` — <assertion gist>
  - `<file>:<line>`
  - expected `<x>` / received `<y>`

### Notes
<e.g. "package.json `test` is a placeholder; no runner in devDependencies">
```

Nothing else.
