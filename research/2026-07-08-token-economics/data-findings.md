# Data findings — real-usage token economics (window 2026-05-29 → 2026-07-08)

Source: 35 local Claude Code transcripts (33 sessions with usage), 3,360 API requests,
main-loop only (subagent transcripts do not persist to `~/.claude/projects` — all totals are
FLOORS). $ = API-equivalent pricing (Fable $10/$50, Opus 4.8 $5/$25 per MTok; cache 1h-write
×2, read ×0.1). Actual billing is a Max subscription — subscription metering ≠ API $;
figures are counterfactual "what this usage would cost on the API".

## F1 — Volume & concentration
- Window total: **$868 API-equiv** (Fable $558, Opus 4.8 $310). No Sonnet/Haiku usage at all —
  confirms the "best model for everything" pattern.
- **Top 5 sessions = 69% of spend** ($595): deck/masterclass marathons + one aura-distill
  research overnight. The long tail (28 sessions) averages $9.75.
- Implication: routing SMALL sessions to small models is worth ~nothing; the lever lives
  INSIDE the big sessions (delegation of bulk phases, context hygiene).

## F2 — Cost anatomy: context movement is ~85% of cost
Per-request resident context: median **153k tokens**, mean 194k, p90 389k (May: 40k → June:
202k mean — context habits grew 5x in one month).
Decomposition (share of $): cache reads 0.51 (Fable) / 0.57 (Opus); 1h cache writes 0.34 /
0.22; output 0.15 / 0.21; fresh input 0.004.
**Generated work is ~15-20% of cost; ~85% is re-reading and re-writing context.**

## F3 — Counterfactual context caps (cost bounds, not behavior claims)
Holding output + fresh input constant, scaling cache traffic to a capped mean context:
cap 150k → save 19% · cap 100k → save 40% · cap 60k → save 57% ($496/window).
Assumption disclosed: linear scaling of cache traffic with resident context; capping context
can change behavior/quality — treat as upper-bound sizing of the lever, to be validated by
the harness-hygiene practices (aggressive /clear, subagent bulk work, leaner always-on context).

## F4 — Distill overhead, measured precisely
- Session-start floor: ~5.5k tokens (SPINE 3.6k + monitor); as one-off read: **$0.006/session**.
- SPINE carried in resident context every request: **$12.10/window** (1.4% of spend).
- `/distill` main-loop: 12 invocations, median **$1.31**, total $29.94 (3.4%).
- Distill subagent (invisible in transcripts): live samples this session put heavy subagents
  at 46-328k tokens; estimate +$6-18/window.
- **All-in distill overhead ≈ $50/window ≈ 5-6% of spend.**

## F5 — Distill savings, part 1: friction non-recurrence (measured)
Method: signature regexes over Bash/PowerShell/Edit tool_result output ONLY (v1 naive scan
over all text inflated counts 3-10x by matching knowledge-file text read into context — a
methodology trap worth publishing).
- Environment gotchas encoded in knowledge → recurrence after encoding ≈ ZERO:
  git index.lock (1 session, never again), NTFS colon paths (1), python3 stub (1),
  screenshot ENOENT (2 sessions Jun 9-10, never again), cp1252 Unicode (4 sessions, last
  event Jul 1, none after).
- Behavioral/protocol rules → encoding does NOT stop recurrence: "Edit before Read" harness
  error: **25 events across 7 sessions** spanning the whole window despite being encoded.
  Quantitative confirmation of the execution-gap thesis (craft/execution-gap.md): knowledge
  kills environment traps; it does not reliably change in-flight habits — those need
  structural checkpoints, not more prose.
- Recovery cost per friction event (output tokens from error → next user prompt; upper bound):
  median 5-18k output tokens ≈ $0.3-1.0 each. Friction non-recurrence saved roughly **$10-30**
  over the window — real, but small vs the context tax.

## F6 — Distill savings, part 2: what we CANNOT yet measure (honest gap)
The big claimed benefit — avoided re-derivation/re-exploration (session boots reading a 1k-token
knowledge file instead of re-discovering a subsystem) and avoided wrong turns in $150 marathon
sessions — has NO counterfactual in this dataset (we never run the same session without
knowledge). Existing distill-benchmark measures quality deltas, not token deltas.
→ Proposal: add token telemetry to the benchmark arms + a "tokens-to-outcome" metric.
→ Best external proxy: AgentDiet (arXiv 2509.23586) measured 40-60% of agent input tokens as
  redundant/wasteful; Anthropic's memory+context-editing eval reports 84% token reduction on
  100-turn tasks (vendor-internal).

## F7 — Retrieval compliance gap
SPINE read via Read tool in only **17 of 33 sessions**; knowledge-file retrievals: 36 total
(median file ~1k tokens — retrieval cost is trivial; the risk is UNDER-retrieval, not cost).
Most-read: SPINE (17), a craft file (6). Distill files were WRITTEN in main loop only 2x —
distill writes happen in the invisible subagent.

## F8 — /distill cost shape
The $15.23 outlier invocation (87k output over 28 requests) was a marathon-session distill;
median is $1.31. Distill cost scales with signal volume, not session cost — cheap sessions
distill cheap. No evidence that distill cost is a material drag at current cadence (12
invocations / 40 days).

## F9 — Model routing baseline
100% of tokens on the two most expensive models. Even without quality experiments, moving the
MECHANICAL slice of big sessions to subagents on cheaper models is bounded by F2: delegation
protects the main context (avoids growth → less cache traffic) — the delegation win is as much
a CONTEXT win as a unit-price win. Subagent spawn floor (~16.4k tokens, measured 2026-06-12)
sets the break-even: delegate only bulk ≳30k tokens.

## Classification per the user's decision frame
- FREE-WIN candidates (no distill-output change): scan-methodology fix for any future
  telemetry; retrieval-compliance instrumentation; benchmark token telemetry.
- TRADE-OFF knobs (need explicit user opt-in + consequences doc): diet SPINE (saves ~$8/window
  ↔ possible retrieval recall loss — E3 tests this); context-cap discipline (saves up to ~57%
  ↔ less ambient context in-session); routing mechanical work to small models (unit-price +
  context win ↔ quality risk on judgment tasks — E1 tests where the line is).
