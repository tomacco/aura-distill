# SESSION-LOG — token-economics overnight research (2026-07-08 → 09)

Append-only checkpoints. Resume protocol: read RESEARCH-PLAN.md, continue first unchecked box.

- 00:0x Worktree + branch `research/2026-07-08-token-economics` created off main.
- 00:0x Pricing verified via claude-api skill in a SUBAGENT — the lookup itself consumed
  ~328k subagent tokens for 4 numbers (live confirmation of the heavy-skill gotcha; kept as
  a data point for E4/pages).
- 00:02 Resume watchdog v2 deployed: schtask `AuraDistill-TokenEcon-ResumeWatchdog`
  (PS 5.1 absolute path), gates = transcript stale 15min + unchecked plan boxes; TEST-FIRED,
  log verified ("fresh" tick). DELETE at box 10.
- 00:1x Miner run: 35 transcripts, 33 sessions 2026-05-29→07-08, 3,360 requests, 656M tokens
  moved, $868 API-equiv (Fable $558 / Opus4.8 $310, no Sonnet/Haiku at all). Zero sidechain
  usage persists in project transcripts → all figures are main-loop FLOORS.
- 00:2x Stage-2: median resident ctx/request 153k (p90 389k); /distill main-loop median
  $1.31 × 12; SPINE Read in 17/33 sessions; naive friction scan found to be inflated 3-10x
  by knowledge-text-in-context — rebuilt to count only Bash/PowerShell/Edit tool_result
  matches.
- 00:3x Friction v2: env gotchas ~never recur after encoding (index.lock/NTFS/python3/
  ENOENT/cp1252); behavioral rule (Edit-before-Read) recurs 25x despite encoding —
  execution-gap quantified. Recovery cost per event: median 5-18k output tokens.
- 00:4x Web fan-out (3 agents + 1 sub-sweep) returned: Mem0 6pp-for-tokens trade; Anthropic
  84% claim; AgentDiet 40-60% redundancy; RouterArena "routers over-rely on strongest
  model"; memory-learned routing = whitespace. Synthesis committed.
- 00:5x E5 arithmetic: context movement ≈85% of cost (reads 51-57%, 1h writes 22-34%,
  output 15-21%); cap-60k sensitivity −57% (UNACHIEVABLE UPPER BOUND framing per review);
  distill all-in overhead ≈$50/window ≈5-6% of spend.
- 01:0x Designs E1-E5 pre-registered + committed; clean-context Opus adversarial review
  returned 17 findings (2 would have invalidated E3/E1); ALL fixes applied pre-run and
  committed (adversarial-review.md).
- 01:1x E1 battery launched (6 tasks × haiku/sonnet-5/opus-4.8 scored + fable ref; judge
  pinned fable; rubric-gate only). Diet SPINE authored by clean agent (5,455 chars ≈1.4k
  tok, 59/59 entries); held-out probes authored by second clean agent (6 probes, paraphrased).
- 01:2x E3 launched: 14 probes × full/diet × (N=2 held-out, N=1 secondary), model pinned
  opus-4-8, prompt-embedded SPINE (identical harness context both arms — parity).
- 01:5x E4 live subagent tally (tokens, from tonight's task usage tags): pricing-skill
  lookup 328k (heavy-skill gotcha re-confirmed); web-research agents 56k/58k/66-68k each
  (+2 child sweeps 46k/57k); adversarial reviewer 33k; diet-SPINE author 91k; probe author
  42k. Median ≈58k/agent; spawn floor alone ≈16-30k. Delegation is a QUALITY+context tool
  with a real fixed cost — consistent with the ≳30k-avoided-bulk break-even rule.
