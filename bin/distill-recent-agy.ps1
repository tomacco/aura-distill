# distill-recent-agy -- aura-distill Time Index ("When" axis) for Antigravity (agy) sessions.
#
# Scans Antigravity brain transcripts (~/.gemini/antigravity-cli/brain/*/logs/transcript.jsonl)
# and buckets sessions on human mental timelines matching distill-recent conventions.
#
# Usage: distill-recent-agy.ps1 [-BrainDir DIR] [-NowMs EPOCH_MS] [-PerBucket N]
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
    Write-Host "Antigravity brain directory not found at $BrainDir"
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

    $firstDt = $d.LastWriteTime
    $lastDt = $d.LastWriteTime
    $firstPrompt = ''
    $lastAssistant = ''
    $turnCount = 0

    try {
        $lines = Get-Content $transPath -ErrorAction Stop
        foreach ($line in $lines) {
            if (-not $line) { continue }
            try {
                $step = $line | ConvertFrom-Json
                if ($step.created_at) {
                    $dt = [DateTimeOffset]::Parse($step.created_at).LocalDateTime
                    if ($turnCount -eq 0) { $firstDt = $dt }
                    $lastDt = $dt
                }
                if ($step.type -eq 'USER_INPUT' -and -not $firstPrompt -and $step.content) {
                    $firstPrompt = Clean-Text $step.content
                }
                if ($step.type -eq 'PLANNER_RESPONSE' -and $step.content) {
                    $lastAssistant = Clean-Text $step.content
                }
                $turnCount++
            } catch {}
        }
    } catch {
        continue
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

# Sort descending by End time
$sorted = $sessions | Sort-Object -Property End -Descending

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
        Write-Host ("- [{0}] {1} {2} {3}" -f $s.Id.Substring(0, 8), $timeStr, $SEP, $s.Prompt)
        if ($s.LeftOff) {
            Write-Host ("    left off: {0}" -f $s.LeftOff)
        }
    }
    Write-Host ""
}
