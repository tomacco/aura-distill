# distill-recent-agy -- aura-distill Time Index ("When" axis) for Antigravity (agy) sessions.
#
# Scans Antigravity brain transcripts
# (~/.gemini/antigravity-cli/brain/<conversation-id>/.system_generated/logs/transcript.jsonl)
# and buckets sessions on human mental timelines matching distill-recent conventions.
# Output is byte-identical to bin/distill-recent-agy.sh (parity enforced by
# tests/antigravity/run-parity-test.sh).
#
# Usage: distill-recent-agy.ps1 [-BrainDir DIR] [-NowMs EPOCH_MS] [-PerBucket N]
# Exit codes: 0 ok (including no transcripts), 2 brain dir not found.
[CmdletBinding()]
param(
    [string]$BrainDir = $null,
    [long]$NowMs = 0,
    [int]$PerBucket = 8
)
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$SEP = [string][char]0x00B7

$WD  = @('Mon','Tue','Wed','Thu','Fri','Sat','Sun')
$MON = @('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec')
$MONTH_FULL = @('JANUARY','FEBRUARY','MARCH','APRIL','MAY','JUNE','JULY',
                'AUGUST','SEPTEMBER','OCTOBER','NOVEMBER','DECEMBER')

function Format-Dt([datetime]$d) {
    $wd = $WD[([int]$d.DayOfWeek + 6) % 7]
    $hm = $d.ToString('HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
    '{0} {1:00} {2} {3}' -f $wd, $d.Day, $MON[$d.Month - 1], $hm
}

function Get-Monday([datetime]$d) {
    $d.Date.AddDays(-1 * (([int]$d.DayOfWeek + 6) % 7))
}

function Clean-Text([string]$s) {
    if (-not $s) { return '' }
    # Strip XML tags like <USER_REQUEST>, <ADDITIONAL_METADATA>, etc.
    $cleaned = [regex]::Replace($s, '<[^>]+>', ' ')
    ([regex]::Replace($cleaned, '[\x00-\x1F]', ' ') -split '\s+' | Where-Object { $_ }) -join ' '
}

function Convert-ToLocalDt([System.DateTimeOffset]$dto) {
    # Mirror the bash twin (python astimezone): a local-clock value outside the
    # representable range skips the FIELD instead of clamping to MaxValue.
    $offset = [System.TimeZoneInfo]::Local.GetUtcOffset($dto)
    $ticks = $dto.UtcTicks + $offset.Ticks
    if ($ticks -lt [datetime]::MinValue.Ticks -or $ticks -gt [datetime]::MaxValue.Ticks) { return $null }
    [datetime]::new($ticks, [System.DateTimeKind]::Unspecified)
}

function Get-BucketKey([datetime]$end, [datetime]$now) {
    $days = ($now.Date - $end.Date).Days
    if ($days -le 0) { return @(0, 'TODAY') }
    if ($days -eq 1) { return @(1, 'YESTERDAY') }
    $wk = [math]::Floor(((Get-Monday $now) - (Get-Monday $end)).Days / 7)
    if ($wk -eq 0) { return @(2, 'EARLIER THIS WEEK') }
    if ($wk -eq 1) { return @(3, 'LAST WEEK') }
    if ($wk -le 3) { return @(4, 'A FEW WEEKS AGO (2-3 wk)') }
    if ($wk -le 7) { return @(5, 'ABOUT A MONTH AGO (4-7 wk)') }
    if ($days -le 104) { return @(6, 'A COUPLE OF MONTHS AGO (2-3 mo)') }
    if ($days -le 182) { return @(7, 'A FEW MONTHS AGO (3-6 mo)') }
    $rank = 8 + ($now.Year * 12 + $now.Month) - ($end.Year * 12 + $end.Month)
    return @($rank, ('{0} {1}' -f $MONTH_FULL[$end.Month - 1], $end.Year))
}

# Resolve Brain directory
if (-not $BrainDir) {
    $userHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    $BrainDir = Join-Path (Join-Path (Join-Path $userHome '.gemini') 'antigravity-cli') 'brain'
}

if (-not (Test-Path $BrainDir)) {
    [Console]::Error.WriteLine("Antigravity brain directory not found at $BrainDir")
    exit 2
}

$now = if ($NowMs -gt 0) {
    [DateTimeOffset]::FromUnixTimeMilliseconds($NowMs).LocalDateTime
} else {
    [datetime]::Now
}

$sessions = [System.Collections.Generic.List[PSCustomObject]]::new()

$dirs = Get-ChildItem -Path $BrainDir -Directory -ErrorAction SilentlyContinue
foreach ($d in $dirs) {
    $transPath = Join-Path $d.FullName ".system_generated\logs\transcript.jsonl"
    if (-not (Test-Path $transPath)) { continue }

    # Fallback timeline when no step carries a parseable created_at
    $firstDt = $d.LastWriteTime
    $lastDt = $d.LastWriteTime
    $sawTs = $false
    $firstPrompt = ''
    $lastAssistant = ''
    $turnCount = 0

    try {
        $lines = Get-Content $transPath -ErrorAction Stop
    } catch {
        continue
    }
    foreach ($line in $lines) {
        if (-not $line) { continue }
        # This file is owned by Antigravity, not us: a malformed line, a
        # non-object record, or a missing/garbage field is skipped -- one field
        # skips the FIELD, never the whole record (twin contract: both
        # implementations skip identically, see distill-recent-agy.sh).
        $step = $null
        try { $step = $line | ConvertFrom-Json } catch { continue }
        if ($step -isnot [System.Management.Automation.PSCustomObject]) { continue }
        $turnCount++
        $props = $step.PSObject.Properties
        $createdAt = if ($props['created_at']) { $props['created_at'].Value } else { $null }
        # pwsh 7 ConvertFrom-Json pre-parses ISO strings into [datetime];
        # Windows PowerShell 5.1 leaves them as strings -- handle both.
        $dtVal = $null
        if ($createdAt -is [datetime]) {
            if ($createdAt.Kind -eq [System.DateTimeKind]::Utc) {
                $dtVal = Convert-ToLocalDt ([System.DateTimeOffset]::new($createdAt))
            } else {
                $dtVal = $createdAt
            }
        } elseif ($createdAt -is [System.DateTimeOffset]) {
            $dtVal = Convert-ToLocalDt $createdAt
        } elseif ($createdAt -is [string] -and $createdAt) {
            try {
                $dtVal = Convert-ToLocalDt ([System.DateTimeOffset]::Parse($createdAt, [System.Globalization.CultureInfo]::InvariantCulture))
            } catch { $dtVal = $null }
        }
        if ($null -ne $dtVal) {
            if (-not $sawTs) { $firstDt = $dtVal; $sawTs = $true }
            $lastDt = $dtVal
        }
        $type = if ($props['type']) { [string]$props['type'].Value } else { '' }
        $content = if ($props['content']) { $props['content'].Value } else { $null }
        if ($type -eq 'USER_INPUT' -and -not $firstPrompt -and $content -is [string] -and $content) {
            $firstPrompt = Clean-Text $content
        }
        if ($type -eq 'PLANNER_RESPONSE' -and $content -is [string] -and $content) {
            $lastAssistant = Clean-Text $content
        }
    }

    if (-not $firstPrompt) { $firstPrompt = "(No user input recorded)" }
    if ($firstPrompt.Length -gt 85) { $firstPrompt = $firstPrompt.Substring(0, 85) + '...' }
    if ($lastAssistant.Length -gt 90) { $lastAssistant = $lastAssistant.Substring(0, 90) + '...' }

    $sessions.Add([PSCustomObject]@{
        Id = $d.Name
        Start = $firstDt
        End = $lastDt
        Prompt = $firstPrompt
        LeftOff = $lastAssistant
        Turns = $turnCount
    })
}

if ($sessions.Count -eq 0) {
    Write-Host "No Antigravity transcripts found."
    exit 0
}

# Sort descending by End time, Id as deterministic tie-break (twin parity)
$sorted = $sessions | Sort-Object -Property End, Id -Descending

# Group into buckets
$bucketGroups = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[PSCustomObject]]]::new()
$bucketOrder = [System.Collections.Generic.List[string]]::new()

foreach ($s in $sorted) {
    $bk = Get-BucketKey $s.End $now
    $bucketLabel = $bk[1]
    if (-not $bucketGroups.ContainsKey($bucketLabel)) {
        $bucketGroups[$bucketLabel] = [System.Collections.Generic.List[PSCustomObject]]::new()
        $bucketOrder.Add($bucketLabel)
    }
    if ($bucketGroups[$bucketLabel].Count -lt $PerBucket) {
        $bucketGroups[$bucketLabel].Add($s)
    }
}

Write-Host "=== Antigravity Session Time Index ==="
Write-Host ""

foreach ($label in $bucketOrder) {
    Write-Host "## $label"
    foreach ($s in $bucketGroups[$label]) {
        $timeStr = Format-Dt $s.End
        $idShort = if ($s.Id.Length -gt 8) { $s.Id.Substring(0, 8) } else { $s.Id }
        Write-Host ("- [{0}] {1} {2} {3}" -f $idShort, $timeStr, $SEP, $s.Prompt)
        if ($s.LeftOff) {
            Write-Host ("    left off: {0}" -f $s.LeftOff)
        }
    }
    Write-Host ""
}
