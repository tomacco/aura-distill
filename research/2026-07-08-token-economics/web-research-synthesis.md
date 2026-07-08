# Web research synthesis — token economics of memory + routing (July 2026)

Method: 3 parallel research agents (+1 spawned sub-sweep on commercial vendors), ≥2-source
verification where possible; single-source and vendor claims labeled. Full briefs preserved
in agent transcripts; this is the deduplicated synthesis. Date: 2026-07-09.

## 1. Do memory systems pay for themselves? (state of evidence)

- **Mem0** (arXiv 2504.19413): ~1.8-7k tokens/conversation vs ~26k full-context (>90%
  footprint cut) BUT the authors' own numbers show full-context SCORES HIGHER (72.9% vs
  66.9% J-score) — extraction-style memory trades ~6pp accuracy for token savings.
  Cross-vendor numbers (Mem0 vs Zep) are contested ±10-26pts in both directions — never cite
  orderings (confirms prior distill knowledge).
- **Anthropic context-editing + memory tool** (vendor-internal, claude.com/blog/context-management):
  100-turn agentic eval — context editing alone +29% performance; +memory tool: **84% token
  reduction**, +39% performance. Directional, not replicated.
- **AgentDiet** (arXiv 2509.23586): manual inspection of 100 real agent trajectories found
  redundant/wasteful content "in almost all"; trimming cut input tokens **39.9-59.7%**, total
  cost 21.1-35.9% with performance held. Best available proxy for what a memoryless agent
  wastes; "tokens burned re-deriving a previously-known fix" has never been isolated as a
  metric — a real gap our dataset partially fills (friction recurrence, F5).
- **Cost-aware forgetting** (arXiv 2505.16067): utility-based deletion shrank a memory 73%
  with NO performance loss — deleting low-utility memories sometimes BEATS keeping everything.
  Directly relevant to SPINE pruning policy.
- **Amortization**: universally asserted ("write once, read many"), never formalized. No
  published break-even-N. Our F4/F5 measurements are among the first real-usage numbers.
- **Context rot** (Chroma, 18 models): accuracy 0.92→0.68 as irrelevant context grows even
  far below the limit — the QUALITY reason to keep resident context lean, independent of cost.
- **Compaction hazard**: documented case of project instructions "followed perfectly before
  compaction, violated 100% after" (claude-code#9796) — auto-summarization is dangerous for
  [NON-NEGOTIABLE]/[DIRECTIVE] knowledge; verbatim fidelity matters there.

## 2. Claude Code harness economics (verified mechanics)

- Cache: 5m write ×1.25 (free auto-refresh on hit), 1h write ×2, read ×0.1; hierarchy
  tools→system→messages; **changing tool definitions invalidates everything**; model switch
  mid-session = full cache rewrite. Minimum cacheable prefix varies by model (512 for Fable 5).
- Session floor 20-30k tokens before the first user word (our data: median 29.8k) —
  CLAUDE.md + always-on rules are "paid every turn, forever" as cache reads.
- Documented extreme: single user telemetry with cache reads = **99.93% of token flow**
  (1310:1 vs I/O; claude-code#24147). Our dataset: ~150:1 — same shape.
- MCP tool-schema deferral ("Tool Search") cut one user's fixed context 51k→8.5k (−46.9%).
- Official levers (code.claude.com/docs/costs): /clear between tasks; heavy skills/verbose ops
  via subagents; CLI tools over MCP; hooks to pre-filter logs; /usage attribution.
- Subscription metering vs API $ is not apples-to-apples: cache reads are claimed not to count
  against plan limits (support.claude.com) yet one user's telemetry says they consumed quota —
  OPEN QUESTION; we therefore report tokens first, $ as API-equivalent counterfactual only.

## 3. Model routing (academic + commercial + harness)

- Academic routers: RouteLLM 85% cost cut at 95% GPT-4 quality (MT-Bench); FrugalGPT 50-98%;
  MixLLM 97% quality at 24% cost. BUT two independent 2026 benchmarks (RouterArena ~8.4k
  queries/12 routers; LLMRouterBench) find many routers fail to beat simple baselines under
  unified eval; commercial routers "over-rely on the strongest model" (Not Diamond ranked
  12/12 despite 20-40% marketing). Open-source routers: ~35% cost cut at <2% accuracy loss.
- Only 3 independent commercial data points exist: RouterArena (Azure 68.1% acc, weak on hard
  queries 17.9%), one 30-day Azure production test (~55% real savings, with real bugs:
  context capped by smallest pool model, cache hit-rate degraded by model churn), and status
  observations (Unify.ai router defunct; Cloudflare ML routing unshipped). Bedrock IPR:
  vendor-claimed 30-63%, $1/1k requests fee, English-only, can't learn from app data.
- Claude Code native levers: per-subagent `model:` frontmatter (docs explicitly endorse Haiku
  routing), `opusplan` alias, `/effort`, experimental Advisor tool (cheap main + strong
  advisor at decision points). Anthropic multi-agent post: Opus lead + Sonnet subs beat
  single Opus by 90.2% but at ~15x tokens — fan-out is a QUALITY tool that COSTS tokens.
- Task taxonomy (what survives downgrading): classification/extraction/format conversion/
  grep/boilerplate → near-zero gap (a 0.5B model beat a 72B on IMDB); multi-step math,
  long-context synthesis, sustained-constraint work (refactors, architecture, hard debugging)
  → keep frontier. In coding, no model dominates all dimensions — route by task domain.
- **Learned per-task routing from an agent's own experience logs: near-zero prior art.**
  Bandit-routing papers are benchmark-only (zero production deployments per the field's own
  2026 survey); two 2026 surveys (routing-side, memory-side) each have zero coverage of
  memory-learned routing; no framework ships it. Distill encoding routing rules from session
  retrospectives would be genuinely novel practice.

## 4. What this means for aura-distill (mapped to the decision frame)

FREE-WIN candidates (distill output unchanged):
- Keep SPINE as pointer-only index (already converged design); mechanical trigger-phrase
  compression IF E3 holds recall without over-reads.
- Distill-process runs in a subagent already — matches "heavy ops out of main loop" guidance.
- Add token telemetry to distill benchmark arms (measurement, no behavior change).

TRADE-OFF knobs (need explicit opt-in + consequence docs):
- Utility-based knowledge pruning/archiving (73%-shrink-no-loss result is task-agnostic
  evidence, not proof for OUR KB; risk: deleting the wrong tail).
- Cost-aware write policy (only encode if expected-reads × avoided-cost > write+carry cost);
  risk: undervaluing rare-but-catastrophic gotchas (one avoided RMA or data loss >> tokens).
- Routing hints as knowledge ([ROUTE] markers): novel, testable case-by-case; risk: stale
  hints as models change (staleness_threshold applies).

Hazards to encode regardless:
- Never auto-compact [NON-NEGOTIABLE]/[DIRECTIVE] entries (compaction-violation case).
- Model-switching mid-session breaks prompt cache (routing has a hidden cache cost inside
  ONE session; subagent-with-own-model avoids this — already distill's pattern).
