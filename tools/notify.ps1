#requires -Version 7
# Pushover notification wrapper (MACHINE-LEVEL — available to all sessions).
#
# Reads the Pushover app token + user/group key from ~/.claude/credentials.json
# (entry with label "Pushover": fields `token` = application API token,
# `userKey` = your user or group key). Secrets are never echoed.
#
# Usage (run via the Bash tool, not the PowerShell tool):
#   pwsh -NoProfile -File "$HOME/.claude/tools/notify.ps1" -Message "build done" [-Title "..."] [-Priority 0] [-Sound "pushover"]
#
# Priority: -2 (no notification) .. 1 (high). Emergency (2) needs retry/expire — not supported here.
param(
  [Parameter(Mandatory)][string]$Message,
  [string]$Title = 'Claude Code',
  [ValidateRange(-2, 1)][int]$Priority = 0,
  [string]$Sound,
  [string]$Label = 'Pushover'
)
$ErrorActionPreference = 'Stop'

$cred = ((Get-Content -Raw (Join-Path $env:USERPROFILE '.claude/credentials.json') | ConvertFrom-Json).credentials |
  Where-Object { $_.label -eq $Label } | Select-Object -First 1)
if (-not $cred)         { Write-Error "No '$Label' entry in credentials.json. Add one with fields: token, userKey."; exit 1 }
if (-not $cred.token)   { Write-Error "'$Label' entry is missing the 'token' (Pushover application API token)."; exit 1 }
if (-not $cred.userKey) { Write-Error "'$Label' entry is missing the 'userKey' (Pushover user/group key)."; exit 1 }

$body = @{
  token    = $cred.token
  user     = $cred.userKey
  message  = $Message
  title    = $Title
  priority = $Priority
}
if ($Sound) { $body.sound = $Sound }

try {
  $resp = Invoke-RestMethod -Method Post -Uri 'https://api.pushover.net/1/messages.json' -Body $body -TimeoutSec 20
  "SENT status=$($resp.status) request=$($resp.request)"
}
catch {
  Write-Error "Pushover send failed: $($_.Exception.Message)"
  exit 1
}
