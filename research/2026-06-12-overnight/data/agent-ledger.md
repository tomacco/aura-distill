# Agent-spawn ledger — live model-tiering experiment (objective 2)

Every delegation this session is logged here as empirical data: what was delegated, to which
model tier, why, and how it turned out. The main loop is Fable 5 (expensive) — the experiment is
whether bulk work delegates cleanly to cheaper tiers with no quality loss at the synthesis level.

| # | Time | Model | Type | Task | Rationale | Outcome (filled on completion) |
|---|------|-------|------|------|-----------|-------------------------------|
| 1 | 00:18 | default (claude) | claude-code-guide | Rate-limit behavior + auto-continuation research | Specialized agent; factual doc lookup, no Fable needed | DONE: 41k tok, 20 tools, 102s — sourced answers incl. June-15 SDK decoupling. ~2k tok returned |
| 2 | 00:18 | sonnet | Explore | Map distill-benchmark repo structure | Mechanical exploration; conclusions-only return keeps main context lean | DONE: 66k tok, 56 tools, 192s — complete operational map, enabled competitor build with zero main-loop repo reading. ~3k tok returned |
| 3 | 00:18 | opus | general-purpose | Memory-backend survey (web research) | Broad research + judgment; opus-grade, not mechanical, but not synthesis | DONE: 58k tok, 9 tools, 345s — dense cited survey, falsified vendor claims, produced challenger shortlist. ~3.5k tok returned |
| 4 | 01:05 | haiku | claude | Probe: do subagents work during session-limit window? | 1-call experiment | DONE: 16k tok (mostly system prompt), 1.4s — YES. Subagents alive while headless claude -p is limit-blocked |

## Cost summary so far

~181k subagent tokens consumed at sonnet/opus/haiku rates; ~8.5k tokens of conclusions entered
Fable context. Counterfactual: doing agents 1-3's work in the main loop would have put 165k+
tokens through Fable 5 at ~2.6-4.3x effective cost AND degraded every later turn.

## Anti-pattern caught live (recorded for the doc)

Main loop invoked the claude-api Skill directly for a pricing lookup → ~30k tokens of reference
material injected into Fable context for a 4-number answer. Correct move per the mechanism:
haiku/sonnet subagent invokes the skill, returns the numbers. Encoded as context-protection rule #2.

## Main-loop context discipline (self-observations)

- Knowledge files read by main loop tonight: SPINE + 6 files ≈ 9.4k tokens (necessary; protocol).
- Avoided: reading distill-benchmark repo myself (delegated to #2), web research myself (#3).
- Anti-pattern to watch: re-reading agent transcripts (forbidden — completion summary only).
