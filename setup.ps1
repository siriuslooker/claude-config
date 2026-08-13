#requires -Version 5.1
<#
.SYNOPSIS
  Install the CLI tools the tracked slash commands assume (Windows / winget).

.DESCRIPTION
  Three CLIs are load-bearing for this repo's commands:

    gh      GitHub CLI      -- GitHub Issues and PRs on personal projects
    bb      Bitbucket CLI   -- PR create/merge on Results Direct repos
    sqlcmd  SQL Server CLI  -- database work

  The script detects what is already present, installs only what is missing,
  prints a summary, and exits non-zero if anything is still missing. Absence is
  never smoothed into a pass -- that is the convention across this repo.

  Idempotent: running it twice is safe and boring.

.PARAMETER Check
  Report status only. Installs nothing. Exits non-zero if anything is missing.

.PARAMETER DryRun
  Print the install commands that would run, without running them. Exits
  non-zero if anything is missing (because nothing was installed).

.EXAMPLE
  pwsh -NoProfile -File ~/.claude/setup.ps1 -Check

.EXAMPLE
  pwsh -NoProfile -File ~/.claude/setup.ps1
#>
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -- The tool table ------------------------------------------------------------
#
# WARNING -- do not "fix" the bb entry.
#
# `winget search bitbucket` returns TWO packages that both call themselves
# "Bitbucket CLI" and both provide a `bb` command:
#
#   Gildas.Bitbucket-CLI   0.17.6   <- the one we want (github.com/gildas/bitbucket-cli)
#   dlbroadfoot.bb         2.87.1   <- a DIFFERENT tool, entirely different subcommands
#
# Installing dlbroadfoot.bb gives you a working `bb` on PATH that silently fails
# to drive our PR workflow, because the verbs don't match. The higher version
# number is a trap. Always pin `Gildas.Bitbucket-CLI`, and always install with
# --exact --source winget so a fuzzy match can't drift onto the decoy.
$Tools = @(
    [pscustomobject]@{
        Name     = 'gh'
        Label    = 'GitHub CLI'
        WingetId = 'GitHub.cli'
        Manual   = 'https://cli.github.com/'
    }
    [pscustomobject]@{
        Name     = 'bb'
        Label    = 'Bitbucket CLI (Gildas)'
        WingetId = 'Gildas.Bitbucket-CLI'
        Manual   = 'https://github.com/gildas/bitbucket-cli/releases'
    }
    [pscustomobject]@{
        Name     = 'sqlcmd'
        Label    = 'SQL Server command-line client'
        WingetId = 'Microsoft.Sqlcmd'
        Manual   = 'https://learn.microsoft.com/sql/tools/sqlcmd/sqlcmd-utility'
    }
)

# -- Helpers -------------------------------------------------------------------

function Write-Head {
    param([string]$Text)
    Write-Host ''
    Write-Host $Text -ForegroundColor Cyan
}

function Get-ToolPath {
    param([string]$Name)
    $cmd = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    return $null
}

# Run an executable and return its combined stdout/stderr as text, never throwing.
function Get-CommandText {
    param([string]$Exe, [string[]]$Arguments)
    try {
        $out = & $Exe @Arguments 2>&1 | Out-String
    }
    catch {
        $out = ''
    }
    return $out
}

function Get-FirstLine {
    param([string]$Text)
    if (-not $Text) { return '' }
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line.Trim()) { return $line.Trim() }
    }
    return ''
}

# Resolve a human-readable version string. Best-effort: an unrecognised banner
# is reported as 'version unknown' rather than being guessed at.
function Get-ToolVersion {
    param([string]$Name)

    if ($Name -eq 'sqlcmd') {
        # Two different binaries answer to `sqlcmd`: the Go-based go-sqlcmd
        # (Microsoft.Sqlcmd, understands --version) and the older ODBC-shipped
        # sqlcmd.exe (rejects --version; prints its banner under -?).
        $text = Get-CommandText -Exe $Name -Arguments @('--version')
        if ($text -notmatch 'does not have an associated argument' -and $text -match '\d+\.\d+') {
            return (Get-FirstLine $text)
        }
        $text = Get-CommandText -Exe $Name -Arguments @('-?')
        $m = [regex]::Match($text, 'Version\s+([0-9][0-9\.]*)')
        if ($m.Success) { return "sqlcmd (ODBC) $($m.Groups[1].Value)" }
        return 'version unknown'
    }

    $line = Get-FirstLine (Get-CommandText -Exe $Name -Arguments @('--version'))
    if ($line) { return $line }
    return 'version unknown'
}

# PATH in this process is a snapshot taken at launch, so a freshly installed tool
# won't resolve until PATH is re-read from the registry.
function Update-SessionPath {
    try {
        $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $user = [Environment]::GetEnvironmentVariable('Path', 'User')
        $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
    }
    catch {
        Write-Host "  (could not refresh PATH from the registry: $($_.Exception.Message))"
    }
}

# -- Preflight -----------------------------------------------------------------

Write-Head 'claude-config setup (Windows / winget)'
Write-Host 'Tools: gh (GitHub CLI), bb (Bitbucket CLI), sqlcmd (SQL Server CLI)'

if ($Check) { Write-Host 'Mode: -Check -- reporting only, nothing will be installed.' }
elseif ($DryRun) { Write-Host 'Mode: -DryRun -- printing commands only, nothing will be installed.' }
else {
    Write-Host ''
    Write-Host 'Heads-up on elevation: winget installs machine-wide packages and may raise a' -ForegroundColor Yellow
    Write-Host 'UAC prompt per package. Nothing here runs silently as admin behind your back.' -ForegroundColor Yellow
    Write-Host 'If you would rather not be prompted, start an elevated shell before continuing.' -ForegroundColor Yellow
}

$wingetPath = Get-ToolPath 'winget'
$haveWinget = [bool]$wingetPath
if ($haveWinget) {
    Write-Host "winget: $wingetPath"
}
else {
    Write-Host 'winget: NOT FOUND' -ForegroundColor Yellow
    Write-Host '  winget ships with App Installer. Install it from the Microsoft Store, or from'
    Write-Host '  https://github.com/microsoft/winget-cli/releases, then re-run this script.'
}

# -- Work ----------------------------------------------------------------------

$results = @()

foreach ($tool in $Tools) {
    Write-Head "$($tool.Name) -- $($tool.Label)"

    $path = Get-ToolPath $tool.Name
    if ($path) {
        $version = Get-ToolVersion $tool.Name
        Write-Host "  already present: $path"
        Write-Host "  version: $version"
        $results += [pscustomobject]@{
            Name = $tool.Name; Status = 'already present'; Version = $version; Detail = $path
        }
        continue
    }

    Write-Host '  not found on PATH'
    $installCmd = "winget install --id $($tool.WingetId) --exact --source winget " +
                  '--accept-package-agreements --accept-source-agreements --silent'

    if ($Check) {
        Write-Host "  would install with: $installCmd"
        $results += [pscustomobject]@{
            Name = $tool.Name; Status = 'MISSING'; Version = '-'
            Detail = "not installed (check mode); install with: $installCmd"
        }
        continue
    }

    if ($DryRun) {
        Write-Host "  DRY RUN, would run: $installCmd"
        $results += [pscustomobject]@{
            Name = $tool.Name; Status = 'MISSING'; Version = '-'
            Detail = 'not installed (dry run)'
        }
        continue
    }

    if (-not $haveWinget) {
        $results += [pscustomobject]@{
            Name = $tool.Name; Status = 'FAILED'; Version = '-'
            Detail = "winget unavailable -- install manually: $($tool.Manual)"
        }
        continue
    }

    Write-Host "  installing: $installCmd"
    # --exact --source winget: see the decoy warning at the top of this file.
    & winget install --id $tool.WingetId --exact --source winget `
        --accept-package-agreements --accept-source-agreements --silent
    $code = $LASTEXITCODE

    Update-SessionPath
    $path = Get-ToolPath $tool.Name

    if ($path) {
        $version = Get-ToolVersion $tool.Name
        Write-Host "  installed: $path"
        Write-Host "  version: $version"
        $results += [pscustomobject]@{
            Name = $tool.Name; Status = 'installed'; Version = $version; Detail = $path
        }
    }
    elseif ($code -eq 0) {
        # winget claims success but the binary isn't resolvable in this process.
        # Usually a PATH-propagation quirk -- but it is NOT verified, so it counts
        # as missing and the script will exit non-zero.
        Write-Host '  winget reported success, but the command does not resolve in this shell.' -ForegroundColor Yellow
        $results += [pscustomobject]@{
            Name = $tool.Name; Status = 'INSTALLED (UNVERIFIED)'; Version = '-'
            Detail = 'winget exit 0 but not on PATH here -- open a new shell and re-run this script'
        }
    }
    else {
        Write-Host "  winget failed (exit $code)" -ForegroundColor Red
        $results += [pscustomobject]@{
            Name = $tool.Name; Status = 'FAILED'; Version = '-'
            Detail = "winget exit $code -- install manually: $($tool.Manual)"
        }
    }
}

# -- Summary -------------------------------------------------------------------

Write-Head 'Summary'
foreach ($r in $results) {
    $colour = switch ($r.Status) {
        'already present' { 'Green' }
        'installed' { 'Green' }
        default { 'Red' }
    }
    Write-Host ('  {0,-8} {1,-22} {2}' -f $r.Name, $r.Status, $r.Version) -ForegroundColor $colour
    if ($r.Status -notin @('already present', 'installed')) {
        Write-Host "           $($r.Detail)"
    }
}

$bad = @($results | Where-Object { $_.Status -notin @('already present', 'installed') })

Write-Head 'Next steps for this repo'
Write-Host '  1. gh auth login                 -- authenticate the GitHub CLI'
Write-Host '  2. ~/.claude/credentials.json    -- bb reads its Bitbucket credentials from here'
Write-Host '     (the entry whose label starts with "Bitbucket API"). The repo deliberately does NOT'
Write-Host '     contain this file; recreate it by hand. See README.md.'

if ($bad.Count -gt 0) {
    Write-Host ''
    Write-Host "$($bad.Count) tool(s) still missing or unverified: $(($bad.Name) -join ', ')" -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host 'All three CLIs are present.' -ForegroundColor Green
exit 0
