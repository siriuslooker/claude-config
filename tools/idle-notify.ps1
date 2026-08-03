<#
.SYNOPSIS
  Pushover you when a Claude session finishes a turn and you don't reply.

.DESCRIPTION
  Wired to three hooks in ~/.claude/settings.json so it applies to EVERY
  session on this machine, not one project:

    Stop            -> -Event Stop     (arm a timer)
    UserPromptSubmit-> -Event Cancel   (you replied; disarm)
    SessionEnd      -> -Event Cancel   (session gone; nothing to wait for)

  How it works. On Stop we write a marker file holding a fresh nonce, then
  launch a DETACHED watcher that sleeps IdleSeconds and re-reads the marker.
  If the marker is gone (you replied, or the session ended) it exits silent.
  If the nonce no longer matches, a NEWER turn superseded this one and the
  newer watcher owns the notification — so this one exits too. That nonce
  check is what stops a burst of quick turns queueing up a burst of pushes:
  exactly one notification per genuinely-idle turn.

  The watcher must be detached. Sleeping inside the hook would block the
  session for five minutes, and the harness would be right to kill it.

.NOTES
  Marker dir ~/.claude/.idle-watch/ is excluded by the profile's allowlist
  .gitignore — do not add it.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidateSet('Stop', 'Cancel', 'Watch')]
  [string]$Event,

  # -Watch only: supplied by the detached process we spawn.
  [string]$SessionId,
  [string]$Nonce,

  [int]$IdleSeconds = 300
)

$ErrorActionPreference = 'Stop'
$watchDir = Join-Path $HOME '.claude/.idle-watch'
$selfPath = $PSCommandPath

function Get-HookContext {
  # Hooks receive a JSON object on stdin: session_id, cwd, transcript_path,
  # hook_event_name. Read defensively — a hook that throws is a hook that
  # breaks every session on the machine.
  try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return $raw | ConvertFrom-Json
  } catch { return $null }
}

function Get-MarkerPath([string]$id) {
  $safe = ($id -replace '[^A-Za-z0-9_-]', '_')
  if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'unknown' }
  Join-Path $watchDir "$safe.json"
}

switch ($Event) {

  'Stop' {
    $ctx = Get-HookContext
    $id = if ($ctx.session_id) { $ctx.session_id } else { 'unknown' }
    $cwd = if ($ctx.cwd) { $ctx.cwd } else { (Get-Location).Path }

    if (-not (Test-Path $watchDir)) { New-Item -ItemType Directory -Force $watchDir | Out-Null }

    $n = [guid]::NewGuid().ToString('N')
    @{ nonce = $n; cwd = $cwd; armedAt = (Get-Date).ToString('o') } |
      ConvertTo-Json -Compress | Set-Content -Path (Get-MarkerPath $id) -Encoding utf8

    Start-Process -FilePath 'pwsh' -WindowStyle Hidden `
      -ArgumentList @(
        '-NoProfile', '-NonInteractive', '-File', $selfPath,
        '-Event', 'Watch', '-SessionId', $id, '-Nonce', $n,
        '-IdleSeconds', $IdleSeconds
      ) | Out-Null
  }

  'Cancel' {
    # Fires on your next prompt and on session end. Either way nobody is
    # waiting on a reply, so drop the marker and the watcher self-cancels.
    $ctx = Get-HookContext
    $id = if ($ctx.session_id) { $ctx.session_id } else { 'unknown' }
    Remove-Item -Path (Get-MarkerPath $id) -Force -ErrorAction SilentlyContinue
  }

  'Watch' {
    Start-Sleep -Seconds $IdleSeconds

    $marker = Get-MarkerPath $SessionId
    if (-not (Test-Path $marker)) { return }   # replied, or session ended

    try { $state = Get-Content $marker -Raw | ConvertFrom-Json } catch { return }
    if ($state.nonce -ne $Nonce) { return }    # a newer turn owns this now

    # Claim it before sending, so a race can never double-send.
    Remove-Item -Path $marker -Force -ErrorAction SilentlyContinue

    $project = try { Split-Path -Leaf $state.cwd } catch { 'a session' }
    $mins = [math]::Round($IdleSeconds / 60)

    & pwsh -NoProfile -File (Join-Path $HOME '.claude/tools/notify.ps1') `
      -Message "Waiting on you in $project ($mins min, no reply)." `
      -Title 'Claude is idle' -Priority 0 | Out-Null
  }
}
