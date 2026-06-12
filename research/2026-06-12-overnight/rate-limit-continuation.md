# Research: Auto-continuation across rate limits (Claude Code, Windows 11)

Status: mechanism DEPLOYED for tonight's session; doc complete. 2026-06-12.

## The problem

Usage on this account is high; a 5-hour-window or weekly usage limit can kill an unattended
session mid-task. Claude Code has **no built-in wait-and-retry**: no env var or setting makes an
interactive session pause-until-reset (confirmed against docs, 2026-06). Headless `claude -p`
emits `system/api_retry` events in `--output-format stream-json` but does not wait either.

## How limits actually work (facts, sourced)

- **Dual-layer limits for Claude Code**: 5-hour rolling window (starts at first message, resets
  automatically) + weekly compute cap. Both doubled on 2026-05-06; peak-hour reductions removed.
- **2026-06-15 (in 3 days): Agent SDK usage (`claude -p`) decouples from interactive limits** into a
  separate monthly credit (support article 15036540). Until then, headless calls and subagents draw
  from the same interactive pool. After the 15th, *delegating to headless/SDK runs becomes a
  rate-limit pressure-relief valve, not just a cost optimization.* Strategic for objective 2.
- In-session scheduled prompts (CronCreate): fire only while the REPL is idle and the session is
  alive. `durable: true` did NOT persist to disk in this session (returned "Session-only" —
  observed twice); treat in-session cron as dying with the session.
- Docs are explicitly silent on: interactive mid-turn limit behavior (fail vs pause), whether
  scheduled prompts queue across a limit stall. Treat as unknowns; design must not depend on them.

## The mechanism (two layers + checkpoint substrate)

**Substrate — git-committed checkpoint.** `SESSION-LOG.md` on the research branch holds objectives,
task table with statuses, current state, and a Resume protocol readable by ANY fresh session.
Committed after every completed task. This makes continuation stateless: nothing depends on the
original session's context surviving.

**Layer 1 — in-session heartbeat cron** (job `ba505a3d`, `11,37 * * * *`, off-minute per fleet
etiquette). Each fire: (a) refreshes a liveness sentinel `~/.claude/overnight-heartbeat.txt`,
(b) instructs resume-from-SESSION-LOG if the previous turn died. Covers: transient stalls,
rate-limit windows that reset while the session process is still alive. Cost: ~1 trivial turn / 26 min.

**Layer 2 — external watchdog** (Windows Task Scheduler `claude-overnight-watchdog`, every 30 min
for 9 h, user-level, no elevation). Runs `scripts/watchdog.ps1`:
1. If sentinel fresher than 75 min → exit (session alive; do nothing).
2. Else → refresh sentinel FIRST (prevents overlapping resume attempts), then
   `claude --continue -p "<resume prompt pointing at SESSION-LOG.md>" --permission-mode acceptEdits`
   from the session's working directory. If the limit is still active the call fails and the
   next fire retries — the retry loop lives OUTSIDE Claude, where it can't be rate-limited.
Covers: session death, long limit windows, machine-level interruptions (log: `~/.claude/overnight-watchdog.log`).

**Why sentinel-gated:** `claude --continue` forks the most recent conversation; firing it while the
interactive session is healthy would create two concurrent writers on one repo — exactly the
concurrency failure documented in NEXT-STEPS #12. The 75-min staleness gate (> 2 missed heartbeats)
makes the two layers mutually exclusive in practice.

## Verification tonight

- Tester-profile headless call succeeded (auth via copied `.credentials.json` — on Windows,
  Claude Code credentials are a plain file in the config dir; `CLAUDE_CONFIG_DIR` profiles work
  without interactive login, unlike macOS keychain-by-path).
- Watchdog task registered and `Ready`; dry logic path (fresh heartbeat → no action) exercised on
  first fire. Full stall path NOT provoked deliberately (would burn a turn + risk double-writer);
  the design degrades safely: worst case is "no resume until Ivan wakes", never a destructive action.

## Generalizable recipe (for distill / future sessions)

1. Checkpoint file in git with task table + resume protocol, updated per task. (Do this ALWAYS for
   unattended work; it's also what makes /compact-loss and crashes harmless.)
2. In-session recurring prompt for cheap liveness + self-resume.
3. OS-level scheduler + headless `--continue`, gated on a staleness sentinel, for true death.
4. After 2026-06-15: prefer pushing bulk work to SDK/headless runs to spare the interactive pool.

## POST-MORTEM (2026-06-12 morning): the mechanism FAILED in production — full RCA

**What happened:** the session limit hit ~01:15 (interactive session included — the subagent pool
that was alive at 01:05 drained shortly after). The session sat limit-paused until Ivan returned
~07:58. No layer resumed work after the 2:50 reset. ~5 hours of planned benchmark work lost.

**Why, layer by layer:**

1. **Layer 1 (in-session cron) — architecturally unable to help, now confirmed empirically.**
   Queued prompts do NOT execute while the client is limit-paused, and they did NOT flush at the
   2:50 reset. They flushed only on user interaction at ~07:58. Conclusion (new fact, was an
   "unknown" in the design doc): *in-session scheduling cannot survive an account-wide limit;
   interactive Claude Code stays paused until a human touches it.*
2. **Layer 2 (external watchdog) — the layer DESIGNED for exactly this — was dead on arrival.**
   Task Scheduler fired every 30 min all night; every run exited instantly with 0x80070002
   ("file not found"): the task action invoked bare `pwsh.exe`, which the Task Scheduler execution
   context could not resolve. The script never ran once; the log stayed empty. A working layer 2
   would have resumed at ~03:26.
3. **New failure mode found this morning:** the tester profile 401'd — a copied
   `.credentials.json` goes stale when the source profile refreshes its OAuth token. Copied-
   credential profiles must be re-copied at the start of each run window.

**Root cause (5-whys, systemic):** not the architecture — the deployment. The watchdog task was
registered but never test-fired. One `Start-ScheduledTask` + log check at registration would have
exposed the path bug in 30 seconds at 00:45. This is the execution-gap pattern: built the full
mechanism, skipped the verification step because the build "looked done".

**Encoded fixes:**
- Scheduled-task registrations MUST use absolute executable paths AND be test-fired immediately,
  with the log checked, before being trusted. (Applied below.)
- Auto-continuation across account limits requires an OS-level scheduler path; in-session
  scheduling is only good for stalls that leave the session responsive.
- Refresh copied-credential profiles at the start of every run window.

## Teardown (morning checklist)

- `Unregister-ScheduledTask -TaskName claude-overnight-watchdog -Confirm:$false`
- Delete `~/.claude/overnight-heartbeat.txt`, review `~/.claude/overnight-watchdog.log`
- CronDelete job `ba505a3d` (dies with session anyway)
