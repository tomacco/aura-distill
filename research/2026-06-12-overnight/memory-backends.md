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

**Run-validity incident (2026-06-12 afternoon, two full datasets discarded):** the first two
"complete" collection runs were invalid for harness reasons, caught because a relevance-1 score
on an easy retrieval test triggered arm-level verification before publishing:
1. **Profile contamination**: `CLAUDE_CONFIG_DIR` as a POSIX path inside Git Bash is silently
   ignored by the Windows claude binary → every collection call ran with the REAL user profile
   (global CLAUDE.md + real distill rules + real SPINE), cross-contaminating all arms — the
   distill arm fatally (two conflicting rule sets; it consulted the real SPINE, found no Helios,
   answered knowledge-blind). Deeper: CLAUDE_CONFIG_DIR relocates only credentials/settings,
   NOT user-level memory — path form alone could never have isolated instructions.
2. **Unresolved `{DISTILL_DIR}` placeholder**: the injected repo-template rules were never
   sed-resolved (install.sh does this for real users), so even a clean agent chased a literal
   `{DISTILL_DIR}/SPINE.md`.
Fix (in the harness now): user-level memory disabled via `CLAUDE_CODE_DISABLE_CLAUDE_MDS=1` +
`CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`; every arm's instructions delivered through the SAME channel
(`--append-system-prompt-file`, arm payload + test context merged); placeholder resolved at
injection. Each arm smoke-verified end-to-end before the scored rerun. Methodology lesson:
**an easy test scoring 1 is an arm-validity alarm, not a finding — verify the arm, then trust
the score.** (Also recorded: v1 May runs used the real profile by design, so v1 distill numbers
inherit this contamination question too.)

**Design corrections after adversarial review (applied BEFORE the scored run):**
- **Style parity**: distill's injection appends an always-on output-style block that the
  user-model and proportionality rubrics directly reward (STYLE_MATCH, "penalty: >10 lines").
  The identical block is now injected into claude-md-native and sqlite-bm25, so the ONLY
  difference between arms is the retrieval mechanism. Without this fix the protocol-value
  contrast was unidentifiable.
- **Provenance**: the injected distill rules are a verbatim copy of main @ v1.1.4 (repo template,
  ~1.7k tokens); the 1,823-token figure in §4 is the user-installed copy with the Always-On
  section populated. A stale "v2 branch" comment in inject.sh said otherwise; fixed.
- **Builder-chosen parameters disclosed** (sqlite-bm25 was built by the same author who maintains
  distill): k=5, OR-only token matching (no AND/phrase fallback), chunking at `##` section level,
  sources hidden (tool is sole access path). These choices plausibly disadvantage the challenger;
  any bm25 loss on coherence/precision should trigger a sensitivity re-run (k=8, AND-first) before
  being believed.
- **Power**: single run per cell, integer 1-5 LLM-judge scores → one criterion flip moves a
  category mean by ~0.07-0.33. The benchmark reports DIRECTION and MAGNITUDE; it cannot resolve
  differences below the (unmeasured) judge noise floor. Conclusions phrased accordingly.

Not merged with May runs (different Claude version + default model — incomparable; note the v1
knowledge-graph "win" was itself an injected-summary artifact, so v1 cross-competitor orderings
should not be cited as mechanism evidence either).
First attempt killed by the session limit after 3 calls (00:25); rerun this morning post-fixes.

## 6. Benchmark results (clean-room run, 2026-06-12/13)

Seed-1 full 4-way (mean of 1-5 judge criteria, 29 tests, sonnet collection / opus judge):

| competitor | bias | correction | persistence | proportion. | retrieval | user-model | OVERALL |
|---|---|---|---|---|---|---|---|
| no-memory | 4.67 | 1.50 | 3.00 | 4.17 | 2.53 | 2.50 | **3.26** |
| claude-md-native | 4.00 | 3.58 | 4.17 | 4.67 | 4.47 | 3.83 | **4.11** |
| distill | 4.67 | 3.17 | 3.25 | 4.75 | 3.40 | 3.08 | **3.84** |
| sqlite-bm25 | 4.04 | 4.58 | 4.92 | 3.58 | 4.73 | 2.67 | **4.10** |

Critical pair, distill − claude-md-native across 3 seeds: **−0.28 / +0.01 / −0.68**
(mean −0.31, sd 0.35 → overall deficit is INSIDE the noise floor 2sd≈0.69; treat overall rank
as "distill not ahead", not as a measured loss). Direction-CONSISTENT per-category signals
(same sign all 3 seeds — these are the real findings):

- **bias: distill wins every seed** (+0.67/+0.42/+0.25) — the marker/confidence protocol
  measurably improves bias resistance. This is the protocol's earned value.
- **correction: distill loses every seed** (−0.42/−1.25/−2.42) — painful: correction durability
  is a core design goal, yet the one-line "⛔ = non-negotiable" legend in the native index
  outperformed the full protocol. bm25 WON corrections outright (4.58): search surfaces the
  ⛔ chunk verbatim at exactly the right moment.
- **persistence & user-model: distill loses every seed** (small-to-moderate).
- proportionality: distill ≥ native every seed (+0.08/+0.92/0.00); retrieval: mixed.

Other observations: every memory arm crushes no-memory (+0.6 to +0.9 — memory per se is not in
question). bm25 dominates knowledge-mechanics categories (correction/persistence/retrieval) but
collapses on judgment/style ones (user-model 2.67, proportionality 3.58 incl. a 1.67 outlier
where it dumped chunks instead of answering proportionately) — consistent with §4's coherence
prediction, in BOTH directions.

**Scope caveat (read before acting):** this benchmark measures the READ side only — single-shot
Q&A against pre-seeded knowledge. It does not measure distill's write path (/distill quality,
signal capture, compaction), cross-session accumulation, or trigger-on-prose in long sessions.
A read-side tie is an argument about the always-on rules, not about the system.

## 7. Recommendation — FINAL (pre-registered rules applied against §6)

Rule 1 (distill ≥ both) did NOT fire. Rule 2 (native ties/exceeds) FIRED on the
direction-consistent evidence; rule 3 (bm25 wins retrieval-mechanics) partially fired —
but bm25 wins corrections too, while losing judgment categories. Decision:

1. **Keep the architecture** (SPINE + files as source of truth) — every memory arm beat
   no-memory decisively; nothing here argues for vectors/graphs/hosted (§2 unchanged).
2. **Slim the always-on protocol aggressively.** The benchmark says the read-side does NOT
   need 1.9k tokens of protocol: a ~200-token index + a one-line ⛔ legend matched or beat it
   on corrections, persistence, user-model and retrieval. KEEP the bias-resistance and
   proportionality language (earned, 3/3 seeds). MOVE write-path machinery (memory pressure,
   origin tracking, confidence ladders) out of always-on context into the /distill-time docs
   where those mechanisms actually execute. Target: always-on ≤600 tokens, SPINE ≤2k.
3. **Steal bm25's correction trick**: corrections deserve guaranteed in-context placement, not
   protocol-mediated retrieval — e.g. a compact ⛔-table directly inside the SPINE (always
   loaded), keeping detail in decisions files. This addresses distill's worst consistent loss
   with ~100 tokens.
4. **Prototype to validate before shipping**: re-run this benchmark with a "distill-slim" arm
   (changes 2+3 applied) — the harness, arms, and analysis script are all reusable as-is.

These are read-side conclusions from a read-side benchmark (see §6 scope caveat); the write
path was not under test and no change to it is implied.

Interpretation rules fixed in advance so results can't be vibes-read after the fact — but per the
power caveat in §5, a rule only fires when the difference is directionally consistent across
categories, not on a single overall-mean gap (the ±0.15 band is a heuristic, not a derived bound):

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

On vectors/graphs/hosted layers: **no local test was run (excluded by design), so the honest
claim is weaker than "ruled out"**: contested external evidence consistently points away from
them at this scale, their dependency cost violates a hard requirement, and no surveyed result
shows them beating file-based approaches below the context-window crossover. Treat as
"no case for them today", and revisit if the KB grows ~10× (≥500 entries) or multi-author
vocabulary drift appears (the two regimes where lexical matching degrades).

## 8. Sources

Full citation list in the survey (agent #3, see data/agent-ledger.md): mem0 paper
arXiv 2504.19413, Zep correction github.com/getzep/zep-papers/issues/5, "Is Grep All You Need?"
arXiv 2605.15184, Letta benchmark letta.com/blog/benchmarking-ai-agent-memory, A-MEM
arXiv 2502.12110, sleep-time compute arXiv 2504.13171, CC native memory code.claude.com/docs/en/memory,
sqlite-vec alexgarcia.xyz, Databricks long-context RAG, anthropic.com/engineering/effective-context-engineering.
Reliability flags: vendor LoCoMo numbers contested; per-retrieval token claims vendor-asserted —
which is why we measure ourselves (§4) and run our own benchmark (§5/§6).
