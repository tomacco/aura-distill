# distill-lock -- owner-checked mutual exclusion for distillation runs that share one store.
#
# PowerShell twin of bin/distill-lock.sh: same lock file, line format, exit codes and output,
# so Claude Code, Codex and Antigravity runs exclude each other whichever script they call
# (parity: tests/lock/run-lock-tests.sh). The lock is {DISTILL_DIR}/.lock holding one line:
# "<owner> <epoch-seconds> <iso-utc>". It is created with FileMode.CreateNew (O_EXCL on Unix,
# CREATE_NEW on Windows), so exactly one caller wins; a reader that catches it before the line
# is written sees a fresh malformed lock, which counts as held. Only the owner can refresh or
# release it. A lock whose heartbeat is older than DISTILL_LOCK_STALE_SECONDS (default 300)
# can be taken over. Takeovers, near-stale heartbeats and releases run under a short-lived
# second lock ({DISTILL_DIR}/.lock.takeover), re-check the lock line under it, and replace the
# lock with an atomic rename, so the lock file never goes missing while someone could create it.
#
# Usage:
#   distill-lock.ps1 acquire   <owner> [--wait SECONDS]
#   distill-lock.ps1 heartbeat <owner> [step:N signals:M]
#   distill-lock.ps1 release   <owner>
#   distill-lock.ps1 status
# Exit codes: 0 ok, 1 held by another owner (after any --wait), 2 usage,
#             3 caller is not the owner (lock lost, stolen as stale, or never held).
$ErrorActionPreference = 'Stop'

$Dir    = if ($env:DISTILL_DIR) { $env:DISTILL_DIR } else { Split-Path -Parent $PSScriptRoot }
$Lock   = Join-Path $Dir '.lock'
$Mutex  = Join-Path $Dir '.lock.takeover'
$Status = Join-Path $Dir '.status'
$Stale  = if ($env:DISTILL_LOCK_STALE_SECONDS) { [int]$env:DISTILL_LOCK_STALE_SECONDS } else { 300 }
$Poll   = if ($env:DISTILL_LOCK_POLL_SECONDS)  { [double]$env:DISTILL_LOCK_POLL_SECONDS }  else { 2 }

function Show-Usage {
    $lines = Get-Content -LiteralPath $PSCommandPath
    $lines[10..16] | ForEach-Object { [Console]::Error.WriteLine(($_ -replace '^# ?', '')) }
    exit 2
}
$script:Msgs = [Collections.Generic.List[string]]::new()
function Say([string]$m) { $script:Msgs.Add($m) }
function Now { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
function Iso { [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ') }
function TmpName([string]$kind) { "$Lock.$kind.$PID.$([Guid]::NewGuid().ToString('N'))" }

# Returns @(owner, epoch) for the lock at $Path, or $null if there is none.
# An unreadable or malformed lock reads as owner "?" aged by its mtime, so it goes stale.
function Read-Lock([string]$Path = $Lock) {
    if (-not [IO.File]::Exists($Path)) { return $null }
    $line = $null
    try { $line = [IO.File]::ReadAllLines($Path) | Select-Object -First 1 } catch { }
    $f = @("$line".Trim() -split '\s+')
    if ($f.Count -ge 2 -and $f[1] -match '^\d+$') { return @($f[0], [long]$f[1]) }
    try {
        $mtime = [DateTimeOffset]::new([IO.File]::GetLastWriteTimeUtc($Path)).ToUnixTimeSeconds()
        return @('?', $mtime)
    } catch { return $null }
}

function Write-Status([string]$text) {
    $tmp = "$Status.tmp.$PID"
    [IO.File]::WriteAllText($tmp, "$text $(Iso)`n")
    Move-Over $tmp $Status
}

# Atomic replace. File.Move(src, dst, overwrite) exists on .NET Core 3+ (PowerShell 6+);
# Windows PowerShell 5.1 uses File.Replace, which needs the destination to exist.
function Move-Over([string]$src, [string]$dst) {
    if ($PSVersionTable.PSVersion.Major -ge 6) { [IO.File]::Move($src, $dst, $true) }
    elseif ([IO.File]::Exists($dst)) { [IO.File]::Replace($src, $dst, $null) }
    else { [IO.File]::Move($src, $dst) }
}

# Creates $Path only if absent and writes $line into it.
function New-ExclusiveFile([string]$Path, [string]$line) {
    try { $fs = [IO.FileStream]::new($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read) }
    catch { return $false }
    try { $b = [Text.Encoding]::ASCII.GetBytes($line); $fs.Write($b, 0, $b.Length) } finally { $fs.Dispose() }
    return $true
}

function Try-Create([string]$owner) { New-ExclusiveFile $Lock "$owner $(Now) $(Iso)`n" }

# The takeover mutex guards every change to an existing lock. It is held for milliseconds;
# one left by a crashed process is cleared after 30 seconds.
function Lock-Mutex {
    for ($i = 0; $i -lt 200; $i++) {
        if (New-ExclusiveFile $Mutex "$PID`n") { return $true }
        try {
            $m = [DateTimeOffset]::new([IO.File]::GetLastWriteTimeUtc($Mutex)).ToUnixTimeSeconds()
            if ([IO.File]::Exists($Mutex) -and ((Now) - $m) -ge 30) { [IO.File]::Delete($Mutex) }
        } catch { }
        Start-Sleep -Milliseconds 50
    }
    return $false
}
function Unlock-Mutex { try { [IO.File]::Delete($Mutex) } catch { } }

function Same-Lock($a, $b) { $a -and $b -and $a[0] -eq $b[0] -and $a[1] -eq $b[1] }

# Under the mutex: if the lock still reads $expected, atomically replace it with a fresh
# line for $owner.
function Replace-If($expected, [string]$owner) {
    if (-not (Lock-Mutex)) { return $false }
    $ok = $false
    try {
        if (Same-Lock (Read-Lock) $expected) {
            $tmp = TmpName 'swap'
            [IO.File]::WriteAllText($tmp, "$owner $(Now) $(Iso)`n")
            try { Move-Over $tmp $Lock; $ok = $true } catch { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        }
    } finally { Unlock-Mutex }
    return $ok
}

function Is-Stale([long]$epoch) { ((Now) - $epoch) -ge $Stale }
# Past half the stale window a waiter may be close to a takeover, so the owner refreshes
# through Replace-If and never blindly overwrites.
function Near-Stale([long]$epoch) { (((Now) - $epoch) * 2) -ge $Stale }

function Test-Owner([string]$owner) {
    if ($owner -notmatch '^[A-Za-z0-9._:-]+$') {
        [Console]::Error.WriteLine('distill-lock: owner must match [A-Za-z0-9._:-]+'); exit 2
    }
}

function Invoke-Heartbeat([string]$owner, [string[]]$rest, [switch]$Quiet) {
    $cur = Read-Lock
    if (-not $cur) { Say 'lost: lock not held'; return 3 }
    if ($cur[0] -ne $owner) { Say "lost: held by $($cur[0])"; return 3 }
    if (Near-Stale $cur[1]) {
        # A waiter may be taking this lock over right now. Refresh through the same
        # mutex-and-check path so we never overwrite a new owner's lock.
        if (-not (Replace-If $cur $owner)) { Say 'lost: stale lock taken over'; return 3 }
    } else {
        $tmp = TmpName 'beat'
        [IO.File]::WriteAllText($tmp, "$owner $(Now) $(Iso)`n")
        Move-Over $tmp $Lock
    }
    if ($rest -and $rest.Count -gt 0) { Write-Status ('running ' + ($rest -join ' ')) }
    if (-not $Quiet) { Say 'ok' }
    return 0
}

function Invoke-Acquire([string]$owner, [string[]]$rest) {
    $wait = 0
    if ($rest -and $rest.Count -gt 0) {
        if ($rest.Count -ne 2 -or $rest[0] -ne '--wait' -or $rest[1] -notmatch '^\d+$') { Show-Usage }
        $wait = [long]$rest[1]
    }
    $deadline = (Now) + $wait
    while ($true) {
        $cur = Read-Lock
        if (-not $cur) {
            if (Try-Create $owner) { Write-Status 'running'; Say 'acquired'; return 0 }
        } elseif ($cur[0] -eq $owner) {
            if ((Invoke-Heartbeat $owner @() -Quiet) -eq 0) { Say 'acquired (already held)'; return 0 }
        } elseif ((Is-Stale $cur[1]) -and (Replace-If $cur $owner)) {
            Write-Status 'running'; Say "acquired (took over stale lock from $($cur[0]))"; return 0
        }
        if ((Now) -ge $deadline) {
            $cur = Read-Lock
            if ($cur) { Say "held $($cur[0]) $((Now) - $cur[1])s" } else { Say 'held (contended)' }
            return 1
        }
        Start-Sleep -Milliseconds ([int]($Poll * 1000))
    }
}

function Invoke-Release([string]$owner) {
    $cur = Read-Lock
    if (-not $cur) { Say 'not held'; return 3 }
    if ($cur[0] -ne $owner) { Say "not owner: held by $($cur[0])"; return 3 }
    if (-not (Lock-Mutex)) { Say 'not owner: lock contended during release'; return 3 }
    try {
        if (-not (Same-Lock (Read-Lock) $cur)) { Say 'not owner: lock changed during release'; return 3 }
        [IO.File]::Delete($Lock)
    } finally { Unlock-Mutex }
    Write-Status 'idle'; Say 'released'; return 0
}

function Invoke-Status {
    $cur = Read-Lock
    if (-not $cur) { Say 'free'; return 0 }
    $age = (Now) - $cur[1]
    if (Is-Stale $cur[1]) { Say "stale $($cur[0]) ${age}s" } else { Say "held $($cur[0]) ${age}s" }
    return 0
}

if ($args.Count -lt 1) { Show-Usage }
$cmd = $args[0]
$rest = @($args | Select-Object -Skip 2)
switch ($cmd) {
    'acquire'   { if ($args.Count -lt 2) { Show-Usage }; Test-Owner $args[1]; $rc = Invoke-Acquire $args[1] $rest }
    'heartbeat' { if ($args.Count -lt 2) { Show-Usage }; Test-Owner $args[1]; $rc = Invoke-Heartbeat $args[1] $rest }
    'release'   { if ($args.Count -ne 2) { Show-Usage }; Test-Owner $args[1]; $rc = Invoke-Release $args[1] }
    'status'    { $rc = Invoke-Status }
    default     { Show-Usage }
}
$script:Msgs | ForEach-Object { [Console]::Out.WriteLine($_) }
exit [int]$rc
