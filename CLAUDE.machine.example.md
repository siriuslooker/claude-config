# Machine-specific facts — EXAMPLE / TEMPLATE

**This file is the tracked template. The real one, `CLAUDE.machine.md`, is gitignored and never
leaves the machine it describes.**

On a fresh clone:

```bash
cp ~/.claude/CLAUDE.machine.example.md ~/.claude/CLAUDE.machine.md
```

then delete the placeholder section below and write your own. `CLAUDE.md` imports
`@~/.claude/CLAUDE.machine.md`, so **the copy must exist** — Claude Code documents the `@import`
syntax but not what a missing target does, and an empty-but-present file is the safe state.

Everything in the real file is **scoped to a named host** — check which machine you are on before
relying on an entry, and never generalise one host's quirk into a rule:

```
hostname          # or $env:COMPUTERNAME on Windows
```

**Why it is no longer tracked.** It accumulated hostnames, LAN addresses, device serials, drive
layouts, installed-software inventories and named internal services — a description of specific
machines, which does not belong in a repo that may be read by anyone. Keep it that way: a fact true
everywhere belongs in `CLAUDE.md` under "General cautions"; a fact true of one host belongs here and
stays here.

**Adding a machine:** append a `## <HOSTNAME>` section. Keep entries to things that are genuinely
local — hardware, what's installed, drive layout, network reach. Record the *diagnosis* alongside the
fact when a quirk cost you time; the value of this file is the traps, not the inventory.

---

## <HOSTNAME>

*Replace this whole section. The headings below are the ones that have earned their place — drop any
that do not apply, and add whatever the host needs.*

- **OS and shells:** which OS, which shell is primary, which others exist and what syntax they take.
- **Drive layout:** where checkouts live, if not under the user profile.
- **Databases:** engines installed, instance names, how to authenticate, notable local databases.
  Record what is *not* installed too — an absent LocalDB is as useful to know as a present one.
- **Network reach:** VPNs, whether the VPN-gated tooling in `CLAUDE.md` works here, LAN hosts this
  machine drives.
- **CLIs installed:** and *how*, when the package name differs from the command name.
- **Devices attached:** phones, tablets, simulators — serial/UDID, screen geometry, which MCP server
  drives them.
- **Remote hosts driven from here:** ssh alias, address, environment fixes a non-interactive shell
  needs, and any sleep/power quirks.
- **Security software:** anything that scans, blocks or throttles builds. Record how you *measured*
  it, not just the conclusion.
- **Known traps:** the entries that pay for the file. A tool that reports success while doing nothing,
  a PATH that looks fine and isn't, a check that cannot detect the thing it claims to check.
