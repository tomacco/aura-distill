# Resume watchdog for the token-economics overnight research session.
# Pattern: ops/session-limits-continuation.md "Resume-watchdog v2" (validated 2026-07-07).
# Fires every 5 min via Task Scheduler. Resumes the interactive session headlessly ONLY if:
#   (a) the session transcript is stale (no writes for >= 15 min), AND
#   (b) RESEARCH-PLAN.md still has unchecked boxes, AND
#   (c) no previous resume attempt is still running.
# Rate-limited attempts fail fast and retry on the next tick -> auto-resume within ~5 min of reset.
# PS 5.1 compatible, ASCII only. DELETE the schtask when the research ships (plan box 10).

$ErrorActionPreference = 'Stop'

$SessionId  = 'd5ce833d-a019-4cc3-b789-acd99070f034'
$Transcript = 'C:\Users\Ivan\.claude\projects\C--Users-Ivan\d5ce833d-a019-4cc3-b789-acd99070f034.jsonl'
$PlanFile   = 'C:\Users\Ivan\repos\aura-distill-token-econ\RESEARCH-PLAN.md'
$ClaudeExe  = 'C:\Users\Ivan\.local\bin\claude.exe'
$WorkDir    = 'C:\Users\Ivan'
$LogFile    = Join-Path $PSScriptRoot 'watchdog.log'
$LockFile   = Join-Path $PSScriptRoot 'watchdog.lock'
$StaleMin   = 15

function Log([string]$msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $LogFile -Value "$ts  $msg"
}

Log 'tick'

# Guard: previous resume attempt still running?
if (Test-Path $LockFile) {
    $lockPid = (Get-Content $LockFile -TotalCount 1).Trim()
    $proc = $null
    try { $proc = Get-Process -Id $lockPid -ErrorAction Stop } catch {}
    if ($proc) { Log "skip: resume attempt PID $lockPid still running"; exit 0 }
    Remove-Item $LockFile -Force
}

# Gate (b): unchecked boxes in the plan?
if (-not (Test-Path $PlanFile)) { Log 'skip: plan file missing'; exit 0 }
$planText = Get-Content $PlanFile -Raw
if ($planText -notmatch '- \[ \]') { Log 'done: no unchecked boxes -- nothing to resume'; exit 0 }

# Gate (a): transcript stale?
if (-not (Test-Path $Transcript)) { Log 'skip: transcript missing'; exit 0 }
$ageMin = ((Get-Date) - (Get-Item $Transcript).LastWriteTime).TotalMinutes
if ($ageMin -lt $StaleMin) { Log ("fresh: transcript age {0:N1} min" -f $ageMin); exit 0 }

Log ("RESUMING: transcript stale {0:N1} min, plan has unchecked boxes" -f $ageMin)

$prompt = 'Watchdog auto-resume after a pause (likely session-limit reset). Read C:\Users\Ivan\repos\aura-distill-token-econ\RESEARCH-PLAN.md and continue the overnight token-economics research at the FIRST unchecked box. Check boxes only after artifacts exist; commit to the research branch after each box; never push main.'

Set-Location $WorkDir
$args = @('--resume', $SessionId, '-p', $prompt, '--dangerously-skip-permissions')
$p = Start-Process -FilePath $ClaudeExe -ArgumentList $args -WorkingDirectory $WorkDir `
     -RedirectStandardOutput (Join-Path $PSScriptRoot 'resume-stdout.log') `
     -RedirectStandardError  (Join-Path $PSScriptRoot 'resume-stderr.log') `
     -NoNewWindow -PassThru
Set-Content -Path $LockFile -Value $p.Id
Log ("spawned claude --resume as PID {0}" -f $p.Id)
$p.WaitForExit()
Log ("resume attempt exited with code {0}" -f $p.ExitCode)
Remove-Item $LockFile -Force -ErrorAction SilentlyContinue
