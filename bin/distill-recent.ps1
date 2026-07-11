# distill-recent -- aura-distill Time Index ("When" axis), derived view.
#
# PowerShell twin of distill-recent.sh -- output must stay byte-identical
# (tests/timeline/run-parity-test.sh enforces it). Aggregates history.jsonl
# into sessions bucketed on a human mental timeline; boundaries follow the
# temporal-memory literature -- see research/2026-07-11-time-index/mental-timelines.md.
#
# Usage: distill-recent.ps1 [-ClaudeHome DIR] [-NowMs EPOCH_MS] [-PerBucket N]
# Exit codes: 0 ok, 2 history.jsonl not found.
[CmdletBinding()]
param(
    [string]$ClaudeHome = $null,
    [long]$NowMs = 0,
    [int]$PerBucket = 8
)
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# Middle-dot separator built from its code point: PowerShell 5.1 reads
# BOM-less scripts as cp1252, so a literal non-ASCII char here would mojibake.
$SEP = [string][char]0x00B7

# Locale-independent names: must match distill-recent.sh exactly
$WD  = @('Mon','Tue','Wed','Thu','Fri','Sat','Sun')
$MON = @('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec')
$MONTH_FULL = @('JANUARY','FEBRUARY','MARCH','APRIL','MAY','JUNE','JULY',
                'AUGUST','SEPTEMBER','OCTOBER','NOVEMBER','DECEMBER')

function Format-Dt([datetime]$d) {
    $wd = $WD[([int]$d.DayOfWeek + 6) % 7]
    '{0} {1:00} {2} {3:HH:mm}' -f $wd, $d.Day, $MON[$d.Month - 1], $d
}
function Get-Monday([datetime]$d) {
    $d.Date.AddDays(-1 * (([int]$d.DayOfWeek + 6) % 7))
}
function Clean-Text([string]$s) {
    if (-not $s) { return '' }
    $chars = foreach ($ch in $s.ToCharArray()) { if ([int]$ch -lt 32) { ' ' } else { $ch } }
    (((-join $chars) -split '\s+') | Where-Object { $_ }) -join ' '
}
function Get-Snippet([System.Collections.ArrayList]$prompts, [int]$limit = 100) {
    $pick = ''
    foreach ($p in $prompts) { if ($p.Length -gt 25) { $pick = $p; break } }
    if (-not $pick) { foreach ($p in $prompts) { if ($p) { $pick = $p; break } } }
    if ($pick.Length -gt $limit) { return $pick.Substring(0, $limit) + '...' }
    return $pick
}
function Get-BucketKey([datetime]$end, [datetime]$now) {
    # Boundaries: day-precision 0-1d, week-precision to ~3wk (5+2 weekday
    # cycle), month-precision to ~6mo, then calendar months.
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
function From-Ms([long]$ms) {
    [DateTimeOffset]::FromUnixTimeMilliseconds($ms).LocalDateTime
}

if (-not $ClaudeHome) {
    $ClaudeHome = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
}
$hist = Join-Path $ClaudeHome 'history.jsonl'
if (-not (Test-Path $hist)) {
    [Console]::Error.WriteLine("distill-recent: $hist not found -- is this the right Claude config dir? (-ClaudeHome DIR)")
    exit 2
}
if ($NowMs -eq 0 -and $env:DISTILL_NOW_MS) { $NowMs = [long]$env:DISTILL_NOW_MS }
if ($NowMs -eq 0) { $NowMs = [DateTimeOffset]::Now.ToUnixTimeMilliseconds() }
$now = From-Ms $NowMs

$sessions = @{}
foreach ($line in [System.IO.File]::ReadLines($hist)) {
    try { $d = $line | ConvertFrom-Json } catch { continue }
    if (-not $d.PSObject.Properties['sessionId'] -or -not $d.PSObject.Properties['timestamp']) { continue }
    $sid = $d.sessionId
    if (-not $sid -or $null -eq $d.timestamp) { continue }
    $t = From-Ms ([long]$d.timestamp)
    if (-not $sessions.ContainsKey($sid)) {
        $proj = if ($d.PSObject.Properties['project'] -and $d.project) { $d.project } else { '' }
        $sessions[$sid] = @{ start = $t; end = $t; project = $proj; prompts = [System.Collections.ArrayList]@() }
    }
    $s = $sessions[$sid]
    if ($t -lt $s.start) { $s.start = $t }
    if ($t -gt $s.end)   { $s.end = $t }
    $disp = if ($d.PSObject.Properties['display'] -and $d.display) { $d.display } else { '' }
    [void]$s.prompts.Add((Clean-Text $disp))
}

$homeLeaf = Split-Path -Leaf ($HOME.TrimEnd('\', '/'))
$buckets = @{}
foreach ($kv in $sessions.GetEnumerator()) {
    $key = Get-BucketKey $kv.Value.end $now
    $bk = '{0:0000}|{1}' -f [int]$key[0], $key[1]
    if (-not $buckets.ContainsKey($bk)) { $buckets[$bk] = [System.Collections.ArrayList]@() }
    [void]$buckets[$bk].Add(@($kv.Value.end, $kv.Key, $kv.Value))
}

$out = New-Object System.Text.StringBuilder
[void]$out.AppendLine(('DISTILL TIME INDEX -- {0} sessions (newest first)' -f $sessions.Count))
[void]$out.Append(('NOW: {0}' -f (Format-Dt $now)))
foreach ($bk in ($buckets.Keys | Sort-Object)) {
    $label = $bk.Substring(5)
    $entries = @($buckets[$bk] | Sort-Object -Property @{ Expression = { $_[0] } }, @{ Expression = { $_[1] } } -Descending)
    [void]$out.AppendLine('')
    [void]$out.AppendLine('')
    [void]$out.Append(('== {0} ==' -f $label))
    $shown = 0
    foreach ($e in $entries) {
        if ($shown -ge $PerBucket) { break }
        $shown++
        $s = $e[2]
        $leaf = if ($s.project) { Split-Path -Leaf ($s.project.TrimEnd('\', '/')) } else { '' }
        $proj = if (-not $leaf -or $leaf -eq $homeLeaf) { '' } else { ('[{0}] ' -f $leaf) }
        [void]$out.AppendLine('')
        [void]$out.Append(('  {0} {5} {1,3} msgs {5} {2} {5} {3}{4}' -f (Format-Dt $e[0]), $s.prompts.Count, $e[1].Substring(0, 8), $proj, (Get-Snippet $s.prompts), $SEP))
    }
    $extra = $entries.Count - $PerBucket
    if ($extra -gt 0) {
        [void]$out.AppendLine('')
        [void]$out.Append(('  ... +{0} more sessions in this bucket' -f $extra))
    }
}
[void]$out.AppendLine('')
[void]$out.AppendLine('')
[void]$out.Append(('Transcript: {0}{1}projects{1}<project-dir>{1}<session-id>.jsonl -- resume: claude --resume <session-id>' -f $ClaudeHome, [System.IO.Path]::DirectorySeparatorChar))
[Console]::Out.WriteLine($out.ToString())
