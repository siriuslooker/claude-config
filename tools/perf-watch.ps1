<#
.SYNOPSIS
  Long-running machine performance sampler. Finds what is eating the box when
  the UI / keyboard goes laggy.

.WHY THIS SHAPE — all four points were learned by getting them wrong

  1. PERFORMANCE COUNTERS, NOT Get-Process, for the AV. VIPRE's services are
     PROTECTED processes (ViprePPLSvc is PPL) and Get-Process reports their
     .CPU as 0.00. A sampler built on Get-Process once reported "zero busy
     samples across 98 samples" for a service that had run for days — an
     impossible number that got read as "AV is quiet". Counters read from the
     kernel and work on protected processes.

  2. NEVER \Process(*)\...  — the wildcard overflows the counter buffer on this
     box ("more data to return than will fit in the supplied buffer"); it idles
     at 68+ node.exe alone. Worse, ANY process exiting mid-sample invalidates
     the WHOLE batch ("the data in one of the performance counter samples is
     not valid"), so one dying process takes the system metrics down with it.
     Use targeted name patterns, and filter samples by Status.

  3. FEW Get-Counter CALLS. Each costs ~1s of overhead, so a per-counter loop
     blows a 2-minute timeout at ~40 samples. This makes exactly two calls per
     sample: system set, process set. They are separated so a process-set
     failure cannot cost us the system metrics — the mistake in point 2.

  4. INPUT LAG IS NOT ALWAYS CPU. % DPC Time and % Interrupt Time are sampled
     explicitly: a driver storm starves the input path while total CPU looks
     unremarkable. Disk queue length likewise — a saturated disk feels exactly
     like a slow machine.

.OUTPUT
  Two CSVs: one row per sample of system-wide metrics, and one row per tracked
  process per sample. Plain CSV so they can be pivoted afterwards without
  re-running anything.

.EXAMPLE
  pwsh -NoProfile -File "$HOME/.claude/tools/perf-watch.ps1" -Minutes 120
  pwsh -NoProfile -File "$HOME/.claude/tools/perf-watch.ps1" -Minutes 480 -IntervalSeconds 10
#>
[CmdletBinding()]
param(
    [int]$Minutes = 120,
    [int]$IntervalSeconds = 5,
    [int]$TopN = 10,
    [string]$OutDir = "$HOME\.claude\perf-watch",

    # Counter-based process patterns. Targeted, never '*' — see point 2.
    # Protected processes MUST be covered here; Get-Process cannot see them.
    [string[]]$ProcessPatterns = @(
        'sbamsvc*','vipre*','viprenis*','vipreppl*',   # AV — protected, counters only
        'node*','pwsh*','powershell*','git*',
        'chrome*','msedge*','firefox*',
        'code*','devenv*','java*','gradle*','kotlin*',
        'docker*','com.docker*','vmmem*','wsl*','vmwp*',
        'searchindexer*','msmpeng*','tiworker*','wuauclt*','explorer*'
    )
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$sysCsv  = Join-Path $OutDir "perf-$stamp-system.csv"
$procCsv = Join-Path $OutDir "perf-$stamp-process.csv"
$cores   = [Environment]::ProcessorCount

$sysCounters = @(
    '\Processor(_Total)\% Processor Time'
    '\Processor(_Total)\% DPC Time'
    '\Processor(_Total)\% Interrupt Time'
    '\System\Processor Queue Length'
    '\System\Context Switches/sec'
    '\Memory\Available MBytes'
    '\Memory\Pages/sec'
    '\PhysicalDisk(_Total)\% Disk Time'
    '\PhysicalDisk(_Total)\Avg. Disk Queue Length'
)
$procCounters = $ProcessPatterns | ForEach-Object { "\Process($_)\% Processor Time" }

Write-Host "perf-watch: $cores cores | every ${IntervalSeconds}s for ${Minutes}m"
Write-Host "  system : $sysCsv"
Write-Host "  process: $procCsv"

# Drop counter paths this host does not have, one at a time, rather than losing
# the whole set. Counter names are localised and patterns match nothing when the
# process is not running.
function Select-ValidCounters([string[]]$paths) {
    $ok = @()
    foreach ($p in $paths) {
        try { Get-Counter -Counter $p -MaxSamples 1 -ErrorAction Stop | Out-Null; $ok += $p }
        catch { Write-Host "  (skipping unavailable counter: $p)" }
    }
    $ok
}
$sysCounters  = Select-ValidCounters $sysCounters
$procCounters = Select-ValidCounters $procCounters
Write-Host "  tracking $($sysCounters.Count) system + $($procCounters.Count) process counters"

# A row is written every sample with the SAME shape, always — including on
# failure. The first version wrote a raw error line, which became the CSV header
# and poisoned every subsequent append.
function New-SysRow {
    param($Time, $Sample, $Note)
    [pscustomobject][ordered]@{
        time = $Time; sample = $Sample
        cpu_total_pct = ''; dpc_pct = ''; interrupt_pct = ''
        cpu_queue = ''; ctx_switches_sec = ''
        mem_avail_mb = ''; pages_sec = ''
        disk_busy_pct = ''; disk_queue = ''
        top1_name = ''; top1_pct_machine = ''
        proc_total = ''; proc_top_counts = ''
        note = $Note
    }
}

$deadline = (Get-Date).AddMinutes($Minutes)
$sample = 0

while ((Get-Date) -lt $deadline) {
    $sample++
    $ts = (Get-Date).ToString('s')
    $row = New-SysRow -Time $ts -Sample $sample -Note ''

    # --- system set -----------------------------------------------------------
    try {
        $s = Get-Counter -Counter $sysCounters -MaxSamples 1 -ErrorAction Stop
        $v = @{}
        foreach ($c in $s.CounterSamples) { if ($c.Status -eq 0) { $v[$c.Path] = $c.CookedValue } }
        function Val([string]$suffix) {
            $hit = $v.Keys | Where-Object { $_ -like "*$suffix" } | Select-Object -First 1
            if ($hit) { [math]::Round($v[$hit], 2) } else { '' }
        }
        $row.cpu_total_pct    = Val '(_total)\% processor time'
        $row.dpc_pct          = Val '\% dpc time'
        $row.interrupt_pct    = Val '\% interrupt time'
        $row.cpu_queue        = Val 'processor queue length'
        $row.ctx_switches_sec = Val 'context switches/sec'
        $row.mem_avail_mb     = Val 'available mbytes'
        $row.pages_sec        = Val 'pages/sec'
        $row.disk_busy_pct    = Val '% disk time'
        $row.disk_queue       = Val 'avg. disk queue length'
    } catch {
        $row.note = 'sys-error: ' + ($_.Exception.Message -replace '[,\r\n]', ';')
    }

    # --- process set (separate call, so its failure costs only itself) --------
    try {
        $ps = Get-Counter -Counter $procCounters -MaxSamples 1 -ErrorAction Stop
        # Status -ne 0 means that instance went away mid-sample: skip it, keep
        # the rest. This is the difference between a usable watch and one that
        # dies whenever a build spawns and reaps a compiler.
        $procs = $ps.CounterSamples |
            Where-Object { $_.Status -eq 0 -and
                           $_.InstanceName -notin @('_total','idle') -and
                           $_.CookedValue -gt 0 } |
            Sort-Object CookedValue -Descending |
            Select-Object -First $TopN

        if ($procs) {
            $row.top1_name        = $procs[0].InstanceName
            $row.top1_pct_machine = [math]::Round($procs[0].CookedValue / $cores, 2)
            foreach ($p in $procs) {
                [pscustomobject][ordered]@{
                    time = $ts; sample = $sample
                    process = $p.InstanceName
                    # Per-process counters are percent of ONE core, so a 12-core
                    # box tops out at 1200. Divide for percent-of-machine, which
                    # is the number a human can reason about.
                    pct_machine  = [math]::Round($p.CookedValue / $cores, 2)
                    pct_one_core = [math]::Round($p.CookedValue, 2)
                } | Export-Csv -Path $procCsv -NoTypeInformation -Append
            }
        }
    } catch {
        $row.note = ($row.note + ' proc-error: ' + ($_.Exception.Message -replace '[,\r\n]', ';')).Trim()
    }

    # --- everything else, by CPU-seconds delta --------------------------------
    # The counter patterns above are a curated list, and a curated list is a
    # guess: the first real run missed ms-teams burning 7.7% of the machine
    # because it was not in the list. This sweep is pattern-free, so nothing
    # hides. It CANNOT see protected processes (VIPRE reports 0.00 here) —
    # that is exactly what the counter set above is for. The two are
    # complementary and neither alone is sufficient.
    try {
        $nowProc = @{}
        foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) {
            if ($null -ne $p.CPU) { $nowProc[$p.Id] = @{ n = $p.ProcessName; c = $p.CPU } }
        }
        if ($script:prevProc) {
            $elapsed = ((Get-Date) - $script:prevProcAt).TotalSeconds
            if ($elapsed -gt 0) {
                $nowProc.Keys |
                    Where-Object { $script:prevProc.ContainsKey($_) } |
                    ForEach-Object {
                        $d = $nowProc[$_].c - $script:prevProc[$_].c
                        if ($d -gt 0) {
                            [pscustomobject]@{
                                pid_ = $_; name = $nowProc[$_].n
                                pct  = [math]::Round(($d / $elapsed / $cores) * 100, 2)
                            }
                        }
                    } |
                    Sort-Object pct -Descending | Select-Object -First $TopN |
                    ForEach-Object {
                        [pscustomobject][ordered]@{
                            time = $ts; sample = $sample
                            process = "$($_.name)[$($_.pid_)]"
                            pct_machine = $_.pct
                            pct_one_core = [math]::Round($_.pct * $cores, 2)
                        } | Export-Csv -Path $procCsv -NoTypeInformation -Append
                    }
            }
        }
        $script:prevProc   = $nowProc
        $script:prevProcAt = Get-Date
    } catch {
        $row.note = ($row.note + ' delta-error: ' + ($_.Exception.Message -replace '[,\r\n]', ';')).Trim()
    }

    # Process-count watch. 215 hung `git` orphans from a leaking status line
    # were the actual cause of a machine-wide slowdown on 2026-08-14, and a
    # count is what made it visible — CPU alone did not, because each hung
    # process used none.
    try {
        $counts = Get-Process -ErrorAction SilentlyContinue | Group-Object ProcessName |
                  Sort-Object Count -Descending | Select-Object -First 3
        $row.proc_top_counts = ($counts | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ' '
        $row.proc_total = (Get-Process -ErrorAction SilentlyContinue).Count
    } catch { }

    $row | Export-Csv -Path $sysCsv -NoTypeInformation -Append
    Start-Sleep -Seconds $IntervalSeconds
}

Write-Host "perf-watch: finished after $sample samples."
Write-Host "  $sysCsv"
Write-Host "  $procCsv"
