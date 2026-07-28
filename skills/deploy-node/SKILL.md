---
name: deploy-node
description: Produce a production Node/SPA build artifact, verify the bundle and its baked-in configuration, and report what would ship and where. Use when the stack manifest reports a node stack. Never pushes to an environment without explicit approval.
---

# Deploy: Node / SPA

## Hard rules

- **Producing a bundle is safe. Publishing it is not.** Build and verify freely. Do not upload to
  a CDN or bucket, run a release pipeline, or invalidate a cache without the user's explicit
  approval for that specific environment, in this session.
- Report what you did and did not do. If you stopped at the bundle, say the deploy did not happen.

## Build for production

```
NODE_ENV=production <pm> ci
NODE_ENV=production <pm> run build
```

Use the manifest's package manager. Use `ci` / `--frozen-lockfile` here even if local dev uses a
loose install — a deploy artifact built off a drifted lockfile is not reproducible. If the frozen
install fails, **stop** and report the lockfile mismatch; do not fall back to `install`.

## Verify the bundle before calling it deployable

- Output directory exists and is non-empty (`dist/`, `build/`, `.next/` — read it from the build
  output, don't assume).
- **Config baked into the bundle is the right config.** Bundlers inline `import.meta.env.*` /
  `process.env.NEXT_PUBLIC_*` at build time, so the environment present during this build is now
  permanent in these files. Report which mode was used and which env vars were set.
- **No secrets in the bundle.** Grep the output for API keys, tokens, and signing secrets. Anything
  inlined into client JS is public. This is a blocker, not a warning.
- **The base path / API origin matches the target.** A bundle built with a dev API origin
  (`localhost`) is broken in production and the failure only shows at runtime. Check `vite.config.*`
  `base`, and any hardcoded origin in the built JS.
- Report bundle sizes, and flag a total that grew unexpectedly if you have a prior number.

## Where this bundle is going

Two common shapes — establish which applies before reporting:

1. **Served by a backend from its static root** (e.g. a .NET app's `wwwroot`) — the deploy is the
   backend's deploy; this skill's job ends at producing `dist/`. The copy step belongs to the
   backend's publish. Note whether that copy is automated in CI or still manual.
2. **Hosted independently** (static host / CDN) — then the SPA is deployed separately and needs its
   API origin and CORS to be correct. Say which, because the answer changes what "deployed" means.

## Return this payload

```markdown
## deploy-node: <ARTIFACT_READY | FAIL | BLOCKED>

- **Root:** <path>  •  **Package manager:** <pm>  •  **Mode:** production
- **Artifact:** <dist path>  •  **Total size:** <KB>  •  **Largest chunk:** <file, KB>
- **Baked-in config:** <env vars that were set, and the resulting API origin / base path>
- **Delivery shape:** <served by backend static root | independently hosted>
- **Published to an environment:** **NO** — artifact only. <or: yes, <env>, approved by user at <when>>

### Blockers
- <secrets in bundle, wrong API origin, lockfile mismatch — or "none">

### To actually deploy
<the exact copy/upload/pipeline step, listed for the user to approve and run>
```
