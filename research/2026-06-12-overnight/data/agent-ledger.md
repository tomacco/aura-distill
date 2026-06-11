# Agent-spawn ledger — live model-tiering experiment (objective 2)

Every delegation this session is logged here as empirical data: what was delegated, to which
model tier, why, and how it turned out. The main loop is Fable 5 (expensive) — the experiment is
whether bulk work delegates cleanly to cheaper tiers with no quality loss at the synthesis level.

| # | Time | Model | Type | Task | Rationale | Outcome (filled on completion) |
|---|------|-------|------|------|-----------|-------------------------------|
| 1 | 00:18 | default (claude) | claude-code-guide | Rate-limit behavior + auto-continuation research | Specialized agent; factual doc lookup, no Fable needed | pending |
| 2 | 00:18 | sonnet | Explore | Map distill-benchmark repo structure | Mechanical exploration; conclusions-only return keeps main context lean | pending |
| 3 | 00:18 | opus | general-purpose | Memory-backend survey (web research) | Broad research + judgment; opus-grade, not mechanical, but not synthesis | pending |

## Main-loop context discipline (self-observations)

- Knowledge files read by main loop tonight: SPINE + 6 files ≈ 9.4k tokens (necessary; protocol).
- Avoided: reading distill-benchmark repo myself (delegated to #2), web research myself (#3).
- Anti-pattern to watch: re-reading agent transcripts (forbidden — completion summary only).
