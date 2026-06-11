# Overnight session watchdog — fires from Windows Task Scheduler every 30 min.
# If the live Claude session's heartbeat goes stale (rate-limit stall or crash),
# resume the most recent conversation headlessly. Layer 2 of the continuation
# mechanism (layer 1 = in-session cron heartbeat). See ../rate-limit-continuation.md.

$ErrorActionPreference = 'Stop'
$hb     = 'C:\Users\Ivan\.claude\overnight-heartbeat.txt'
$log    = 'C:\Users\Ivan\.claude\overnight-watchdog.log'
$staleMin = 75

function Log($msg) { Add-Content $log "[$(Get-Date -Format o)] $msg" }

$age = if (Test-Path $hb) { (New-TimeSpan -Start (Get-Item $hb).LastWriteTime -End (Get-Date)).TotalMinutes } else { [double]::MaxValue }

if ($age -lt $staleMin) { Log "heartbeat fresh (${age:n0} min) - no action"; exit 0 }

Log "heartbeat STALE (${age:n0} min) - attempting headless resume"
# Refresh sentinel FIRST so overlapping watchdog fires don't spawn parallel resumes;
# if this resume fails on a still-active rate limit, the next fire retries after 30 min.
Set-Content $hb -Value "watchdog-resume-attempt $(Get-Date -Format o)"

Set-Location C:\Users\Ivan
& C:\Users\Ivan\.local\bin\claude.exe --continue -p @'
WATCHDOG RESUME (automated; Ivan asleep until ~08:15). The interactive session stalled —
likely a rate limit that has now reset, or a crash. Read
C:\Users\Ivan\repos\aura-distill\research\2026-06-12-overnight\SESSION-LOG.md and resume
per its Resume protocol: continue the first non-DONE task, update SESSION-LOG.md and commit
to branch research/2026-06-12-overnight after each completed task. Refresh
C:\Users\Ivan\.claude\overnight-heartbeat.txt (Set-Content, ISO timestamp) every ~20 minutes
while you work. NEVER push to main. If the rate limit is still active this command will fail;
the watchdog will retry in 30 minutes.
'@ --permission-mode acceptEdits *>> $log

Log "headless resume exited with code $LASTEXITCODE"
