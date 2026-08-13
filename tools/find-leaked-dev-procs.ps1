<#
.SYNOPSIS
  Find (and optionally kill) leaked local development processes — dev servers, watchers,
  test runners and MCP servers left behind by earlier sessions.

.DESCRIPTION
  Long-lived dev processes accumulate silently. Measured on one Windows dev box, 2026-08-07: 68 node
  processes, of which 54 were leaked — eight duplicate backend watchers from one day, six vite
  servers from a project not being worked on, twelve MCP servers from three sessions two days
  earlier, and three test runs that hung and never exited.

  That matters beyond tidiness: fourteen of them were FILE WATCHERS (`tsx watch`, `vite`) holding
  recursive watches over the same trees and waking on every change. It is a better explanation for
  a machine feeling heavy at idle than most of the things one would otherwise go tuning.

  REPORT BY DEFAULT, KILL ONLY WHEN ASKED. Two safety properties, both learned by nearly getting
  them wrong:

  1. A process that is LISTENING is kept, and so is its whole family — ancestors AND descendants.
     On 2026-08-07 the live backend's parent watcher was itself two days old and looked exactly
     like the leaked ones beside it; a kill-by-age-and-appearance sweep would have taken the live
     server down with it. The socket is the ground truth; walk outward from it.

  2. Killing is limited to an ALLOWLIST of recognised dev-tool command lines. An age-plus-no-socket
     heuristic would match the agent harness's own node processes and kill the session running the
     sweep. Deciding what we are willing to kill is safer than trying to enumerate what we are not.

  Never key liveness off a process NAME: `pgrep -f <pattern>` matches its own invoking shell, and
  any other process carrying the string. Ports, parentage and command lines are the honest signals.

.PARAMETER MinAgeHours
  Only treat a process as a candidate once it is this old. Default 2. Guards against catching a
  dev server that is mid-startup and has not bound its port yet.

.PARAMETER Kill
  Actually terminate the candidates. Without it this only reports.

.PARAMETER IncludePids
  Extra PIDs to force into the candidate list (something you have identified by hand). Still
  refused if the PID is in the keep set.

.PARAMETER ExcludePids
  PIDs to protect regardless of how they look.

.EXAMPLE
  pwsh -NoProfile -File ~/.claude/tools/find-leaked-dev-procs.ps1
  # report only

.EXAMPLE
  pwsh -NoProfile -File ~/.claude/tools/find-leaked-dev-procs.ps1 -Kill -MinAgeHours 6
#>
[CmdletBinding()]
param(
  [int] $MinAgeHours = 2,
  [switch] $Kill,
  [switch] $IncludeMcpServers,
  [int[]] $IncludePids = @(),
  [int[]] $ExcludePids = @()
)

$ErrorActionPreference = 'Stop'

# Runtimes worth sweeping. Deliberately narrow: this is about JS dev tooling, which is what leaks.
$runtimeNames = @('node.exe')

# ---------------------------------------------------------------------------
# The kill allowlist. A command line must match one of these to be killable.
# Anything unrecognised is REPORTED as unknown and left alone — the agent
# harness's own node processes live in that gap on purpose.
# ---------------------------------------------------------------------------
$killable = [ordered]@{
  'vite dev server'   = '[\\/]vite[\\/]bin[\\/]vite\.js'
  'tsx watch'         = '[\\/]tsx[\\/]dist[\\/]cli\.mjs.*\bwatch\b'
  'jest run'          = '[\\/]jest[\\/]bin[\\/]jest\.js'
  'metro / RN cli'    = '[\\/]react-native[\\/]cli'
  'pnpm script wrap'  = 'pnpm[\\/.](mjs|cjs).*--filter|pnpm[\\/]bin[\\/]pnpm'
  'next dev server'   = '[\\/]next[\\/]dist[\\/]bin[\\/]next'
  'nodemon'           = '[\\/]nodemon[\\/]bin[\\/]nodemon'
}

# ---------------------------------------------------------------------------
# MCP servers are held back behind an explicit flag, and the reason is not
# caution for its own sake: a LIVE session's MCP servers are indistinguishable
# from leaked ones by every signal this script has. They speak over stdio, so
# they hold no socket and the listener-family walk cannot see them; their
# parent is a `cmd.exe` that stays alive either way. Age does not separate them
# either — a working session can easily run longer than any threshold worth
# setting, and the leaked ones found on 2026-08-07 had live `cmd.exe` parents
# just like healthy ones.
#
# Caught by testing this script during a live session: six of its own MCP
# servers were sitting at 0.1h, spared only for being new. Two hours later a
# default sweep would have killed the tools out from under the session running
# it.
#
# They are also the cheap leak — no file watching, unlike the dev servers
# above, which are what actually make a machine feel heavy. So the default
# sweep takes the expensive class and leaves this one to a deliberate ask,
# ideally when no session is running.
# ---------------------------------------------------------------------------
$mcpKillable = [ordered]@{
  'npx launcher'      = 'npx-cli\.js'
  'npx cached tool'   = '_npx[\\/]'
}
if ($IncludeMcpServers) { foreach ($k in $mcpKillable.Keys) { $killable[$k] = $mcpKillable[$k] } }

# ---------------------------------------------------------------------------
# Snapshot processes and listening sockets
# ---------------------------------------------------------------------------
$procs = @()
foreach ($n in $runtimeNames) {
  $procs += Get-CimInstance Win32_Process -Filter "Name='$n'" -ErrorAction SilentlyContinue
}
if (-not $procs) { Write-Host "No $($runtimeNames -join '/') processes running."; return }

$byId = @{}
foreach ($p in $procs) { $byId[[int]$p.ProcessId] = $p }

$portsByPid = @{}
foreach ($c in (Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue)) {
  $k = [int]$c.OwningProcess
  if (-not $portsByPid.ContainsKey($k)) { $portsByPid[$k] = New-Object System.Collections.Generic.HashSet[int] }
  [void]$portsByPid[$k].Add([int]$c.LocalPort)
}

# ---------------------------------------------------------------------------
# Keep set: everything listening, plus its ancestors and descendants.
#
# The ancestor walk is the load-bearing half. A watcher that spawned the live
# server may itself be days old and indistinguishable from its leaked siblings.
# ---------------------------------------------------------------------------
$keep = New-Object System.Collections.Generic.HashSet[int]

$serving = @($procs | Where-Object { $portsByPid.ContainsKey([int]$_.ProcessId) } | ForEach-Object { [int]$_.ProcessId })
foreach ($pid_ in $serving) {
  $cur = $pid_
  while ($cur -and $byId.ContainsKey([int]$cur)) {
    [void]$keep.Add([int]$cur)
    $cur = [int]$byId[[int]$cur].ParentProcessId
  }
}
# Protect this process's own ancestry too, so a sweep can never kill the shell running it.
$cur = $PID
while ($cur -and $byId.ContainsKey([int]$cur)) { [void]$keep.Add([int]$cur); $cur = [int]$byId[[int]$cur].ParentProcessId }

foreach ($e in $ExcludePids) { [void]$keep.Add([int]$e) }

# Descend: children of anything kept are kept (Metro's transform workers, a runner's workers).
$changed = $true
while ($changed) {
  $changed = $false
  foreach ($p in $procs) {
    if ($keep.Contains([int]$p.ParentProcessId) -and -not $keep.Contains([int]$p.ProcessId)) {
      [void]$keep.Add([int]$p.ProcessId); $changed = $true
    }
  }
}

# ---------------------------------------------------------------------------
# Classify
# ---------------------------------------------------------------------------
$now = Get-Date
$rows = foreach ($p in $procs) {
  $id    = [int]$p.ProcessId
  $start = $p.CreationDate
  $age   = if ($start) { ($now - $start).TotalHours } else { 0 }
  $cmd   = if ($p.CommandLine) { $p.CommandLine } else { '' }

  $kind = 'unknown'
  foreach ($k in $killable.Keys) { if ($cmd -match $killable[$k]) { $kind = $k; break } }

  $parentAlive = $byId.ContainsKey([int]$p.ParentProcessId) -or
                 [bool](Get-Process -Id $p.ParentProcessId -ErrorAction SilentlyContinue)

  $ports = if ($portsByPid.ContainsKey($id)) { ($portsByPid[$id] | Sort-Object) -join ',' } else { '' }

  $verdict =
    if ($keep.Contains($id))              { if ($ports) { 'SERVING' } else { 'KEEP (family of a listener)' } }
    elseif ($kind -eq 'unknown')          { 'LEAVE (unrecognised)' }
    elseif ($age -lt $MinAgeHours)        { 'LEAVE (too new)' }
    elseif ($IncludePids -contains $id)   { 'CANDIDATE (named)' }
    else                                  { 'CANDIDATE' }

  [pscustomobject]@{
    PID         = $id
    AgeHours    = [math]::Round($age, 1)
    Ports       = $ports
    ParentAlive = $parentAlive
    Kind        = $kind
    Verdict     = $verdict
    Cmd         = if ($cmd.Length -gt 110) { $cmd.Substring(0, 110) } else { $cmd }
  }
}

$candidates = @($rows | Where-Object { $_.Verdict -like 'CANDIDATE*' })

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host ("{0} process(es); {1} serving, {2} kept as family, {3} candidate(s) for cleanup" -f `
  $rows.Count,
  @($rows | Where-Object Verdict -eq 'SERVING').Count,
  @($rows | Where-Object { $_.Verdict -like 'KEEP*' }).Count,
  $candidates.Count)
Write-Host ""

$rows | Sort-Object Verdict, AgeHours -Descending |
  Format-Table -AutoSize PID, AgeHours, Ports, Kind, Verdict

if ($candidates.Count -eq 0) { Write-Host "Nothing to clean up."; return }

Write-Host "Candidates, grouped:"
$candidates | Group-Object Kind | Sort-Object Count -Descending | ForEach-Object {
  Write-Host ("  {0,-20} x{1,-4} oldest {2}h" -f $_.Name, $_.Count, (($_.Group | Measure-Object AgeHours -Maximum).Maximum))
}
Write-Host ""

if (-not $Kill) {
  Write-Host "Report only. Re-run with -Kill to terminate the $($candidates.Count) candidate(s)."
  return
}

# ---------------------------------------------------------------------------
# Kill, then verify every previously-listening port is STILL listening.
# A sweep that quietly took a live server down would be worse than the leak.
# ---------------------------------------------------------------------------
$portsBefore = @{}
foreach ($k in $portsByPid.Keys) { foreach ($v in $portsByPid[$k]) { $portsBefore[$v] = $k } }

foreach ($c in $candidates) { Stop-Process -Id $c.PID -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 3

Write-Host "Killed $($candidates.Count). Verifying the ports that were listening before:"
$broke = 0
foreach ($port in ($portsBefore.Keys | Sort-Object)) {
  $still = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue
  if ($still) { Write-Host ("  {0,-7} still UP (pid {1})" -f $port, $still[0].OwningProcess) }
  else        { Write-Host ("  {0,-7} *** WENT DOWN ***" -f $port); $broke++ }
}
if ($broke -gt 0) {
  Write-Warning "$broke port(s) stopped listening. That is a bug in this script's keep set, not an expected outcome — restart them and report it."
  exit 1
}
Write-Host "All previously-listening ports survived."
