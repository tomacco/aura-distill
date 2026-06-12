# Research: Memory backends for distill — what is the best approach?

Status: survey + measurements + benchmark design complete; benchmark scores land after the
2:50am rate-limit reset (section 6 placeholder). 2026-06-12.

## 1. The question

SPINE + flat markdown files is DEAD simple — zero dependencies, zero install, git-diffable.
Is it leaving something on the table (tokens, retrieval quality) versus a DB, a vector DB,
or another technique? Evaluated across Ivan's stated dimensions: installation simplicity,
dependency footprint, token usage — plus retrieval quality, write-path reliability,
auditability, scaling, and failure modes.

## 2. Headline answer (evidence-based, pre-benchmark)

**The current architecture is not outclassed — it is the converged industry design as of
mid-2026.** Three independent lines of evidence:

1. **Anthropic shipped the same architecture as Claude Code native auto-memory** (v2.1.59+):
   a MEMORY.md index capped at 200 lines/25KB, auto-loaded at session start, with topic files
   read on demand. Thin-index + lazy markdown IS the endorsed pattern.
2. **File-based agents beat dedicated memory products on the standard benchmark.** On LoCoMo:
   a Letta agent that just greps/reads markdown scored 74.0% vs mem0's best graph variant 68.5%;
   mem0's own paper shows plain full-context (72.9%) beating every dedicated memory system.
   "Is Grep All You Need?" (arXiv 2605.15184): grep beat vector retrieval for every harness/model
   pair on LongMemEval-S (e.g. 93.1% vs 75.9%).
3. **The vector crossover is far away.** Semantic retrieval starts winning only when the
   effective KB exceeds what a model can usefully attend to (~30k-115k tokens, gated by
   "lost-in-the-middle" degradation from ~16-64k). Ivan's KB: 66k tokens total, ~5.5k fixed
   + ~1k/file on demand — one to two orders of magnitude below the crossover at the
   *per-session-loaded* level. (Caveat: ALL single-vendor memory-benchmark numbers are
   contested ±10-26 points; ordering claims are directional, not gospel.)

So the realistic challengers are not vector DBs or knowledge graphs. They are **variants of the
same family**: (a) BM25/FTS5 lexical search as the retrieval mechanism, (b) the do-nothing
native feature, (c) keeping files but hardening the trigger path.

## 3. Comparison matrix (full survey: see agent report summary, citations in §8)

| Approach | Install/deps | Always-on tokens | Retrieval | Write path (LLM-maintainable?) | Git-diffable | Verdict for distill |
|---|---|---|---|---|---|---|
| **SPINE + files (current)** | none | ~5.5k (rules 1.8k + SPINE 3.6k) | LLM reads index → file (~1k/hit) | yes — /distill, proven | yes | baseline; trigger-on-prose is its unique strength |
| **CC native auto-memory** | none (built-in) | MEMORY.md ≤200 lines | same architecture | yes — automatic | only if dir is in a repo | the "do nothing" control; machine-local, no curation discipline, no markers/confidence |
| **SQLite FTS5/BM25 CLI** | Python stdlib only | ~150 (tool rules) | tool call → top-k chunks (~300-800/hit) | files stay source of truth; DB is derived/rebuildable | yes (sources) | strongest challenger: ~5k always-on savings, finer-grained hits; costs a tool-call round-trip + reliance on the agent calling it |
| sqlite-vec hybrid (+ local embedder) | 43MB model + sqlite-vec | ~150 | semantic top-k | embed-on-write; model-swap = full re-embed | .db blob | NOT benchmarked tonight by design: literature predicts wins only on paraphrase queries at this scale; violates no-deps for marginal gain |
| Knowledge graph (MCP server-memory et al.) | Node pkg | whole-graph dump or per-query | substring node search; wins multi-hop only, LOSES single-hop −13% vs RAG | explicit tool calls; silent dup accumulation | JSONL ok | beat distill 4.32 vs 4.21 in benchmark v1 — but note its benchmark form injected a FLAT RULES SUMMARY (no real graph engine). Its win is a win for *concise always-on summaries*, not for graphs |
| mem0 / Letta / Zep (hosted) | Postgres+pgvector(+Neo4j) | — | API; full-context beats them on LoCoMo | LLM extraction pipelines, >600k tok/conv write cost (Zep) | no | dominated at this scale; deps alone disqualify |
| A-MEM / sleep-time compute (research) | embed store + LLM writes | — | 2× multi-hop, loses adversarial | heavy write path | partial | one idea worth stealing: offline consolidation ≈ what /distill already does |

## 4. Token economics (measured, data/token-costs-current.md)

- Fixed floor today: **~5.5k tokens/session** (CLAUDE.md 58 + rules/distill.md 1,823 + SPINE 3,638).
- Typical session: +2-6 files ≈ 2-7k more. Observed tonight: 9.4k total.
- SPINE is 66% of the floor and is no longer "80 small lines" — 3.6k tokens.
- BM25-CLI alternative: ~150 always-on + ~300-800/retrieval → breakeven after ~2 retrievals;
  saves ~4-5k/session *if* retrieval reliability holds (that's what the benchmark tests).
- BUT: the per-file granularity of the current approach carries coherence value — a domain file
  delivers the constraint AND its context/why. Chunked hits may score worse on applying knowledge
  correctly even when recall ties. (Benchmark categories B/C/P will show this.)

## 5. Benchmark design (running tonight)

Self-contained 4-way, 25 tests × 4 competitors, collection sonnet-pinned, blind eval opus-pinned,
new prototypes on `bench/2026-06-12-backends` branch of distill-benchmark:

- `no-memory` — control
- `distill` — current rules v1.1.4 + SPINE + 5 knowledge files
- `claude-md-native` — SAME knowledge, native CLAUDE.md ~120-token index, no protocol.
  *Isolates: what do distill's 1.9k protocol tokens actually buy?*
- `sqlite-bm25` — SAME knowledge behind a real FTS5 CLI (stdlib-only, sources hidden).
  *Isolates: tool-retrieval vs index-read, and the always-on savings vs reliability trade.*

Not merged with May runs (different Claude version + default model — incomparable).
First attempt killed by the session limit after 3 calls (00:25); idempotent resume armed for 02:56.

## 6. Benchmark results

> PENDING — collection rerun scheduled 02:56 local, blind eval (opus) + aggregate after.
> Fill in: per-category scores, head-to-heads distill vs claude-md-native (protocol value)
> and distill vs sqlite-bm25 (architecture choice), tool-call reliability rate of sqlite-bm25,
> output-length/latency comparison.

## 7. Recommendation (to finalize after §6)

Pre-registered interpretation rules, so results can't be vibes-read after the fact:

1. **If distill ≥ both challengers overall** → keep architecture; act on token findings only:
   diet the SPINE (3.6k → aim ≤2k: trim per-line "when to read" prose, move detail into files)
   and trim rules/distill.md. No mechanism change.
2. **If claude-md-native ties distill** (within ~0.15 overall) → the protocol text isn't earning
   its 1.9k tokens on benchmark-shaped tasks; keep the protocol for its real-world functions
   (markers, confidence, memory-pressure, /distill write path) but slim the always-injected rules
   aggressively — the benchmark says the model doesn't need most of it to USE knowledge.
3. **If sqlite-bm25 wins retrieval but loses correction/bias** → hybrid: keep files+SPINE as
   source of truth, add the ~40-LoC BM25 CLI as a *derived index* for trigger-hardening
   (UserPromptSubmit hook searches and surfaces candidate files) — NEXT-STEPS-compatible, zero deps.
4. **If sqlite-bm25 wins outright** → bigger conversation: the index belongs in a tool, not in
   context. Prototype palinode-style operation-based writes before committing.

Either way: **vector DBs, graphs, and hosted memory layers are ruled out at this scale** —
on evidence, not taste. Revisit the vector question only if the KB grows ~10× (≥500 entries)
or multi-author vocabulary drift appears (the two regimes where lexical match degrades).

## 8. Sources

Full citation list in the survey (agent #3, see data/agent-ledger.md): mem0 paper
arXiv 2504.19413, Zep correction github.com/getzep/zep-papers/issues/5, "Is Grep All You Need?"
arXiv 2605.15184, Letta benchmark letta.com/blog/benchmarking-ai-agent-memory, A-MEM
arXiv 2502.12110, sleep-time compute arXiv 2504.13171, CC native memory code.claude.com/docs/en/memory,
sqlite-vec alexgarcia.xyz, Databricks long-context RAG, anthropic.com/engineering/effective-context-engineering.
Reliability flags: vendor LoCoMo numbers contested; per-retrieval token claims vendor-asserted —
which is why we measure ourselves (§4) and run our own benchmark (§5/§6).
