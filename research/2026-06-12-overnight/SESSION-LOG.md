# Overnight Research Session — 2026-06-12

> **AGENT DIRECTIVE — READ THIS FIRST.** If you are a Claude session resuming this work
> (after a rate limit, crash, or context loss): this file is the checkpoint. Read it fully,
> then continue from the **Current State** section below. Do NOT restart completed work.
> Branch: `research/2026-06-12-overnight` in `C:\Users\Ivan\repos\aura-distill`. NEVER push to main.

## Objectives (set by Ivan, 2026-06-12 ~00:10, asleep until ~08:15)

1. **Memory-backend research + test.** Answer: "what is the best approach for what we are doing?"
   Compare SPINE+flat-files (current) vs DB / vector DB / other techniques. Dimensions Ivan named:
   installation simplicity, no dependencies, token usage. Test using distill-benchmark methodology
   (`C:\Users\Ivan\repos\distill-benchmark`). Deliverable: research doc + benchmark data.
2. **Model-tiering mechanism.** Fable 5 is superb but SUPER expensive. Develop + test a mechanism to
   rely on Opus AND Sonnet strategically while keeping Fable 5 context small. Use distill itself as
   the context compressor (better than /compact). Deliverable: mechanism + research doc.
3. **Rate-limit auto-continuation.** Usage is high; if we hit the limit, work must continue
   automatically after reset. Build + document the mechanism. (This file is part of it.)

Constraints: push OK but NOT to main. Research docs required for everything. /distill authorized.

## Deliverables layout (this directory)

- `SESSION-LOG.md` — this checkpoint (update after every completed task)
- `memory-backends.md` — research doc, objective 1
- `model-tiering.md` — research doc, objective 2
- `rate-limit-continuation.md` — research doc, objective 3
- `data/` — measurements, agent-spawn ledger (objective 2 live data)

## Task list

| # | Task | Status |
|---|------|--------|
| 1 | Session setup (branch, log, clone benchmark) | DONE |
| 2 | Rate-limit continuation mechanism | DONE (see rate-limit-continuation.md; watchdog task + cron live) |
| 3 | Obj1: survey memory-backend approaches | DONE (opus agent; verdict: thin-index+files is the converged design; challengers = BM25 CLI + native CLAUDE.md control) |
| 4 | Obj1: measure token costs of current approach | DONE (data/token-costs-current.md) |
| 5 | Obj1: implement competitors + run benchmark | IN PROGRESS — competitors built+smoke-tested on branch bench/2026-06-12-backends of distill-benchmark; FULL RUN KILLED BY SESSION LIMIT (resets 2:50am local); poisoned results/2026-06-12 deleted; idempotent runner/resume-collection.sh ready; one-shot cron 6710b9f7 fires 02:56 to rerun → blind eval (EVAL_MODEL=opus) → aggregate |
| 6 | Obj1: research doc | in progress (draft pending benchmark numbers) |
| 7 | Obj2: design model-tiering mechanism | DONE (model-tiering.md — Fable-lean orchestration, routing table, distill-as-compressor) |
| 8 | Obj2: test mechanism | in progress (live ledger = evidence; tight-loop validation runs tonight — subagents WORK during the limit window, only headless is blocked) |
| 9 | Obj2: research doc | DONE pending test results fold-in (model-tiering.md) |
| 10 | Adversarial review + final report + /distill | pending |

## Current State (updated 00:50)

- Continuation mechanism LIVE: heartbeat cron `ba505a3d` + Task Scheduler `claude-overnight-watchdog`
  + sentinel `~/.claude/overnight-heartbeat.txt`. Teardown checklist in rate-limit-continuation.md.
- Token measurement done: fixed floor ~5.5k tokens/session (SPINE=3.6k), median file ~1k, KB=66k/49 files.
- distill-benchmark mapped (see agent ledger #2 result summary below): competitors = inject.sh+cleanup.sh
  auto-discovered; run via Git Bash with patches (CLAUDE_BIN → `~/.local/bin/claude.exe`, /tmp deps);
  tester profile CREATED+VERIFIED at `C:\Users\Ivan\.claude-tester` (copied .credentials.json works);
  jq installed via winget. Precedent for new-competitors-only runs: results/2026-05-18-v3 (engram only).
  Benchmark eval profile expected at `~/.claude-personal` — NOT yet created (same copy trick will work).
- Opus survey agent still running (memory-backend approaches). Next: design 1-2 challenger competitors
  from its shortlist, patch runner for Windows (branch in distill-benchmark, NOT main), run R1 smoke test,
  then full 25-test run per new competitor, blind eval, aggregate. Respect immutability: results/2026-06-12/.

## Key knowledge already loaded (don't re-derive)

- Benchmark v1: knowledge-graph scored 4.32 > aura-distill 4.21 > no-memory 2.98. KG is the contender.
- Benchmark pitfalls: run competitors SEQUENTIALLY; historical data immutable; versions from real
  releases only; bad data never reaches UI; evaluator needs strong numeric-score prompt.
- TIC metric = system_context_tokens + user_correction_tokens; breakeven ~4 interactions @ 2000 tokens.
- Always-on identity context HURTS (benchmark-validated); always-on = output rules only.
- Sub-agents can't write outside project dir; background agents can't write at all → all file writes
  happen in the foreground main loop.
- Delegation discipline (objective 2 practiced live): bulk exploration/research → sonnet; design-heavy
  reasoning → opus; synthesis/judgment/integration → main loop. Log every spawn in `data/agent-ledger.md`.

## Resume protocol

1. `git -C C:\Users\Ivan\repos\aura-distill status` — confirm branch `research/2026-06-12-overnight`.
2. Read Task list + Current State above; continue the first non-DONE task.
3. Update this file + commit after every completed task (small commits, this branch only).
4. Ivan wakes ~08:15 local — by then the final report must be the last message in the session,
   and this directory must contain the three research docs.
