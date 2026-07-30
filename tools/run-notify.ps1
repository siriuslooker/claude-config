#requires -Version 7
# Run a long command, then Pushover the outcome (MACHINE-LEVEL — all sessions).
#
# WHY THIS EXISTS. Long builds kept finishing without anyone being told. Two
# separate causes, and only one of them is a tooling gap:
#   1. An agent delegated the build to a SUBAGENT, which started it in the
#      background and ended its turn. Completion re-invokes that subagent, not
#      the main thread, so the notification chain broke at the boundary and the
#      main thread fell back to polling. The fix for that is behavioural — run
#      long work from the MAIN thread with the Bash tool's run_in_background,
#      which re-invokes the caller on exit. See ~/.claude/CLAUDE.md.
#   2. The human is away from the terminal entirely. No amount of harness
#      plumbing helps there — that is what this wrapper is for.
#
# So this is deliberately NOT a build-progress tracker. It does not poll, it
# does not guess whether something is "still running" (see the compile-* skills
# on why process-name checks lie), and it adds no dependency to any repo. It
# runs a command to completion and reports what happened.
#
# It lives in the profile rather than in a project's build script on purpose:
# a repo script that reads ~/.claude/credentials.json couples the repo to this
# profile, and the same wrapper then works for every project and every stack.
#
# Usage — the command is ONE string passed to -Run:
#   pwsh -NoProfile -File "$HOME/.claude/tools/run-notify.ps1" -Label "web tests" -Run 'pnpm --filter @gcsp/web test'
#   pwsh -NoProfile -File "$HOME/.claude/tools/run-notify.ps1" -Label "Android build" -Run @'
#   wsl -d Ubuntu-24.04 -u root -- bash -lc 'bash /mnt/f/.../build.sh'
#   '@
#
# ⚠️ It takes a STRING rather than trailing arguments, and that is deliberate.
# An earlier version collected the command from remaining arguments, which
# cannot work: PowerShell binds any `-flag` in the wrapped command to THIS
# script's own parameters, and a bare `--` separator is consumed by the parser
# before the script runs at all ("the parameter name '' is ambiguous"). A single
# string sidesteps both. Use a single-quoted here-string (@'...'@) when the
# command itself contains quotes, as the wsl example above does.
#
# Output is passed straight through, so the caller still sees the log and can
# still grep it. The wrapper exits with the wrapped command's exit code, so
# `&&` chaining and CI gating behave exactly as if it were not here.
param(
  [Parameter(Mandatory)][string]$Run,
  [string]$Label = 'Long-running command',
  # -2 suppresses the notification entirely — useful for testing the plumbing
  # without buzzing a phone. Failures escalate to 1 regardless (see below).
  [ValidateRange(-2, 1)][int]$Priority = 0,
  [string]$Sound
)
$ErrorActionPreference = 'Continue'

$started = Get-Date
# `pwsh -Command` rather than Invoke-Expression: a separate process means the
# wrapped command cannot alter this script's state, and $LASTEXITCODE comes
# back from the child cleanly whether it was a native exe or a cmdlet.
& pwsh -NoProfile -Command $Run
$code = $LASTEXITCODE
if ($null -eq $code) { $code = 0 }   # cmdlets and some natives leave it unset
$elapsed = (Get-Date) - $started

$mins = [Math]::Floor($elapsed.TotalMinutes)
$secs = $elapsed.Seconds
$took = if ($mins -gt 0) { "${mins}m ${secs}s" } else { "${secs}s" }

if ($code -eq 0) {
  $msg = "$Label finished OK in $took"
  $prio = $Priority
} else {
  $msg = "$Label FAILED (exit $code) after $took"
  # A failure is the case worth interrupting for. Escalate unless the caller
  # explicitly asked for silence.
  $prio = if ($Priority -eq -2) { -2 } else { 1 }
}

# The notification must never change the outcome: a Pushover outage should not
# turn a green build red, or a red one green.
try {
  $notify = Join-Path $PSScriptRoot 'notify.ps1'
  $sendArgs = @('-NoProfile', '-File', $notify, '-Message', $msg, '-Title', 'Claude Code', '-Priority', $prio)
  if ($Sound) { $sendArgs += @('-Sound', $Sound) }
  $out = & pwsh @sendArgs 2>&1
  Write-Host "[run-notify] $msg — $out"
}
catch {
  Write-Host "[run-notify] $msg — notification failed: $($_.Exception.Message)"
}

exit $code
