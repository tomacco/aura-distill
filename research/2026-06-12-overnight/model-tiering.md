# Research: Strategic model tiering — Fable 5 lean, Opus/Sonnet for bulk

Status: mechanism designed, exercised live all session (data/agent-ledger.md), and validated
with N=2 clean-context agents (tight-loops methodology): 3/5 routing cases reproduced identically,
2 ambiguities surfaced and encoded as the routing modifiers below. 2026-06-12.

## The problem

Fable 5 is the best available model and the session orchestrator — but it is SUPER expensive,
and every token that enters its context is paid at the top rate *and* consumes the shared usage
pool. The goal: keep Fable 5 as the brain while Opus/Sonnet/Haiku do the bulk work, and keep the
Fable context from growing.

## Economics (from the claude-api reference, 2026-06)

| Model | $/MTok in/out | Effective vs Fable* | Context | Role |
|---|---|---|---|---|
| Fable 5 (`claude-fable-5`) | $10 / $50 | 1.0× | 1M | Main loop ONLY |
| Opus 4.8 (`claude-opus-4-8`) | $5 / $25 | ~0.38× | 1M | Judgment-heavy delegation |
| Sonnet 4.6 (`claude-sonnet-4-6`) | $3 / $15 | ~0.23× | 1M | Bulk delegation default |
| Haiku 4.5 (`claude-haiku-4-5`) | $1 / $5 | ~0.08× | 200K | Mechanical lookups |

*Includes Fable's new tokenizer counting ~30% more tokens for identical content — its effective
premium over Opus is ~2.6×, over Sonnet ~4.3×. On subscription (not API billing) the same ratios
govern usage-limit consumption. Two structural facts sharpen this:

1. **Cache discipline**: switching the main-loop model mid-session invalidates the prompt cache.
   The officially documented workaround (agent-design guidance) is *exactly* the subagent pattern:
   "Spawn a subagent with the cheaper model for the sub-task; keep the main loop on one model."
   So tiering-via-subagents is not a hack — it is the sanctioned architecture.
2. **2026-06-15**: Agent SDK / headless usage decouples from interactive limits into a separate
   monthly credit. Delegation then also relieves rate-limit pressure, not just cost.

## The mechanism: Fable-lean orchestration

**Principle: Fable 5's context is the scarce resource. Nothing enters it that a cheaper model
could have read and summarized.** The main loop synthesizes, decides, and writes the final
artifacts; everything else is delegated with a conclusions-only return contract.

### Routing table

| Work type | Route to | Examples from this session |
|---|---|---|
| Mechanical/factual lookup | **haiku** subagent | version lookups, file inventories, format checks |
| Exploration & mapping | **sonnet** subagent (often `Explore` type) | distill-benchmark repo map (66k tokens spent in subagent, ~2k summary returned) |
| Web research sweeps, doc validation (tight-loops N=2), test execution | **sonnet** | clean-context artifact validation |
| Design-heavy research, judgment under ambiguity, adversarial review | **opus** | memory-backend survey (58k tokens in subagent, dense report returned) |
| Specialized factual agents | their default model | claude-code-guide (41k tokens, structured answer returned) |
| Synthesis, strategy, decisions, final writing, user intent | **Fable main loop** | research docs, run design, go/no-go calls |

### Routing modifiers (added after N=2 clean-agent tight-loop validation)

- **Compound tasks split, never escalate whole.** When work spans rows (explore + judge,
  research + recommend), the cheaper model does the bulk phase and returns a report; Fable (or
  opus) does the judgment phase ON the report. Both validators independently hit this gap:
  "survey npm and recommend two" routed sonnet by one, opus by the other. Rule: bulk → sonnet,
  recommendation happens at the report level.
- **Session mode scales the delegation bar.** Autonomous session (user away): delegate per the
  table. Interactive session: a spawn costs 30s-6min of the USER's time — answer small things
  directly; delegate only work that takes minutes regardless.
- **Already-in-context exemption.** If the answer verifiably sits in main-loop context, answer
  directly. The protection rules guard against LOADING content, not against USING what's loaded.
- **The <200-line read threshold is a proxy.** The real criterion is context persistence: don't
  pull anything into Fable context that later turns will re-attend to without benefit.

### Context-protection rules (main loop)

1. **Never read bulk content directly**: repo exploration, web pages, long transcripts, big logs
   → subagent reads, main loop gets the conclusion. Reading targeted small files is fine.
2. **Heavy skills are subagent work.** A reference skill load can inject 30k+ tokens for a
   4-number answer (measured this session with the claude-api skill — see ledger). If a skill is
   a lookup, spawn a haiku/sonnet agent to invoke it and return the distilled answer.
3. **Never re-read subagent transcripts** — the completion summary is the product.
4. **Batch independent delegations** in one message (parallel agents, single Fable turn).
5. **Commit checkpoints, not context**: long-running state lives in a git-tracked SESSION-LOG,
   not in conversation memory.

### Distill as the context compressor (the structural advantage)

Distill beats /compact at the three context-transfer problems, because its compression is
*curated, structured, and model-agnostic* while /compact is automatic, lossy, and session-local:

| Transfer problem | /compact | distill-based mechanism |
|---|---|---|
| Session start (who/what/constraints) | n/a — re-derive or paste | SPINE + domain files: ~5.5k fixed tokens buys weeks of accumulated context (measured) |
| Mid-session handoff to a subagent | paste context into prompt (paid at BOTH ends) | pass distill file PATHS; the agent reads them fresh — cheap input on the cheap model |
| Cross-session / post-crash continuation | summary trapped in the old session | SESSION-LOG.md checkpoint in git: any model tier, any session, can resume (proven tonight by the watchdog design) |
| Knowledge worth keeping | evaporates | /distill encodes it once; every future session pays only the read |

Concrete handoff pattern (used tonight): subagent prompts contain *references* ("read
`tests/seed-knowledge.md`", "the constraints are in SPINE section X") instead of inlined content.
The expensive model never pays output-tokens to retype what the cheap model can read.

### What stays on Fable (don't over-delegate)

- Final synthesis and anything the user will read as the deliverable.
- Decisions with taste/judgment under his conventions (Fable holds the accumulated session intent).
- Small targeted reads (<~200 lines) — a delegation round-trip costs more than the read.
- Anything requiring write access outside the project dir (subagents can't write there — ops/agent-patterns).

## Live evidence (this session's ledger, data/agent-ledger.md)

By the time of writing: 3 delegated agents consumed ~165k tokens at sonnet/opus/default rates and
returned ~6k tokens of conclusions into Fable context. Had the main loop done that work itself,
those ~165k tokens (plus tool-call intermediates) would have entered Fable 5 context at ~2.6-4.3×
the effective cost — and bloated the context that every subsequent Fable turn re-pays attention
over. The benchmark collection (100+ LLM calls) runs entirely OUTSIDE the session via the runner
(headless claude, sonnet-pinned) — zero Fable tokens per call.

## Adoption plan (proposed, pending Ivan)

1. Encode the routing table + context-protection rules as `craft/model-tiering.md` in distill
   (SPINE-indexed, loaded when orchestrating — NOT always-on; always-on stays output-rules-only
   per the benchmark-validated [NON-NEGOTIABLE]).
2. One-line pointer in always-on interaction rules is the maximum footprint, e.g.:
   "Bulk work (exploration/research/skill-lookups) → cheaper-model subagents; see craft/model-tiering.md."
3. SESSION-LOG checkpoint pattern becomes standard for any unattended/long session (template in
   rate-limit-continuation.md).
4. After 2026-06-15, prefer headless/SDK runs for batch workloads (separate usage pool).

## Open questions / risks

- Delegation latency: each agent spawn costs 30s-6min wall-clock. For interactive sessions the
  routing bar should be higher than for autonomous ones.
- Quality risk: sonnet summaries can miss subtleties Fable would catch. Mitigation: conclusions-only
  contracts must include "report anomalies/uncertainty explicitly"; judgment-heavy work goes to opus.
- Subagents can't prompt for permissions (background ones can't write at all) — write-work stays
  in the main loop regardless of model economics.
