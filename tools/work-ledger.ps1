<#
.SYNOPSIS
  Validate a work ledger (docs/backlog.json), and render its queue into a markdown file.

.DESCRIPTION
  Implements the `work-ledger` skill: state lives in exactly one place, and drift from that
  place must be a COMPUTABLE finding rather than something someone remembers to look for.

  Two modes:

    -Validate -Ledger <path>
        Run every check in the skill's section 2. Findings print one per line, most severe
        first, with a stable class token per finding so the output is greppable.
        Exit 0 clean, 1 findings, 2 the ledger itself is unreadable or malformed.

    -Render -Ledger <path> -Into <markdown file>
        Regenerate the queue between the markers

            <!-- BEGIN GENERATED: work-ledger -->
            <!-- END GENERATED: work-ledger -->

        Not one byte outside the markers is touched. Missing markers is an error, never a
        guess about where the block belongs.

  PowerShell 7, zero module installs: JSON via ConvertFrom-Json, dates via ParseExact with
  the invariant culture, git via the git executable. Nothing else.

  ## The rule that shapes every check

  A check that cannot be computed reports NOT-CHECKABLE and is never counted as clean.
  `paths: []`, a path that no longer exists, a git command that fails, a directory that is
  not a git repository, a `waitingOn.since` that will not parse -- each is its own named
  outcome. Absence of evidence is never a pass, so NOT-CHECKABLE still exits 1.

.PARAMETER Validate
  Run the checks.

.PARAMETER Render
  Regenerate the queue block in -Into.

.PARAMETER Ledger
  Path to the ledger JSON (conventionally docs/backlog.json). Required by both modes.

.PARAMETER Into
  Markdown file holding the generated markers. Required by -Render.

.PARAMETER DocsRoot
  Directory tree scanned for citations. Defaults to the directory holding the ledger.

.PARAMETER RepoRoot
  Repository root used for `git -C` and for resolving `paths` and `detail`. Defaults to the
  nearest ancestor of the ledger containing a `.git` entry, so the tool works from any cwd.

.PARAMETER Today
  ISO date used as "now" for the stale-waitingOn check. Defaults to the current date.
  Supplying it makes a run fully reproducible.

.PARAMETER StaleDays
  Age in days at which a `waitingOn` is stale. Default 30.

.PARAMETER StateWords
  Words that count as a status assertion for the state-in-prose check.
  Default: planned, done, blocked, shipped. Deliberately tunable, and deliberately not
  emoji -- in a mature documentation set the emoji are rhetorical emphasis, not state
  (one audit counted ~2,861 of them), so anything reading them reads prose as data.

.PARAMETER OrphanScanBare
  Widen the orphan-citation check to every id-shaped token, not just those in a known
  namespace or written in backticks. Noisier; for a deliberate audit pass.

.PARAMETER AppendOnlyDocs
  Filename patterns for APPEND-ONLY HISTORY documents, exempt from the state-in-prose check
  and from that check only -- they are still fully scanned for orphan citations.

  Default: *decision-log*.md, *phase-journal*.md, archive-*.md. Each earns its place on the
  same principle, not on a threshold: a decision-log entry recording that a thing shipped on
  a date is doing its job, so is a phase journal, and an archive is append-only BY
  DEFINITION -- a frozen record whose whole purpose is to say what was true on a date.
  Rewriting any of them to satisfy this check would be vandalism, not a fix.

  Patterns rather than fixed names, so the docs/ scaffold's numeric prefixes do not matter
  and no project-specific filename is hardcoded.

  qa-* is deliberately NOT here. "Closed" is not inferable from a filename and a live
  runbook looks identical to a closed one, so a runbook asserting an item shipped is a
  second home for a LIVE item's state. A few findings is a cheap price for not blinding the
  check to a live surface.

  Every skipped file is NAMED in a PROSE-APPEND-ONLY-EXEMPT line on every run. That line is
  the only thing standing between a narrow principled exemption and a growing list of
  documents the check quietly ignores. Do not make it conditional, and do not remove it.

.PARAMETER NoProseCheck
  Skip the state-in-prose check.

.PARAMETER NoGitCheck
  Skip the git drift check. Reported as NOT-CHECKABLE rather than silently omitted.

.PARAMETER Help
  Print usage.

.EXAMPLE
  pwsh -NoProfile -File ~/.claude/tools/work-ledger.ps1 -Validate -Ledger docs/backlog.json

.EXAMPLE
  pwsh -NoProfile -File ~/.claude/tools/work-ledger.ps1 -Render -Ledger docs/backlog.json -Into docs/2-project-status.md
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [switch]$Validate,
    [switch]$Render,
    [string]$Ledger,
    [string]$Into,
    [string]$DocsRoot,
    [string]$RepoRoot,
    [string]$Today,
    [int]$StaleDays = 30,
    [string[]]$StateWords = @('planned', 'done', 'blocked', 'shipped'),
    [switch]$NoProseCheck,
    [switch]$NoGitCheck,
    [switch]$OrphanScanBare,
    [string[]]$AppendOnlyDocs = @('*decision-log*.md', '*phase-journal*.md', 'archive-*.md'),
    [Alias('h')][switch]$Help
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

$script:BeginMarker = '<!-- BEGIN GENERATED: work-ledger -->'
$script:EndMarker = '<!-- END GENERATED: work-ledger -->'

# ---------------------------------------------------------------- usage / hard failure

function Show-Usage {
    @'
work-ledger.ps1 -- validate a work ledger and render its queue.

  Validate:
    work-ledger.ps1 -Validate -Ledger <backlog.json>
                    [-DocsRoot <dir>] [-RepoRoot <dir>] [-Today <yyyy-MM-dd>]
                    [-StaleDays <n>] [-StateWords a,b,c]
                    [-OrphanScanBare] [-AppendOnlyDocs pat,pat]
                    [-NoProseCheck] [-NoGitCheck]

  Render:
    work-ledger.ps1 -Render -Ledger <backlog.json> -Into <markdown file>

  Exit codes (validate):  0 clean   1 findings   2 ledger unreadable/malformed
  Exit codes (render):    0 written  2 ledger unreadable, markers missing/ambiguous

  Findings print one per line, most severe first, as:
    <SEVERITY>  <CLASS>  <id>  <message>
  Severities: ERROR, WARN, NOT-CHECKABLE, INFO. Grep column 2 for a class, e.g.
    ... -Validate -Ledger docs/backlog.json | Select-String PROBABLY-SHIPPED

  A NOT-CHECKABLE finding is not a pass: it exits 1 like any other finding.
  INFO is information, not a finding, and does not affect the exit code -- a `paths`
  entry the work has yet to create is reported there.
'@ | Write-Output
}

function Fail-Hard {
    param([string]$Message)
    Write-Output "FATAL  $Message"
    exit 2
}

# ---------------------------------------------------------------- findings

$script:Findings = [System.Collections.Generic.List[object]]::new()
# INFO is printed and greppable but is NOT a finding: it does not affect the exit code.
# It exists for facts that are real information yet entirely consistent with the item's
# state -- a `paths` entry the work has yet to create being the case that forced it.
$script:SevRank = @{ 'ERROR' = 0; 'WARN' = 1; 'NOT-CHECKABLE' = 2; 'INFO' = 3 }

function Add-Finding {
    param(
        [ValidateSet('ERROR', 'WARN', 'NOT-CHECKABLE', 'INFO')][string]$Severity,
        [string]$Class,
        [string]$Id,
        [string]$Message
    )
    $shown = $Id
    if ([string]::IsNullOrWhiteSpace($shown)) { $shown = '-' }
    $script:Findings.Add([pscustomobject]@{
            Severity = $Severity
            Rank     = $script:SevRank[$Severity]
            Class    = $Class
            Id       = $shown
            Message  = $Message
        })
}

# ---------------------------------------------------------------- small helpers

function Get-Field {
    param($Obj, [string]$Name)
    if ($null -eq $Obj) { return $null }
    $p = $Obj.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    # `return , $x` -- the comma is load-bearing. A bare `return $p.Value` lets the pipeline
    # unroll the value, so `[]` comes back as $null and a one-element array comes back as
    # its element. That made every array field look like it was the wrong type.
    return , $p.Value
}

function Test-HasField {
    param($Obj, [string]$Name)
    if ($null -eq $Obj) { return $false }
    return ($null -ne $Obj.PSObject.Properties[$Name])
}

# Explicit, invariant-culture ISO parsing. Never Get-Date -- a locale-dependent parse
# would make the same ledger validate differently on two machines.
function Parse-IsoDate {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    # MUST be [string[]]. An Object[] binds the (String, String, ...) overload instead and
    # PowerShell joins the array into one nonsense format, so every date fails to parse.
    [string[]]$formats = @('yyyy-MM-dd', 'yyyy-MM-ddTHH:mm:ss', 'yyyy-MM-ddTHH:mm:ssZ', 'yyyy-MM-ddTHH:mm:sszzz')
    [datetime]$parsed = [datetime]::MinValue
    $ok = [datetime]::TryParseExact(
        $Text.Trim(),
        $formats,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref]$parsed)
    if ($ok) { return $parsed }
    return $null
}

# `priority` is the only field a human sets by fiat, and it is NEVER derived. Absent or
# null means unranked -- not last place. Returns $null unless the value is a positive
# integer, so an invalid value (reported by the schema check) cannot fake a rank.
function Get-PriorityOrNull {
    param($Obj)
    if (-not (Test-HasField $Obj 'priority')) { return $null }
    $raw = Get-Field $Obj 'priority'
    if ($null -eq $raw) { return $null }
    $text = [string]$raw
    $n = 0
    if (-not [int]::TryParse($text, [ref]$n)) { return $null }
    if ("$n" -ne $text.Trim()) { return $null }   # rejects 1.0, 01, " 1 "
    if ($n -lt 1) { return $null }
    return $n
}

function Get-AsArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) { return @($Value) }
    if ($Value -is [System.Collections.IEnumerable]) { return @($Value) }
    return @($Value)
}

# An id-shaped token: uppercase-kebab (IMG-DELETE), or a bare run like P11.
$script:IdShape = '^[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)*$'

# Namespace-number shaped, e.g. PROJ-957 or WO-27. Used ONLY to decide whether a BACKTICKED
# token in an unknown namespace is a citation. NEVER used to validate an id -- most real
# ids are word-shaped, so this is a narrow admission rule, not an id definition.
$script:NsNumberShape = [regex]'^[A-Z]{2,}-[0-9]+$'

function Test-IdShaped {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return ($Text -cmatch $script:IdShape)
}

# ---------------------------------------------------------------- load

function Read-Ledger {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        Fail-Hard '-Ledger is required. Pass the path to the ledger JSON (conventionally docs/backlog.json).'
    }
    if (-not (Test-Path -LiteralPath $Path)) { Fail-Hard "Ledger not found: $Path" }
    $item = Get-Item -LiteralPath $Path
    if ($item.PSIsContainer) { Fail-Hard "-Ledger must be a file, not a directory: $Path" }

    $raw = $null
    try { $raw = [System.IO.File]::ReadAllText($item.FullName) }
    catch { Fail-Hard "Ledger could not be read: $Path -- $($_.Exception.Message)" }

    if ([string]::IsNullOrWhiteSpace($raw)) { Fail-Hard "Ledger is empty: $Path" }

    $doc = $null
    try { $doc = $raw | ConvertFrom-Json -Depth 32 }
    catch { Fail-Hard "Ledger is not valid JSON: $Path -- $($_.Exception.Message)" }

    if ($null -eq $doc -or $doc -is [array]) {
        Fail-Hard "Ledger must be a JSON object with an 'items' array: $Path"
    }
    if (-not (Test-HasField $doc 'items')) { Fail-Hard "Ledger has no 'items' array: $Path" }

    $items = Get-Field $doc 'items'
    if ($null -eq $items) { Fail-Hard "Ledger 'items' is null: $Path" }
    if ($items -is [string] -or -not ($items -is [System.Collections.IEnumerable])) {
        Fail-Hard "Ledger 'items' must be an array: $Path"
    }

    $list = @($items)
    for ($i = 0; $i -lt $list.Count; $i++) {
        if ($null -eq $list[$i] -or -not ($list[$i] -is [pscustomobject])) {
            Fail-Hard "Ledger items[$i] is not an object: $Path"
        }
    }

    return [pscustomobject]@{
        Path     = $item.FullName
        Document = $doc
        Items    = $list
    }
}

function Resolve-RepoRoot {
    param([string]$LedgerPath, [string]$Override)
    if (-not [string]::IsNullOrWhiteSpace($Override)) {
        if (-not (Test-Path -LiteralPath $Override)) { Fail-Hard "-RepoRoot does not exist: $Override" }
        return (Get-Item -LiteralPath $Override).FullName
    }
    $dir = [System.IO.Path]::GetDirectoryName($LedgerPath)
    while (-not [string]::IsNullOrWhiteSpace($dir)) {
        if (Test-Path -LiteralPath (Join-Path $dir '.git')) { return $dir }
        $parent = [System.IO.Path]::GetDirectoryName($dir)
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

# ---------------------------------------------------------------- vocabulary

$script:Enums = @{
    kind     = @('code', 'config', 'infra', 'decision', 'doc', 'qa')
    state    = @('open', 'in-progress', 'landed', 'dropped')
    size     = @('one-line', 'hour', 'half-day', 'day', 'phase', 'unknown')
    severity = @('data-loss', 'security', 'correctness', 'ux', 'debt', 'none')
}

$script:RequiredFields = @(
    'id', 'title', 'kind', 'state', 'repo', 'size', 'severity',
    'dependsOn', 'waitingOn', 'paths', 'aliases', 'detail', 'opened'
)

$script:SevOrder = @{ 'data-loss' = 0; 'security' = 1; 'correctness' = 2; 'ux' = 3; 'debt' = 4; 'none' = 5 }
$script:SizeOrder = @{ 'one-line' = 0; 'hour' = 1; 'half-day' = 2; 'day' = 3; 'phase' = 4; 'unknown' = 5 }
$script:KindOrder = @('code', 'config', 'infra', 'decision', 'doc', 'qa')

# ---------------------------------------------------------------- checks

function Invoke-SchemaChecks {
    param($LedgerData)

    $doc = $LedgerData.Document

    $schema = Get-Field $doc 'schema'
    if ($null -eq $schema) {
        Add-Finding -Severity 'ERROR' -Class 'SCHEMA-NO-VERSION' -Id '-' -Message "ledger has no top-level 'schema' field"
    }
    elseif ("$schema" -ne '1') {
        Add-Finding -Severity 'ERROR' -Class 'SCHEMA-VERSION-UNKNOWN' -Id '-' -Message "ledger 'schema' is '$schema'; this tool understands schema 1"
    }
    foreach ($top in @('project', 'updated')) {
        if ($null -eq (Get-Field $doc $top)) {
            Add-Finding -Severity 'WARN' -Class 'SCHEMA-TOP-FIELD-MISSING' -Id '-' -Message "ledger has no top-level '$top' field"
        }
    }
    $updated = Get-Field $doc 'updated'
    if ($null -ne $updated -and $null -eq (Parse-IsoDate ([string]$updated))) {
        Add-Finding -Severity 'ERROR' -Class 'SCHEMA-DATE-INVALID' -Id '-' -Message "top-level 'updated' is not an ISO date: '$updated'"
    }

    # retired / ignoredNamespaces: both optional, both arrays of strings. Absent means empty,
    # so no existing ledger becomes invalid by their introduction.
    foreach ($topArray in @('retired', 'ignoredNamespaces')) {
        if (-not (Test-HasField $doc $topArray)) { continue }
        $v = Get-Field $doc $topArray
        if ($null -eq $v -or $v -is [string] -or -not ($v -is [System.Collections.IEnumerable])) {
            Add-Finding -Severity 'ERROR' -Class 'SCHEMA-NOT-ARRAY' -Id '-' -Message "top-level '$topArray' must be an array of strings (omit it, or use [], when empty)"
            continue
        }
        foreach ($e in @($v)) {
            if ($null -eq $e -or $e -isnot [string] -or [string]::IsNullOrWhiteSpace($e)) {
                Add-Finding -Severity 'ERROR' -Class 'SCHEMA-NOT-ARRAY' -Id '-' -Message "top-level '$topArray' contains a non-string or empty entry"
            }
        }
    }

    # An id in BOTH retired and items is a contradiction, not a harmless duplicate: the
    # ledger would be claiming the same work is live and closed at once.
    $itemIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($it in $LedgerData.Items) {
        $iid = [string](Get-Field $it 'id')
        if (-not [string]::IsNullOrWhiteSpace($iid)) { [void]$itemIds.Add($iid.Trim()) }
    }
    foreach ($r in (Get-AsArray (Get-Field $doc 'retired'))) {
        $rt = ([string]$r).Trim()
        if ($rt.Length -gt 0 -and $itemIds.Contains($rt)) {
            Add-Finding -Severity 'ERROR' -Class 'SCHEMA-RETIRED-CONTRADICTION' -Id $rt -Message "appears in both 'retired' and 'items'; an item cannot be live and closed at once"
        }
    }

    $enumFields = @($script:Enums.Keys | Sort-Object)
    $seen = @{}
    $index = -1
    foreach ($it in $LedgerData.Items) {
        $index++
        $rawId = Get-Field $it 'id'
        $id = if ($null -eq $rawId) { "items[$index]" } else { [string]$rawId }

        foreach ($f in $script:RequiredFields) {
            if (-not (Test-HasField $it $f)) {
                Add-Finding -Severity 'ERROR' -Class 'SCHEMA-FIELD-MISSING' -Id $id -Message "required field '$f' is absent"
            }
        }

        if ($null -ne $rawId) {
            if ($id -cmatch '^\d+$') {
                Add-Finding -Severity 'ERROR' -Class 'SCHEMA-ID-POSITIONAL' -Id $id -Message 'id is a bare number; an id is a name, never an ordinal'
            }
            elseif (-not (Test-IdShaped $id)) {
                Add-Finding -Severity 'ERROR' -Class 'SCHEMA-ID-SHAPE' -Id $id -Message 'id is not uppercase-kebab'
            }
            if ($seen.ContainsKey($id)) {
                Add-Finding -Severity 'ERROR' -Class 'SCHEMA-ID-DUPLICATE' -Id $id -Message "id appears more than once (items[$($seen[$id])] and items[$index])"
            }
            else {
                $seen[$id] = $index
            }
        }

        foreach ($field in $enumFields) {
            if (Test-HasField $it $field) {
                $allowed = $script:Enums[$field]
                $val = [string](Get-Field $it $field)
                if ($allowed -notcontains $val) {
                    Add-Finding -Severity 'ERROR' -Class 'SCHEMA-ENUM-INVALID' -Id $id -Message "$field '$val' is not one of: $($allowed -join ', ')"
                }
            }
        }

        foreach ($field in @('dependsOn', 'paths', 'aliases')) {
            if (Test-HasField $it $field) {
                $v = Get-Field $it $field
                if ($null -eq $v -or $v -is [string] -or -not ($v -is [System.Collections.IEnumerable])) {
                    Add-Finding -Severity 'ERROR' -Class 'SCHEMA-NOT-ARRAY' -Id $id -Message "$field must be an array (use [] when empty)"
                }
            }
        }

        if (Test-HasField $it 'opened') {
            $openedRaw = [string](Get-Field $it 'opened')
            if ($null -eq (Parse-IsoDate $openedRaw)) {
                Add-Finding -Severity 'ERROR' -Class 'SCHEMA-DATE-INVALID' -Id $id -Message "opened is not an ISO date: '$openedRaw'"
            }
        }

        $w = Get-Field $it 'waitingOn'
        if ($null -ne $w) {
            if ($w -is [string] -or -not ($w -is [pscustomobject])) {
                Add-Finding -Severity 'ERROR' -Class 'SCHEMA-WAITINGON-SHAPE' -Id $id -Message 'waitingOn must be null, or an object with who/what/since'
            }
            else {
                foreach ($f in @('who', 'what', 'since')) {
                    if ([string]::IsNullOrWhiteSpace([string](Get-Field $w $f))) {
                        Add-Finding -Severity 'ERROR' -Class 'SCHEMA-WAITINGON-SHAPE' -Id $id -Message "waitingOn.$f is missing or empty"
                    }
                }
            }
        }

        # priority: a positive integer or null. Absent is legal and means unranked; there is
        # deliberately NO default, because a default would be a derived priority.
        if (Test-HasField $it 'priority') {
            $praw = Get-Field $it 'priority'
            if ($null -ne $praw -and $null -eq (Get-PriorityOrNull $it)) {
                Add-Finding -Severity 'ERROR' -Class 'SCHEMA-PRIORITY-INVALID' -Id $id -Message "priority '$praw' is not a positive integer or null (1 = highest; omit or null when unranked)"
            }
        }

        if ((Test-HasField $it 'title') -and [string]::IsNullOrWhiteSpace([string](Get-Field $it 'title'))) {
            Add-Finding -Severity 'ERROR' -Class 'SCHEMA-FIELD-EMPTY' -Id $id -Message 'title is empty'
        }
    }
}

function Invoke-DependencyChecks {
    param($LedgerData)

    $byId = @{}
    foreach ($it in $LedgerData.Items) {
        $id = [string](Get-Field $it 'id')
        if (-not [string]::IsNullOrWhiteSpace($id) -and -not $byId.ContainsKey($id)) { $byId[$id] = $it }
    }

    foreach ($it in $LedgerData.Items) {
        $id = [string](Get-Field $it 'id')
        foreach ($dep in (Get-AsArray (Get-Field $it 'dependsOn'))) {
            $depId = [string]$dep
            if ($depId -eq $id) {
                Add-Finding -Severity 'ERROR' -Class 'DEP-SELF' -Id $id -Message 'dependsOn names itself'
                continue
            }
            if (-not $byId.ContainsKey($depId)) {
                Add-Finding -Severity 'ERROR' -Class 'DEP-DANGLING' -Id $id -Message "dependsOn '$depId' matches no ledger item"
                continue
            }
            $depState = [string](Get-Field $byId[$depId] 'state')
            if ($depState -eq 'landed' -or $depState -eq 'dropped') {
                Add-Finding -Severity 'ERROR' -Class 'PHANTOM-BLOCKER' -Id $id -Message "dependsOn '$depId' is already '$depState'; this blocker has dissolved"
            }
        }
    }

    # Cycles. Iterative DFS, ids and edges sorted so the reported cycle is deterministic.
    $colour = @{}   # 1 = on the current path, 2 = finished
    $reported = @{}
    foreach ($start in ($byId.Keys | Sort-Object)) {
        if ($colour[$start] -eq 2) { continue }

        $stack = [System.Collections.Generic.List[object]]::new()
        $path = [System.Collections.Generic.List[string]]::new()

        $startEdges = @(Get-AsArray (Get-Field $byId[$start] 'dependsOn') | ForEach-Object { [string]$_ } | Where-Object { $byId.ContainsKey($_) -and $_ -ne $start } | Sort-Object)
        $stack.Add([pscustomobject]@{ Id = $start; Edges = $startEdges; Next = 0 })
        $colour[$start] = 1
        $path.Add($start)

        while ($stack.Count -gt 0) {
            $top = $stack[$stack.Count - 1]
            if ($top.Next -lt $top.Edges.Count) {
                $next = [string]$top.Edges[$top.Next]
                $top.Next = $top.Next + 1

                if ($colour[$next] -eq 1) {
                    $at = $path.IndexOf($next)
                    $cycle = @($path[$at..($path.Count - 1)]) + @($next)
                    $key = (($cycle | Sort-Object -Unique) -join '>')
                    if (-not $reported.ContainsKey($key)) {
                        $reported[$key] = $true
                        Add-Finding -Severity 'ERROR' -Class 'DEP-CYCLE' -Id ($cycle[0]) -Message "dependsOn cycle: $($cycle -join ' -> ')"
                    }
                }
                elseif ($colour[$next] -ne 2) {
                    $colour[$next] = 1
                    $path.Add($next)
                    $node = $next
                    $edges = @(Get-AsArray (Get-Field $byId[$node] 'dependsOn') | ForEach-Object { [string]$_ } | Where-Object { $byId.ContainsKey($_) -and $_ -ne $node } | Sort-Object)
                    $stack.Add([pscustomobject]@{ Id = $next; Edges = $edges; Next = 0 })
                }
            }
            else {
                $colour[$top.Id] = 2
                $stack.RemoveAt($stack.Count - 1)
                if ($path.Count -gt 0) { $path.RemoveAt($path.Count - 1) }
            }
        }
    }
}

function Invoke-DecisionChecks {
    param($LedgerData, [string]$RepoRootPath, [string]$LedgerDir)

    foreach ($it in $LedgerData.Items) {
        $id = [string](Get-Field $it 'id')
        $state = [string](Get-Field $it 'state')
        $decided = [string](Get-Field $it 'decidedIn')

        if ($state -eq 'in-progress' -and [string]::IsNullOrWhiteSpace($decided)) {
            Add-Finding -Severity 'WARN' -Class 'UNDECIDED-IN-FLIGHT' -Id $id -Message "state 'in-progress' with no decidedIn; building before agreeing"
        }
        if ($state -eq 'open' -and -not [string]::IsNullOrWhiteSpace($decided)) {
            Add-Finding -Severity 'WARN' -Class 'DECIDED-NOT-BUILT' -Id $id -Message "decidedIn is set but state is still 'open' -- recorded is not tracked"
        }

        # Dangling detail. The FILE is resolved; the #anchor is not (see the report).
        $detail = [string](Get-Field $it 'detail')
        if ([string]::IsNullOrWhiteSpace($detail)) {
            if (Test-HasField $it 'detail') {
                Add-Finding -Severity 'WARN' -Class 'DANGLING-DETAIL' -Id $id -Message 'detail is empty; nobody can act on this item'
            }
            continue
        }

        $filePart = ($detail -split '#', 2)[0]
        if ([string]::IsNullOrWhiteSpace($filePart)) {
            Add-Finding -Severity 'NOT-CHECKABLE' -Class 'DETAIL-ANCHOR-ONLY' -Id $id -Message "detail '$detail' names no file, so it cannot be resolved"
            continue
        }

        # A `detail` is conventionally repo-root-relative (docs/9-foo.md#6). Fall back to the
        # ledger's parent (the usual repo root when there is no .git) and then to the ledger's
        # own directory, so a ledger checked out on its own still resolves.
        $bases = @()
        if (-not [string]::IsNullOrWhiteSpace($RepoRootPath)) { $bases += $RepoRootPath }
        $ledgerParent = [System.IO.Path]::GetDirectoryName($LedgerDir)
        if (-not [string]::IsNullOrWhiteSpace($ledgerParent)) { $bases += $ledgerParent }
        $bases += $LedgerDir
        $found = $false
        foreach ($b in $bases) {
            if (Test-Path -LiteralPath (Join-Path $b $filePart)) { $found = $true; break }
        }
        if (-not $found) {
            Add-Finding -Severity 'WARN' -Class 'DANGLING-DETAIL' -Id $id -Message "detail points nowhere: '$filePart'"
        }
    }
}

function Invoke-WaitingOnChecks {
    param($LedgerData, [datetime]$Now, [int]$Days)

    foreach ($it in $LedgerData.Items) {
        $id = [string](Get-Field $it 'id')
        $w = Get-Field $it 'waitingOn'
        if ($null -eq $w -or -not ($w -is [pscustomobject])) { continue }

        $sinceRaw = [string](Get-Field $w 'since')
        $since = Parse-IsoDate $sinceRaw
        if ($null -eq $since) {
            Add-Finding -Severity 'NOT-CHECKABLE' -Class 'WAITINGON-SINCE-UNPARSEABLE' -Id $id -Message "waitingOn.since '$sinceRaw' is not an ISO date, so staleness cannot be computed"
            continue
        }
        if (($Now - $since).TotalDays -gt $Days) {
            $who = [string](Get-Field $w 'who')
            Add-Finding -Severity 'WARN' -Class 'STALE-WAITING-ON' -Id $id -Message "waitingOn '$who' since $($since.ToString('yyyy-MM-dd')), older than $Days days and never revisited"
        }
    }
}

# The highest-value check in the tool: ask git, not a document, whether work has moved.
function Invoke-GitDriftCheck {
    param($LedgerData, [string]$RepoRootPath)

    $openItems = @($LedgerData.Items | Where-Object { [string](Get-Field $_ 'state') -eq 'open' })
    if ($openItems.Count -eq 0) { return }

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Add-Finding -Severity 'NOT-CHECKABLE' -Class 'GIT-UNAVAILABLE' -Id '-' -Message "git is not on PATH, so drift could not be computed for $($openItems.Count) open item(s)"
        return
    }
    if ([string]::IsNullOrWhiteSpace($RepoRootPath)) {
        Add-Finding -Severity 'NOT-CHECKABLE' -Class 'GIT-NO-REPO' -Id '-' -Message "no .git found above the ledger, so drift could not be computed for $($openItems.Count) open item(s)"
        return
    }

    & git -C $RepoRootPath rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -ne 0) {
        Add-Finding -Severity 'NOT-CHECKABLE' -Class 'GIT-NO-REPO' -Id '-' -Message "'$RepoRootPath' is not a usable git work tree, so drift could not be computed for $($openItems.Count) open item(s)"
        return
    }

    foreach ($it in $openItems) {
        $id = [string](Get-Field $it 'id')

        $opened = Parse-IsoDate ([string](Get-Field $it 'opened'))
        if ($null -eq $opened) {
            Add-Finding -Severity 'NOT-CHECKABLE' -Class 'DRIFT-NO-BASELINE' -Id $id -Message 'opened is not an ISO date, so there is no baseline to measure commits from'
            continue
        }
        $since = $opened.ToString('yyyy-MM-dd')

        $paths = @(Get-AsArray (Get-Field $it 'paths') | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($paths.Count -eq 0) {
            Add-Finding -Severity 'NOT-CHECKABLE' -Class 'PATHS-EMPTY' -Id $id -Message 'paths is empty, so whether this shipped cannot be computed'
            continue
        }

        $moved = [System.Collections.Generic.List[string]]::new()
        $still = [System.Collections.Generic.List[string]]::new()
        $toCreate = [System.Collections.Generic.List[string]]::new()
        $skipped = 0

        foreach ($p in ($paths | Sort-Object)) {
            # ONE `git log` per path, and the VERDICT COMES FROM COMMITS ONLY. The working
            # tree is never evidence that work moved -- uncommitted work is invisible here
            # by design. Test-Path appears below solely to name the REASON a path could not
            # be judged, never to decide whether it moved.
            $out = & git -C $RepoRootPath log --since=$since --format=%H -- $p 2>&1
            if ($LASTEXITCODE -ne 0) {
                $why = ((@($out) -join ' ').Trim())
                Add-Finding -Severity 'NOT-CHECKABLE' -Class 'GIT-COMMAND-FAILED' -Id $id -Message "git log failed for path '$p': $why"
                $skipped++
                continue
            }
            $hashes = @(@($out) | Where-Object { "$_" -match '\S' })
            if ($hashes.Count -gt 0) { $moved.Add($p); continue }

            # 🔴 Zero commits since `opened` is NOT yet evidence of "no movement": git may not
            # be able to see this path AT ALL. Collapsing those two cases reports every item
            # pointing into a vendored, gitignored reference clone as clean.
            & git -C $RepoRootPath check-ignore -q -- $p *> $null
            if ($LASTEXITCODE -eq 0) {
                Add-Finding -Severity 'NOT-CHECKABLE' -Class 'PATH-GITIGNORED' -Id $id -Message "path '$p' is gitignored in this repo (a vendored reference clone has its own history), so its commits cannot be judged here"
                $skipped++
                continue
            }

            $any = & git -C $RepoRootPath log -1 --format=%H -- $p 2>&1
            $hasHistory = ($LASTEXITCODE -eq 0) -and (@(@($any) | Where-Object { "$_" -match '\S' }).Count -gt 0)
            if ($hasHistory) { $still.Add($p); continue }   # git knows it; genuinely no commits since

            if (Test-Path -LiteralPath (Join-Path $RepoRootPath $p)) {
                Add-Finding -Severity 'NOT-CHECKABLE' -Class 'PATH-UNTRACKED' -Id $id -Message "path '$p' exists but git has no commits for it at all, so drift cannot be measured from commits"
                $skipped++
                continue
            }

            # Yet to be created. Real information, entirely consistent with state 'open',
            # and NOT an error -- an item whose whole job is to create this file used to
            # have to declare `paths: []` and report not-checkable forever.
            Add-Finding -Severity 'INFO' -Class 'PATH-YET-TO-BE-CREATED' -Id $id -Message "path '$p' does not exist yet and has no history; this work has still to create it"
            $toCreate.Add($p)
        }

        # Every declared path yet to be created: not-checkable, for a reason distinct from
        # having declared no paths at all.
        if ($toCreate.Count -eq $paths.Count) {
            Add-Finding -Severity 'NOT-CHECKABLE' -Class 'PATHS-ALL-YET-TO-BE-CREATED' -Id $id -Message "all $($paths.Count) declared path(s) are yet to be created, so there is nothing to measure drift against"
            continue
        }

        # A path yet to be created counts against 'shipped' -- a declared file that does not
        # exist is the clearest possible evidence the work has not landed.
        $checkable = $moved.Count + $still.Count + $toCreate.Count
        if ($checkable -eq 0) {
            Add-Finding -Severity 'NOT-CHECKABLE' -Class 'DRIFT-NO-CHECKABLE-PATHS' -Id $id -Message "none of the $($paths.Count) path(s) could be checked, so drift is unknown"
            continue
        }
        # PROBABLY-SHIPPED requires EVERY declared path to have moved. If even one path could
        # not be judged -- a gitignored reference clone being the case that matters -- then
        # "every path has commits" is not established, so the verdict is downgraded rather
        # than asserted. Trading an honest gap for a false pass is the failure mode here.
        if ($moved.Count -eq $checkable -and $skipped -eq 0) {
            Add-Finding -Severity 'WARN' -Class 'PROBABLY-SHIPPED' -Id $id -Message "state 'open' but all $checkable declared path(s) have commits since ${since} -- git disagrees with the ledger"
        }
        elseif ($moved.Count -gt 0) {
            $note = ''
            if ($skipped -gt 0) { $note = ", and $skipped path(s) could not be judged (so 'shipped' cannot be concluded)" }
            Add-Finding -Severity 'WARN' -Class 'PARTIALLY-MOVED' -Id $id -Message "state 'open' and $($moved.Count) of $checkable judgeable path(s) have commits since ${since}${note} -- moved: $($moved -join ', ')"
        }
    }
}

function Get-DocLines {
    param([string]$Root, [string]$LedgerPath)

    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -ne $LedgerPath } |
        Sort-Object FullName)

    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($f in $files) {
        $inGenerated = $false
        $n = 0
        foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
            $n++
            if ($line.Contains($script:BeginMarker)) { $inGenerated = $true; continue }
            if ($line.Contains($script:EndMarker)) { $inGenerated = $false; continue }
            if ($inGenerated) { continue }   # generated output is not prose
            $result.Add([pscustomobject]@{ File = $f.FullName; Line = $n; Text = $line })
        }
    }
    return $result
}

function Invoke-CitationChecks {
    param($LedgerData, [string]$DocsRootPath)

    if ([string]::IsNullOrWhiteSpace($DocsRootPath) -or -not (Test-Path -LiteralPath $DocsRootPath)) {
        Add-Finding -Severity 'NOT-CHECKABLE' -Class 'DOCS-ROOT-MISSING' -Id '-' -Message "docs root '$DocsRootPath' does not exist, so the citation checks could not run"
        return
    }

    # Known symbols: ids, ALIASES, and jira keys. Aliases matter as much as ids -- a
    # citation matching an alias is a legitimate old name, not an orphan. Getting this
    # wrong floods the first run with false positives and the tool gets switched off.
    $known = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $idShapedKnown = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $prefixes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    foreach ($it in $LedgerData.Items) {
        $syms = @([string](Get-Field $it 'id')) +
        @(Get-AsArray (Get-Field $it 'aliases') | ForEach-Object { [string]$_ }) +
        @([string](Get-Field $it 'jira'))
        foreach ($s in $syms) {
            if ([string]::IsNullOrWhiteSpace($s)) { continue }
            $t = $s.Trim()
            [void]$known.Add($t)
            if (Test-IdShaped $t) {
                [void]$idShapedKnown.Add($t)
                [void]$prefixes.Add((($t -split '-', 2)[0]))
            }
        }
    }

    # 🔴 `retired` is what stops the orphan check dying in its first week. Rule 4 REMOVES
    # landed items, so without this every live-document citation of closed work orphans
    # forever -- measured at 26 of 30 findings on the first real ledger, in exactly the
    # documents most worth scanning. A retired symbol resolves; it is not an orphan.
    # It feeds the known-symbol set and the namespace prefixes, but DELIBERATELY NOT the
    # state-in-prose scan. This is intentional under-reporting, which looks exactly like a
    # bug, so do not "fix" it back: a REMOVED item has no ledger state left for prose to
    # contradict, and that check exists to catch a SECOND home for a LIVE item's state.
    # Measured on the first real ledger, 2026-09-08: feeding 19 retired ids into the prose
    # scan added 29 findings (38 -> 67), every one of them a history document correctly
    # recording that shipped work shipped. That is the noise that gets a check switched off.
    $retiredCount = 0
    foreach ($r in (Get-AsArray (Get-Field $LedgerData.Document 'retired'))) {
        if ($null -eq $r) { continue }
        $t = ([string]$r).Trim()
        if ($t.Length -eq 0) { continue }
        [void]$known.Add($t)
        $retiredCount++
        if (Test-IdShaped $t) { [void]$prefixes.Add((($t -split '-', 2)[0])) }
    }

    # `ignoredNamespaces` -- prefixes that are NEVER ledger items. A work order is an
    # artifact, not a unit of work, so `WO-27` must never be expected in the ledger.
    $ignoredNs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($n in (Get-AsArray (Get-Field $LedgerData.Document 'ignoredNamespaces'))) {
        if ($null -eq $n) { continue }
        $t = ([string]$n).Trim()
        if ($t.Length -gt 0) { [void]$ignoredNs.Add($t) }
    }

    $docLines = Get-DocLines -Root $DocsRootPath -LedgerPath $LedgerData.Path
    if ($docLines.Count -eq 0) {
        Add-Finding -Severity 'NOT-CHECKABLE' -Class 'DOCS-EMPTY' -Id '-' -Message "no markdown found under '$DocsRootPath', so the citation checks had nothing to read"
        return
    }

    $tokenRx = [regex]'(?<![A-Za-z0-9-])[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+(?![A-Za-z0-9-])'

    # --- orphan citation
    # Conservative by design. A token is a candidate only when it looks like a CITATION
    # rather than incidental shouting, which means one of:
    #   (a) its prefix belongs to a namespace the ledger itself uses (PROJ-957 -> PROJ-958), or
    #   (b) it is written in inline-code backticks, which is how the convention cites ids.
    # Everything else -- HTTP-GET, TODO-LATER, NOT-CHECKABLE -- is prose, and treating it as
    # a citation floods the first run, which is how this check gets switched off.
    # -OrphanScanBare widens (b) to every id-shaped token, for a deliberate audit pass.
    $codeSpanRx = [regex]'`+([^`]+)`+'
    $orphans = @{}
    foreach ($dl in $docLines) {
        $backticked = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($cs in $codeSpanRx.Matches($dl.Text)) {
            foreach ($ct in $tokenRx.Matches($cs.Groups[1].Value)) { [void]$backticked.Add($ct.Value) }
        }
        foreach ($m in $tokenRx.Matches($dl.Text)) {
            $tok = $m.Value
            if ($known.Contains($tok)) { continue }
            $tokPrefix = (($tok -split '-', 2)[0])
            if ($ignoredNs.Contains($tokPrefix)) { continue }   # never a ledger item
            # A BACKTICKED token alone is not enough -- backticks hold plenty of technical
            # strings (HMAC-SHA256, a regex class [A-Z], a FILL-ME placeholder). It counts
            # only when it is namespace-number shaped, e.g. PROJ-957.
            #
            # The prefix clause below is LOAD-BEARING and must not be dropped in favour of
            # the digits-only shape: most ids in a real ledger are word-shaped
            # (CONFIG-CONSOLIDATE, MAP-TITLE-FROM-BACKOFFICE), so a digits-only rule would
            # silently stop detecting stale citations of exactly those -- a recall loss
            # dressed up as a precision win. A backticked IMG-SOMETHING stays a candidate
            # because the ledger already knows the IMG namespace through IMG-DELETE.
            $isCandidate = $prefixes.Contains($tokPrefix) -or
                           ($backticked.Contains($tok) -and $script:NsNumberShape.IsMatch($tok)) -or
                           $OrphanScanBare
            if (-not $isCandidate) { continue }
            if (-not $orphans.ContainsKey($tok)) {
                $orphans[$tok] = "$([System.IO.Path]::GetFileName($dl.File)):$($dl.Line)"
            }
        }
    }
    foreach ($tok in ($orphans.Keys | Sort-Object)) {
        Add-Finding -Severity 'WARN' -Class 'ORPHAN-CITATION' -Id $tok -Message "cited at $($orphans[$tok]) but no ledger item claims it as an id or alias"
    }

    # --- state in prose
    if ($NoProseCheck) { return }
    if ($idShapedKnown.Count -eq 0) {
        Add-Finding -Severity 'NOT-CHECKABLE' -Class 'PROSE-NO-SYMBOLS' -Id '-' -Message 'no id-shaped symbols in the ledger, so the state-in-prose check could not run'
        return
    }

    $alternation = (($idShapedKnown | Sort-Object -Property Length -Descending | ForEach-Object { [regex]::Escape($_) }) -join '|')
    $knownRx = [regex]("(?<![A-Za-z0-9-])($alternation)(?![A-Za-z0-9-])")

    # A status assertion: a ticked/unticked checkbox, a `status:` field, or one of the
    # state words -- within roughly the same line as the citation. NEVER an emoji.
    $words = @($StateWords | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { [regex]::Escape($_.Trim()) })
    $assertPattern = '(?i)(^\s*[-*+]?\s*\[[ xX]\]|(?<![A-Za-z])status\s*:'
    # The hyphen in the lookarounds matters: without it, 'shipped' matches inside the id
    # SHIPPED-ONE and every mention of that item becomes a false positive.
    if ($words.Count -gt 0) { $assertPattern += '|(?<![A-Za-z-])(' + ($words -join '|') + ')(?![A-Za-z-])' }
    $assertPattern += ')'
    $assertRx = [regex]$assertPattern

    # Append-only history may record PAST state: that is what a decision log, a phase journal
    # and an archive are FOR. Exempt from THIS check only -- still scanned for orphans.
    #
    # Each pattern is here on the same principle: the document is a frozen record of what was
    # true on a date, so the status assertions in it are correct and rewriting them would be
    # vandalism. `archive-*` was added after a de-statusing round moved 1,864 lines of prior
    # narration into docs/archive-status-history.md, carrying 14 checkbox and `Blocked`
    # assertions that all reported here.
    #
    # NOT a threshold to relax when the count looks high. qa-* was considered and REJECTED:
    # "closed" is not inferable from a filename, and a runbook asserting an item shipped is a
    # second home for a LIVE item's state.
    #
    # The INFO line below NAMES every skipped file, on every run. With three patterns that
    # matters more, not less -- it is what keeps this an exemption rather than a blind spot.
    $exemptFiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($null -ne $AppendOnlyDocs) {
        foreach ($dl in $docLines) {
            if ($exemptFiles.Contains($dl.File)) { continue }
            $leaf = [System.IO.Path]::GetFileName($dl.File)
            foreach ($pat in $AppendOnlyDocs) {
                if ([string]::IsNullOrWhiteSpace($pat)) { continue }
                if ($leaf -like $pat) { [void]$exemptFiles.Add($dl.File); break }
            }
        }
    }
    if ($exemptFiles.Count -gt 0) {
        $exemptNames = @($exemptFiles | ForEach-Object { [System.IO.Path]::GetFileName($_) } | Sort-Object)
        Add-Finding -Severity 'INFO' -Class 'PROSE-APPEND-ONLY-EXEMPT' -Id '-' -Message "state-in-prose skipped for $($exemptFiles.Count) append-only history document(s): $($exemptNames -join ', ')"
    }

    $seenProse = @{}
    foreach ($dl in $docLines) {
        if ($exemptFiles.Contains($dl.File)) { continue }
        $idHits = $knownRx.Matches($dl.Text)
        if ($idHits.Count -eq 0) { continue }
        $assert = $assertRx.Match($dl.Text)
        if (-not $assert.Success) { continue }
        foreach ($h in $idHits) {
            $key = "$($h.Value)|$($dl.File)|$($dl.Line)"
            if ($seenProse.ContainsKey($key)) { continue }
            $seenProse[$key] = $true
            $snippet = $assert.Value.Trim()
            Add-Finding -Severity 'WARN' -Class 'STATE-IN-PROSE' -Id $h.Value -Message "status assertion '$snippet' beside the id at $([System.IO.Path]::GetFileName($dl.File)):$($dl.Line) -- prose cites an item, it never states its state"
        }
    }
}

# ---------------------------------------------------------------- render

function Format-Cell {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '-' }
    return (($Text -replace '\|', '\|') -replace '\r?\n', ' ')
}

function Build-QueueBlock {
    param($LedgerData)

    $queue = @($LedgerData.Items | Where-Object {
            $s = [string](Get-Field $_ 'state')
            $s -eq 'open' -or $s -eq 'in-progress'
        })

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('<!-- Generated from the work ledger by work-ledger.ps1 -- do not hand-edit. -->')
    $lines.Add('')

    if ($queue.Count -eq 0) {
        $lines.Add('_No open items in the ledger._')
        return $lines
    }

    # 🔴 `priority` OVERRIDES EVERY COMPUTED ORDER, including the kind partition. Sorting by
    # severity alone sank a project's ten-item next feature to the bottom of the file,
    # because new work is honestly `severity: none`, and "do this first, then that" had
    # nowhere to live. Ranked items therefore lead, in the human's stated order.
    $ranked = @($queue | Where-Object { $null -ne (Get-PriorityOrNull $_) } | Sort-Object `
        @{ Expression = { Get-PriorityOrNull $_ } }, `
        @{ Expression = { [string](Get-Field $_ 'id') } })
    $unranked = @($queue | Where-Object { $null -eq (Get-PriorityOrNull $_) })

    $first = $true
    if ($ranked.Count -gt 0) {
        $first = $false
        $lines.Add('### Ranked - in the order stated')
        $lines.Add('')
        Add-QueueTable -Lines $lines -Rows $ranked -IncludePriority
    }

    $extraKinds = @($unranked | ForEach-Object { [string](Get-Field $_ 'kind') } |
        Where-Object { $script:KindOrder -notcontains $_ } | Sort-Object -Unique)
    $kinds = @($script:KindOrder) + $extraKinds

    $headings = @{
        'code' = 'Queue - code'; 'config' = 'Config'; 'infra' = 'Infra'
        'decision' = 'Decisions'; 'doc' = 'Docs'; 'qa' = 'QA'
    }

    foreach ($kind in $kinds) {
        $rows = @($unranked | Where-Object { [string](Get-Field $_ 'kind') -eq $kind })
        if ($rows.Count -eq 0) { continue }

        # severity descending, then size ascending, so the cheap dangerous things surface
        # first. id last, purely to make the order deterministic.
        $rows = @($rows | Sort-Object `
            @{ Expression = { $v = $script:SevOrder[[string](Get-Field $_ 'severity')]; if ($null -eq $v) { 99 } else { $v } } }, `
            @{ Expression = { $v = $script:SizeOrder[[string](Get-Field $_ 'size')]; if ($null -eq $v) { 99 } else { $v } } }, `
            @{ Expression = { [string](Get-Field $_ 'id') } })

        if (-not $first) { $lines.Add('') }
        $first = $false

        $h = $kind
        if ($headings.ContainsKey($kind)) { $h = $headings[$kind] }
        $lines.Add("### $h")
        $lines.Add('')
        Add-QueueTable -Lines $lines -Rows $rows
    }
    return $lines
}

function Add-QueueTable {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        $Rows,
        [switch]$IncludePriority
    )

    if ($IncludePriority) {
        $Lines.Add('| # | Item | Kind | Title | Severity | Size | State | Depends on | Waiting on | Detail |')
        $Lines.Add('|---|---|---|---|---|---|---|---|---|---|')
    }
    else {
        $Lines.Add('| Item | Title | Severity | Size | State | Depends on | Waiting on | Detail |')
        $Lines.Add('|---|---|---|---|---|---|---|---|')
    }

    foreach ($r in $Rows) {
            $deps = @(Get-AsArray (Get-Field $r 'dependsOn') | ForEach-Object { '`' + [string]$_ + '`' })
            $depCell = '-'
            if ($deps.Count -gt 0) { $depCell = ($deps -join ', ') }

            $w = Get-Field $r 'waitingOn'
            $waitCell = '-'
            if ($null -ne $w -and $w -is [pscustomobject]) {
                $waitCell = '{0} - {1} (since {2})' -f `
                    (Format-Cell ([string](Get-Field $w 'who'))),
                (Format-Cell ([string](Get-Field $w 'what'))),
                (Format-Cell ([string](Get-Field $w 'since')))
            }

            $detail = [string](Get-Field $r 'detail')
            $detailCell = '-'
            if (-not [string]::IsNullOrWhiteSpace($detail)) { $detailCell = '`' + (Format-Cell $detail) + '`' }

            $titleCell = Format-Cell ([string](Get-Field $r 'title'))
            $jira = [string](Get-Field $r 'jira')
            if (-not [string]::IsNullOrWhiteSpace($jira)) { $titleCell = "$titleCell ($(Format-Cell $jira))" }

        $sevCell = Format-Cell ([string](Get-Field $r 'severity'))
        $sizeCell = Format-Cell ([string](Get-Field $r 'size'))
        $stateCell = Format-Cell ([string](Get-Field $r 'state'))
        $idCell = '`' + [string](Get-Field $r 'id') + '`'

        if ($IncludePriority) {
            $Lines.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} |' -f `
                    (Get-PriorityOrNull $r),
                $idCell,
                (Format-Cell ([string](Get-Field $r 'kind'))),
                $titleCell, $sevCell, $sizeCell, $stateCell, $depCell, $waitCell, $detailCell))
        }
        else {
            $Lines.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} |' -f `
                    $idCell, $titleCell, $sevCell, $sizeCell, $stateCell, $depCell, $waitCell, $detailCell))
        }
    }
}

function Invoke-Render {
    param($LedgerData, [string]$IntoPath)

    if ([string]::IsNullOrWhiteSpace($IntoPath)) {
        Fail-Hard '-Into is required with -Render. Pass the markdown file holding the generated markers.'
    }
    if (-not (Test-Path -LiteralPath $IntoPath)) { Fail-Hard "-Into file not found: $IntoPath" }
    $target = Get-Item -LiteralPath $IntoPath
    if ($target.PSIsContainer) { Fail-Hard "-Into must be a file, not a directory: $IntoPath" }

    $bytes = $null
    try { $bytes = [System.IO.File]::ReadAllBytes($target.FullName) }
    catch { Fail-Hard "-Into file could not be read: $IntoPath -- $($_.Exception.Message)" }

    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    if ($hasBom -and $text.Length -gt 0) { $text = $text.Substring(1) }

    $bi = $text.IndexOf($script:BeginMarker, [System.StringComparison]::Ordinal)
    $ei = $text.IndexOf($script:EndMarker, [System.StringComparison]::Ordinal)

    if ($bi -lt 0 -and $ei -lt 0) {
        Fail-Hard "no generated markers in $IntoPath. Insert both of these where the queue belongs, then re-run:`n         $($script:BeginMarker)`n         $($script:EndMarker)"
    }
    if ($bi -lt 0) { Fail-Hard "found the END marker but not the BEGIN marker in $IntoPath. Refusing to guess where the block starts." }
    if ($ei -lt 0) { Fail-Hard "found the BEGIN marker but not the END marker in $IntoPath. Refusing to guess where the block ends." }
    if ($ei -lt $bi) { Fail-Hard "the END marker precedes the BEGIN marker in $IntoPath. Fix the markers by hand." }
    if ($text.IndexOf($script:BeginMarker, $bi + $script:BeginMarker.Length, [System.StringComparison]::Ordinal) -ge 0) {
        Fail-Hard "more than one BEGIN marker in $IntoPath. Refusing to guess which block to regenerate."
    }
    if ($text.IndexOf($script:EndMarker, $ei + $script:EndMarker.Length, [System.StringComparison]::Ordinal) -ge 0) {
        Fail-Hard "more than one END marker in $IntoPath. Refusing to guess which block to regenerate."
    }

    # Line ending: whatever the file already uses, so the diff stays inside the block.
    $crlf = ([regex]::Matches($text, "`r`n")).Count
    $lf = ([regex]::Matches($text, "(?<!`r)`n")).Count
    $eol = "`n"
    if ($crlf -gt 0 -and $crlf -ge $lf) { $eol = "`r`n" }

    $before = $text.Substring(0, $bi)          # everything up to the BEGIN marker
    $after = $text.Substring($ei)              # the END marker and everything after it

    $body = ((Build-QueueBlock -LedgerData $LedgerData) -join $eol)
    $new = $before + $script:BeginMarker + $eol + $body + $eol + $after

    if ($new -eq $text) {
        Write-Output "RENDER  unchanged  $($target.FullName)"
        return
    }

    $enc = New-Object System.Text.UTF8Encoding($hasBom)
    try { [System.IO.File]::WriteAllText($target.FullName, $new, $enc) }
    catch { Fail-Hard "-Into file could not be written: $IntoPath -- $($_.Exception.Message)" }

    Write-Output "RENDER  updated  $($target.FullName)"
}

# ---------------------------------------------------------------- main

if ($Help) { Show-Usage; exit 0 }

if (-not $Validate -and -not $Render) {
    Show-Usage
    Write-Output ''
    Write-Output 'FATAL  choose a mode: -Validate or -Render.'
    exit 2
}
if ($Validate -and $Render) { Fail-Hard '-Validate and -Render are mutually exclusive; run the tool twice.' }
if ($Validate -and $PSBoundParameters.ContainsKey('Into')) { Fail-Hard '-Into applies to -Render only.' }
if ($StaleDays -lt 0) { Fail-Hard "-StaleDays must be zero or greater (got $StaleDays)." }

$ledgerData = Read-Ledger -Path $Ledger
$ledgerDir = [System.IO.Path]::GetDirectoryName($ledgerData.Path)

if ($Render) {
    Invoke-Render -LedgerData $ledgerData -IntoPath $Into
    exit 0
}

# ---- validate

$now = (Get-Date).Date
if (-not [string]::IsNullOrWhiteSpace($Today)) {
    $parsedToday = Parse-IsoDate $Today
    if ($null -eq $parsedToday) { Fail-Hard "-Today must be an ISO date such as 2026-09-08 (got '$Today')." }
    $now = $parsedToday.Date
}

$repoRootPath = Resolve-RepoRoot -LedgerPath $ledgerData.Path -Override $RepoRoot

$docsRootPath = $ledgerDir
if (-not [string]::IsNullOrWhiteSpace($DocsRoot)) {
    if (-not (Test-Path -LiteralPath $DocsRoot)) { Fail-Hard "-DocsRoot does not exist: $DocsRoot" }
    $docsRootPath = (Get-Item -LiteralPath $DocsRoot).FullName
}

Invoke-SchemaChecks -LedgerData $ledgerData
Invoke-DependencyChecks -LedgerData $ledgerData
Invoke-DecisionChecks -LedgerData $ledgerData -RepoRootPath $repoRootPath -LedgerDir $ledgerDir
Invoke-WaitingOnChecks -LedgerData $ledgerData -Now $now -Days $StaleDays
if ($NoGitCheck) {
    Add-Finding -Severity 'NOT-CHECKABLE' -Class 'GIT-CHECK-SKIPPED' -Id '-' -Message '-NoGitCheck was passed, so drift against git was not computed'
}
else {
    Invoke-GitDriftCheck -LedgerData $ledgerData -RepoRootPath $repoRootPath
}
Invoke-CitationChecks -LedgerData $ledgerData -DocsRootPath $docsRootPath

$sorted = @($script:Findings | Sort-Object Rank, Class, Id, Message)
foreach ($f in $sorted) {
    Write-Output ('{0,-13}  {1,-27}  {2,-20}  {3}' -f $f.Severity, $f.Class, $f.Id, $f.Message)
}

$errors = @($sorted | Where-Object { $_.Severity -eq 'ERROR' }).Count
$warns = @($sorted | Where-Object { $_.Severity -eq 'WARN' }).Count
$nc = @($sorted | Where-Object { $_.Severity -eq 'NOT-CHECKABLE' }).Count
$info = @($sorted | Where-Object { $_.Severity -eq 'INFO' }).Count
Write-Output ('SUMMARY  items={0}  errors={1}  warnings={2}  not-checkable={3}  info={4}' -f $ledgerData.Items.Count, $errors, $warns, $nc, $info)

# INFO is information, not a finding, so it alone does not fail the run.
if (($errors + $warns + $nc) -gt 0) { exit 1 }
exit 0
