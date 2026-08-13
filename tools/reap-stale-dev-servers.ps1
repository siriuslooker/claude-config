<#
.SYNOPSIS
  Kill long-lived development servers left behind by earlier sessions.

.DESCRIPTION
  Metro (React Native), Vite and their worker pools run until something stops them.
  They are launched through a `cmd.exe` that exits immediately, so nothing owns them:
  ending a Claude session, closing a terminal, or a crash all leave them running. They
  then sit for days.

  Measured on one Windows dev box, 2026-08-11: 22 orphaned node processes, the oldest 127
  hours (five days), holding 2.7 GB. They arrived in clusters of six to eight, which is the
  signature of one Metro plus its jest-worker transform pool. That machine also ran a
  corporate on-access antivirus whose CPU cost tracks the NUMBER OF PROCESSES it has to
  watch rather than file volume, so a pile of idle bundlers is not free even when they are
  doing nothing.

  ## Why this runs at SessionStart and not SessionEnd

  A dev server you deliberately left running is one you may still want. Reaping at
  SessionEnd would kill the Metro you are about to come back to, which is worse than the
  problem. Reaping at SessionStart with an age threshold cannot do that: anything older
  than the threshold belongs to a session that is already over.

  ## What it will not touch

  - Anything younger than -MaxAgeHours (default 12).
  - Anything in the current process's ancestor chain.
  - Any node process whose command line does not match a known dev-server signature.
    An unrecognised node process is left alone — this is deliberately a allowlist of
    things known to be safe to kill, not a denylist of things to spare.

  Being wrong in the "left it running" direction costs some memory. Being wrong in the
  "killed something live" direction costs someone's work. So it only kills what it can
  name.

.PARAMETER MaxAgeHours
  Only consider processes older than this. Default 12.

.PARAMETER WhatIf
  Report what would be killed and kill nothing.
#>
[CmdletBinding()]
param(
  [int]$MaxAgeHours = 12,
  [switch]$WhatIf
)

$ErrorActionPreference = 'SilentlyContinue'

# Known long-lived dev servers and their worker pools. Matched against the full command
# line. Keep this list explicit: a broad pattern like "node" would eventually kill the
# agent harness itself, and the failure would look like a random crash.
$signatures = @(
  'react-native[\\/]cli\.js',        # Metro, launched by the RN CLI
  'metro[\\/]',                      # Metro internals
  '@expo[\\/]cli',                   # expo start
  'jest-worker',                     # Metro's transform pool, and jest's
  'vite[\\/]bin[\\/]vite\.js',       # Vite dev server
  'vitest[\\/].*worker'              # stray vitest workers
)
$pattern = ($signatures -join '|')

# Never kill anything we are running inside of.
$ancestors = @()
$node = Get-CimInstance Win32_Process -Filter "ProcessId=$PID"
while ($node) {
  $ancestors += $node.ProcessId
  $node = Get-CimInstance Win32_Process -Filter "ProcessId=$($node.ParentProcessId)"
}

$cutoff = (Get-Date).AddHours(-$MaxAgeHours)

$candidates = Get-CimInstance Win32_Process -Filter "Name='node.exe'" | ForEach-Object {
  $proc = Get-Process -Id $_.ProcessId
  if (-not $proc) { return }
  if ($proc.StartTime -ge $cutoff) { return }
  if ($ancestors -contains $_.ProcessId) { return }
  if (-not $_.CommandLine) { return }
  if ($_.CommandLine -notmatch $pattern) { return }
  [pscustomobject]@{
    Id      = $_.ProcessId
    AgeH    = [math]::Round(((Get-Date) - $proc.StartTime).TotalHours, 1)
    MB      = [math]::Round($proc.WorkingSet64 / 1MB)
    Cmd     = $_.CommandLine
  }
}

if (-not $candidates) {
  Write-Output "reap-stale-dev-servers: nothing older than ${MaxAgeHours}h to reap."
  exit 0
}

$count = @($candidates).Count
$mb = [math]::Round((@($candidates) | Measure-Object MB -Sum).Sum)

if ($WhatIf) {
  Write-Output "reap-stale-dev-servers: WOULD reap $count process(es), ~${mb} MB:"
  foreach ($c in $candidates) {
    $short = if ($c.Cmd.Length -gt 100) { $c.Cmd.Substring(0, 100) } else { $c.Cmd }
    Write-Output ("  pid {0}  {1}h  {2}MB  {3}" -f $c.Id, $c.AgeH, $c.MB, $short)
  }
  exit 0
}

# Kill children before parents where both are in the list, so a supervisor does not
# respawn a worker we just removed.
foreach ($c in ($candidates | Sort-Object AgeH)) {
  try { Stop-Process -Id $c.Id -Force -ErrorAction Stop } catch { }
}

Write-Output "reap-stale-dev-servers: reaped $count stale dev-server process(es), ~${mb} MB freed (older than ${MaxAgeHours}h)."
