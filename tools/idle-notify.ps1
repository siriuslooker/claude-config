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

  BACKGROUND TASKS (added 2026-08-06). A turn that ends while a subagent or
  background shell is still running is NOT a turn you owe a reply to — the
  session will re-invoke itself when the task returns. Pushing at 5 minutes
  there is pure noise, and during a long agent run you would get one every
  time.

  The Stop payload tells us, in a supported field:

    "background_tasks": [ { id, type: "subagent", status: "running",
                            description, agent_type } ]

  So when anything is running we arm for BusySeconds (30 min) instead of
  IdleSeconds (5 min), and change the wording.

  Deliberately a LONGER WAIT, not suppression: a task that hangs is exactly
  what you want to hear about, and "never notify while busy" would hide it.
  No liveness re-check is needed — a task that finishes normally re-invokes
  the session, whose next Stop mints a new nonce and retires this watcher
  through the mismatch test that already exists. So the busy timer only fires
  when nothing came back.

  DO NOT reimplement this by scanning the temp directory. Checked 2026-08-06:
  a running agent's own <id>.output stays 0 bytes with a stale mtime for the
  entire run — it is written on completion — so file mtime reports a healthy
  agent as dead. The payload field is the only honest source.

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

  [int]$IdleSeconds = 300,

  # Used INSTEAD of IdleSeconds when the Stop payload says a background task
  # (subagent, background shell) was still running. See the note below.
  [int]$BusySeconds = 1800
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

    # The Stop payload carries `background_tasks`, e.g.
    #   [{ id, type: "subagent", status: "running", description, agent_type }]
    # This is a SUPPORTED signal from the harness — do not go hunting the temp
    # directory for it. A running agent's own transcript stays 0 bytes with a
    # stale mtime for the whole run, so file mtime is NOT liveness (checked
    # 2026-08-06); this field is.
    $busy = @()
    try { $busy = @($ctx.background_tasks | Where-Object { $_.status -eq 'running' }) } catch { $busy = @() }

    # Why a longer wait rather than no notification at all: a background task
    # that HANGS is exactly the case worth hearing about, and suppressing
    # outright converts "tell me when it's idle" into "never tell me". Note we
    # don't need to re-check liveness later — if the task finishes normally the
    # session is re-invoked, the next Stop mints a new nonce, and this watcher
    # exits on the mismatch it already tests for. So this timer only ever fires
    # when nothing came back, which is the thing worth a push.
    $wait = if ($busy.Count -gt 0) { $BusySeconds } else { $IdleSeconds }
    $what = if ($busy.Count -gt 0) {
      $first = $busy[0]
      $label = if ($first.description) { $first.description } else { $first.type }
      if ($busy.Count -gt 1) { "$label (+$($busy.Count - 1) more)" } else { $label }
    } else { $null }

    $n = [guid]::NewGuid().ToString('N')
    @{
      nonce   = $n
      cwd     = $cwd
      armedAt = (Get-Date).ToString('o')
      busy    = $busy.Count
      what    = $what
    } | ConvertTo-Json -Compress | Set-Content -Path (Get-MarkerPath $id) -Encoding utf8

    Start-Process -FilePath 'pwsh' -WindowStyle Hidden `
      -ArgumentList @(
        '-NoProfile', '-NonInteractive', '-File', $selfPath,
        '-Event', 'Watch', '-SessionId', $id, '-Nonce', $n,
        '-IdleSeconds', $wait
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

    # Two different events, so say which. Reaching this branch with a task still
    # armed means it never came back — the normal finish would have superseded
    # this watcher — so word it as a possible stall, not as "waiting on you".
    if ($state.busy -gt 0) {
      $msg = "Still running in $project after $mins min: $($state.what). May be stuck."
      $title = 'Claude may be stuck'
      $prio = 1
    } else {
      $msg = "Waiting on you in $project ($mins min, no reply)."
      $title = 'Claude is idle'
      $prio = 0
    }

    & pwsh -NoProfile -File (Join-Path $HOME '.claude/tools/notify.ps1') `
      -Message $msg -Title $title -Priority $prio | Out-Null
  }
}
