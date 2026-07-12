# distill-recent -- aura-distill Time Index ("When" axis), derived view.
#
# PowerShell twin of distill-recent.sh -- output must stay byte-identical
# (tests/timeline/run-parity-test.sh enforces it). Aggregates history.jsonl
# into sessions bucketed on a human mental timeline; boundaries follow the
# temporal-memory literature -- see research/2026-07-11-time-index/mental-timelines.md.
# Per-session "left off:" (transcript-tail last assistant text) and header
# "LAST /distill:" staleness line are derived, best-effort, read-only.
#
# Usage: distill-recent.ps1 [-ClaudeHome DIR] [-NowMs EPOCH_MS] [-PerBucket N]
# Exit codes: 0 ok, 2 history.jsonl not found,
#             4 history.jsonl present but no line matched the expected schema
#               (upstream format may have changed -- fall back to transcripts).
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
    # invariant culture: ':' in HH:mm is a culture-sensitive time separator and
    # would render as '.' on e.g. Finnish hosts, breaking parity with the sh twin
    $hm = $d.ToString('HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
    '{0} {1:00} {2} {3}' -f $wd, $d.Day, $MON[$d.Month - 1], $hm
}
function Get-Monday([datetime]$d) {
    $d.Date.AddDays(-1 * (([int]$d.DayOfWeek + 6) % 7))
}
function Clean-Text([string]$s) {
    # regex, not a per-char loop: at 100k history lines the loop costs seconds
    if (-not $s) { return '' }
    ([regex]::Replace($s, '[\x00-\x1F]', ' ') -split '\s+' | Where-Object { $_ }) -join ' '
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

# Tail window for "left off:" extraction; must equal TAIL_BYTES in the sh twin.
$TAIL_BYTES = 262144

function Get-LeftOff([string]$home_, [string]$sid, [string]$project) {
    # Last assistant text of the session transcript -- how the session ENDED
    # (the status half of a "continue where we left off" query). Same
    # transcript-dir munging as Claude Code: non-alphanumerics become '-'.
    if (-not $project) { return '' }
    $dir = [regex]::Replace($project, '[^A-Za-z0-9]', '-')
    $path = Join-Path (Join-Path (Join-Path $home_ 'projects') $dir) ($sid + '.jsonl')
    $size = [long]0; $read = 0; $buf = $null
    try {
        $fs = [System.IO.File]::OpenRead($path)
        try {
            $size = $fs.Length
            $take = [int][Math]::Min($size, $TAIL_BYTES)
            [void]$fs.Seek($size - $take, [System.IO.SeekOrigin]::Begin)
            $buf = New-Object byte[] $take
            while ($read -lt $take) {
                $n = $fs.Read($buf, $read, $take - $read)
                if ($n -le 0) { break }
                $read += $n
            }
        } finally { $fs.Dispose() }
    } catch { return '' }  # transcript rotated/cleaned up -- best-effort field
    if ($read -le 0) { return '' }
    $lines = [System.Text.Encoding]::UTF8.GetString($buf, 0, $read) -split "`n"
    $stop = 0
    if ($size -gt $TAIL_BYTES) { $stop = 1 }  # first line of a mid-file window is cut
    for ($i = $lines.Count - 1; $i -ge $stop; $i--) {
        $line = $lines[$i]
        # cheap pre-filter before JSON-parsing potentially huge tool-result lines
        if ($line.IndexOf('"type":"assistant"') -lt 0) { continue }
        try { $d = $line | ConvertFrom-Json } catch { continue }
        if ($d -isnot [System.Management.Automation.PSCustomObject]) { continue }
        if (-not $d.PSObject.Properties['type'] -or $d.type -ne 'assistant') { continue }
        if (-not $d.PSObject.Properties['message'] -or -not $d.message) { continue }
        if ($d.message -isnot [System.Management.Automation.PSCustomObject]) { continue }
        if (-not $d.message.PSObject.Properties['content']) { continue }
        $c = $d.message.content
        $t = ''
        if ($c -is [string]) {
            $t = Clean-Text $c
        } elseif ($c -is [System.Array]) {
            # text must BE a string: a non-string "text" (e.g. 42) is corrupt
            # data, skipped identically by both twins (parity)
            $parts = foreach ($x in $c) {
                if ($x -is [System.Management.Automation.PSCustomObject] -and
                    $x.PSObject.Properties['type'] -and $x.type -eq 'text' -and
                    $x.PSObject.Properties['text'] -and $x.text -is [string]) { $x.text }
            }
            $t = Clean-Text (@($parts) -join ' ')
        } else { continue }
        if ($t) {  # tool-use-only records fall through to the previous text
            if ($t.Length -gt 150) { return $t.Substring(0, 150) + '...' }
            return $t
        }
    }
    return ''
}

function Get-LastDistillDate([string]$home_) {
    # last_updated stamp from the SPINE -- /distill rewrites it on every run,
    # so it doubles as a capture-lag marker for the staleness header.
    $spine = Join-Path (Join-Path $home_ 'distill') 'SPINE.md'
    try { $txt = [System.IO.File]::ReadAllText($spine) } catch { return $null }
    $m = [regex]::Match($txt, 'last_updated:\s*(\d{4}-\d{2}-\d{2})')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
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
$linesSeen = 0
foreach ($line in [System.IO.File]::ReadLines($hist)) {
    if (-not $line.Trim()) { continue }
    $linesSeen++
    try { $d = $line | ConvertFrom-Json } catch { continue }
    # valid JSON that isn't an object (null, 42, "str", [..]) must be skipped,
    # not crash: this file is owned by Claude Code, not us
    if ($d -isnot [System.Management.Automation.PSCustomObject]) { continue }
    if (-not $d.PSObject.Properties['sessionId'] -or -not $d.PSObject.Properties['timestamp']) { continue }
    $sid = $d.sessionId
    # timestamp must be numeric (parity with the python twin: strings are drift)
    $tsOk = $d.timestamp -is [int] -or $d.timestamp -is [long] -or $d.timestamp -is [double] -or $d.timestamp -is [decimal]
    if (-not $sid -or -not $tsOk) { continue }
    # numeric but out of range: corrupt line, skip not crash
    try { $t = From-Ms ([long]$d.timestamp) } catch { continue }
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

if ($linesSeen -gt 0 -and $sessions.Count -eq 0) {
    # Loud failure beats silently-wrong: an empty index here means the upstream
    # schema changed, not that the user has no history.
    [Console]::Error.WriteLine("distill-recent: parsed $linesSeen lines but recognized 0 sessions -- history.jsonl format may have changed (expected objects with display/timestamp/project/sessionId). Fall back to raw transcripts.")
    exit 4
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
$ld = Get-LastDistillDate $ClaudeHome
if ($ld) {
    # strictly-after: same-day-as-distill sessions are ambiguous, undercount
    # rather than cry wolf
    $d0 = [datetime]::ParseExact($ld, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture).Date
    $n = 0
    foreach ($kv in $sessions.GetEnumerator()) { if ($kv.Value.end.Date -gt $d0) { $n++ } }
    $word = if ($n -eq 1) { 'session' } else { 'sessions' }
    [void]$out.AppendLine('')
    [void]$out.Append(('LAST /distill: {0} -- {1} undistilled {2} since' -f $ld, $n, $word))
}
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
        $sid8 = if ($e[1].Length -gt 8) { $e[1].Substring(0, 8) } else { $e[1] }
        [void]$out.Append(('  {0} {5} {1,3} msgs {5} {2} {5} {3}{4}' -f (Format-Dt $e[0]), $s.prompts.Count, $sid8, $proj, (Get-Snippet $s.prompts), $SEP))
        $lo = Get-LeftOff $ClaudeHome $e[1] $s.project
        if ($lo) {
            [void]$out.AppendLine('')
            [void]$out.Append(('      left off: {0}' -f $lo))
        }
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
