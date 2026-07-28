---
name: deploy-netcore
description: Produce a deployable .NET publish artifact (dotnet publish), apply or script EF Core migrations, and report exactly what would ship and where. Use when the stack manifest reports a netcore stack. Never pushes to an environment without explicit approval.
---

# Deploy: .NET

## Hard rules

- **Producing an artifact is safe. Pushing it is not.** Publish, verify, and report freely. Do not
  copy to a server, run a release pipeline, restart a site, or touch a shared environment without
  the user's explicit approval **for that environment, in this session**. Approval for staging is
  not approval for production.
- **Never apply a migration to a shared or production database on your own initiative.** Generate
  the script and show it. A destructive migration against a shared DB is not recoverable by a retry.
- Report what you did and did not do. If you stopped at the artifact, say the deploy did not happen.

## Build the artifact

```
dotnet publish <proj> -c Release -o <out> --nologo
```

Default `<out>` to `.claude/stack-ops/publish/<project>`. Add `-r <rid> --self-contained false`
only if the target requires a RID.

**If this repo also has a `node` stack whose bundle the .NET app serves** (a `wwwroot` SPA), the SPA
must be built and copied in **before** publish, or you will ship an empty or stale `wwwroot`:

1. Run `compile-node` first (its `build`, in production mode).
2. Copy the SPA's `dist/` into the API project's `wwwroot/`.
3. Then publish.

Check whether the `.csproj` already does this via an MSBuild target. If it does, don't duplicate it —
verify it ran by listing the published `wwwroot`. If it doesn't, note that as a CI gap: the copy
step being manual is exactly how a stale bundle reaches production.

## Verify the artifact before calling it deployable

- The entry assembly and `<app>.runtimeconfig.json` exist in the output.
- `appsettings.json` is present, and `appsettings.Development.json` is **not** the effective config.
- **No secrets in the artifact.** Grep the published `appsettings*.json` for connection strings,
  passwords, and signing keys. A dev secret shipped to production is a real finding — report it as
  a blocker, not a warning.
- The published `wwwroot` contains the current SPA bundle (compare a hashed filename against the
  `dist/` you just built) if this app serves one.

## Migrations

```
dotnet ef migrations script --idempotent --project <proj> -o <out>/migrate.sql
```

Always produce the idempotent script — it is reviewable and re-runnable. Report the pending
migration names and whether the script contains destructive statements (`DROP`, `ALTER COLUMN`
narrowing a type, `DELETE`). If the app applies migrations on startup (`Database.Migrate()` in
`Program.cs`), **say so prominently** — deploying the app *is* the migration, which changes the
approval question.

## Return this payload

```markdown
## deploy-netcore: <ARTIFACT_READY | FAIL | BLOCKED>

- **Project:** <path>  •  **Configuration:** Release
- **Artifact:** <out path>  •  **Size:** <MB>  •  **Files:** <n>
- **SPA bundle included:** <yes (built this run / by MSBuild target) | n/a | STALE — see notes>
- **Deployed to an environment:** **NO** — artifact only. <or: yes, <env>, approved by user at <when>>

### Migrations
- **Pending:** <names, or "none">
- **Script:** <path>
- **Destructive statements:** <yes — list them | none>
- **Applied on app startup:** <yes — deploying the app applies them | no>

### Blockers
- <secrets in artifact, missing config, etc. — or "none">

### To actually deploy
<the exact commands or pipeline step, listed for the user to approve and run>
```
