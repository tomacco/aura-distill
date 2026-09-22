# Local models for aura-distill retrieval and distillation

**Status:** E1–E4 run · started 2026-09-22 · machine: Mac M5 Pro (16 cores, 48 GB unified) · all
runs local unless marked otherwise.

## Headline

1. The SPINE index read costs **21,247 tokens per session**, 2.3× what this project documented. It is
   the largest fixed cost of a distill session, paid before any work begins.
2. A **zero-model** router (BM25 rank-fusion over the index line *and* the file body) routes at
   **0.87 top-1 in 4.85 ms and 29 MB**. Injecting its top-3 into a real headless cell **measured
   −70% cache-creation tokens, −64% cost and one fewer round trip, at 3/3 correct** (E5).
3. **Laya lost to it on every arm** (best: 0.67) at 5.7 GB and 200× the latency — including on the
   calibrated-uncertainty property it was brought in for. Clean negative; see the verdict for the
   narrow claim that is actually supported.
4. The distillation pre-filter idea **died to arithmetic**: 82% of a transcript is tool traffic, so a
   user-turn classifier is aimed at 13% of the volume.

Nothing here is merged. The two shippable candidates — the router hook and the tool-traffic cap —
need an issue, a held-out eval on mined queries, and an independent review first.

## The question

aura-distill spends frontier-model tokens on two steps that may not need a frontier model:

1. **Retrieval.** Every session starts by reading `SPINE.md` (the knowledge index) and choosing which
   domain file to load. That is a classification over ~65 options.
2. **Distillation.** A `/distill` run reads a transcript and decides which turns carry durable signal.
   That is a filter before it is a synthesis.

If a small local model (Laya, Jev, or a quantized LLM) can do either step at equal quality, the
frontier model never pays for it. If it cannot, that is a result too — and the honest comparison
needs a **zero-model control**, because "free" is a real competitor.

## Foundations (measured, not estimated)

| # | Fact | Evidence | Holds |
| --- | --- | --- | --- |
| F1 | The SPINE read costs **21,247 tokens** (median of 4 cells: 21233 / 21242 / 21247 / 21249) | `cache_creation_input_tokens` on the message *after* the one that read `SPINE.md`, from 4 real headless baseline cells, `jev-distill-routing/tools/tokens.py` | YES |
| F2 | The project's own docs estimated ~9k for that read | `jev-distill-routing/README.md` | YES — **the real cost is 2.3× the documented estimate** |
| F3 | The routing decision itself takes **2.7 s median** (2.3–4.4) out of ~13 s end-to-end | arm-A baseline run 2026-09-21, `choose_s` | YES, n=4 |
| F4 | SPINE is 48,461 chars / 65 bullets; **2.281 chars per token** for this content | F1 ÷ char count | YES |
| F5 | The knowledge base is 97 files / 628k chars ≈ 275k tokens; median domain file ≈ 2.1k tokens | `tools/tokens.py` | YES |
| F6 | Laya runs on this Mac on the MPS backend: 3 checkpoints loaded, **55 ms for 4 questions in one forward pass** | `~/repos/laya-lab/smoke.py`, 2026-09-22 | YES |

F1 is the number the whole programme hangs on, and it was wrong in the repo before this run. **Read
of the index, not the answer, is the single largest fixed cost of a distill session.**

## Eval set

`jev-distill-routing/topics-eval.json` — 30 routing topics over the live 65-entry SPINE, two tiers:

- **easy (15)** — the request names a noun that also appears in the SPINE line (`pkill`, `WHEA`, `yfinance`).
- **hard (15)** — the request announces the action in the user's own words with the SPINE's distinctive
  nouns deliberately avoided (`"my gaming crashes are back"` → `ops/whea-crash-forensics.md`).

The tiers exist because a lexical router trivially wins the easy tier, and *only* the hard tier
distinguishes a model from string matching.

> **Limitation, stated up front.** These 30 topics were written by the agent running the experiment,
> not mined from Ivan's sessions (this Mac holds 9 sessions / 28 user turns — too few). Ground truth is
> one agent's reading of the SPINE. Treat the *ordering* of arms as the result and the absolute numbers
> as provisional until the set is replaced with mined real queries.

## E1 — zero-model control arms (done)

Pure Python BM25, no model, no network. Four retrieval surfaces and three rank fusions, all declared
before scoring and none re-tuned afterwards:

| arm | what it indexes | hit@1 all | easy | **hard** | hit@3 | MRR |
| --- | --- | --- | --- | --- | --- | --- |
| `bm25-title` | title + path only (a "diet" SPINE) | 0.43 | 0.73 | 0.13 | 0.53 | 0.499 |
| `bm25-full` | SPINE bullet: title + description + path | 0.60 | 0.93 | 0.27 | 0.77 | 0.721 |
| `bm25-hybrid` | max(full, body-2k), score-normalised | 0.60 | 0.93 | 0.27 | 0.83 | 0.726 |
| `rrf-full+body2k` | rank fusion of full + first 2k of each file | 0.67 | 0.93 | 0.40 | 0.83 | 0.749 |
| `bm25-body` | first 2k chars of the knowledge file | 0.70 | 0.93 | 0.47 | 0.77 | 0.750 |
| `bm25-bodyfull` | the whole knowledge file | 0.77 | 0.93 | 0.60 | 0.87 | 0.827 |
| `rrf-all3` | rank fusion of full + body-2k + bodyfull | 0.77 | 0.93 | 0.60 | 0.87 | 0.834 |
| **`rrf-full+bodyfull`** | **rank fusion of the SPINE line and the whole file** | **0.87** | 0.93 | **0.80** | **0.90** | **0.894** |

Cost of the winner, measured: **18 ms** to build both indexes over all 97 files, **4.85 ms** median per
query, **29 MB** peak RSS, zero network, zero GPU, no model file.

Three findings:

- **The index text is a worse retrieval key than the file content.** `bm25-bodyfull` beats `bm25-full`
  on the hard tier by 33 points with no model. A SPINE line is written to tell an agent *when to read*
  a file; that turns out not to describe what is in it.
- **A title-only SPINE collapses** (hard tier 0.27 → 0.13). Direct evidence for the existing
  `SPINE diet must preserve distinctive nouns` entry, and against shortening the index to save tokens.
- **Fusing the two surfaces beats either alone** — but only rank fusion does. Score-normalised
  `max()` (`bm25-hybrid`) added nothing, because BM25 scores from a 745-char document and a 6,000-char
  document are not on the same scale. Reciprocal-rank fusion never compares the scores.

### The shortlist mechanism (the actual candidate win)

Rather than *replacing* the router, shrink its input: rank the 65 bullets, inject only the top N, and
fall back to the full SPINE when the model reports none fit. Expected cost is
`N·(mean bullet + framing) + (1 − recall@N)·(SPINE + shortlist)`:

| N | recall@N (`bm25-full`) | E[tokens] | saving | recall@N (`rrf-full+bodyfull`) | E[tokens] | saving |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 0.60 | 9,001 | 58% | 0.87 | 3,120 | 85% |
| **3** | 0.77 | 6,186 | 71% | **0.90** | **3,232** | **85%** |
| 5 | 0.87 | 4,684 | 78% | 0.90 | 3,875 | 82% |
| 8 | 0.93 | 4,178 | 80% | 0.93 | 4,178 | 80% |

**This is the bar.** A local model must beat ~85% token saving at 0.87 top-1 accuracy, obtained for
5 ms and 29 MB. A model that merely matches it has lost, because it costs RAM, load time, a model
download and a dependency.

> **Overfitting caveat, stated before the numbers are used.** Eight arms were scored on 30 queries the
> same agent wrote. One topic is worth 3.3 points, so gaps under ~10 points are noise, and
> `rrf-full+bodyfull` winning by 10 over `bm25-bodyfull` is at the edge of it. The winner is hereby
> **pre-registered** for a held-out test against mined real queries; it is not to be re-tuned first.

## E2 — which mechanism, and what it is worth

Same measured constants, applied to three candidate mechanisms. `status-quo` = read the SPINE, choose,
read the file. `shortlist-N` = a hook injects the top-N SPINE *bullets*, the agent still chooses.
`inject-files-N` = a hook injects the top-N *file bodies*, so there is no SPINE read and no routing
turn at all. A miss (ground truth outside the top N) pays the shortlist **and** the status quo after it.

| mechanism | recall | E[tokens] | saving | round-trips saved |
| --- | --- | --- | --- | --- |
| status-quo | 1.00 | 23,917 | — | — |
| **shortlist-1** | 0.87 | **6,326** | **74%** | 0 |
| shortlist-3 | 0.90 | 6,425 | 73% | 0 |
| shortlist-8 | 0.93 | 8,102 | 66% | 0 |
| **inject-files-1** | 0.87 | 7,689 | 68% | **1 (≈2.7 s)** |
| inject-files-2 | 0.90 | 12,669 | 47% | 1 |
| inject-files-3 | 0.90 | 18,106 | 24% | 1 |

Injecting whole files stops paying past N=1 because knowledge files are large (median 2,670 tokens,
p90 8,182, max 15,897). So there are two different optima, and they are not the same mechanism:

- **Cheapest tokens: `shortlist-1`** — 74% off, the agent still makes the final call.
- **Lowest latency: `inject-files-1`** — 68% off *and* the routing decision and the file read both
  disappear from the critical path (~2.7 s of a ~13 s session, plus one round trip).

### What that is worth in money

At Opus 5 rates ($5/MTok input) with Claude Code's 1-hour cache TTL (2× write, 0.1× read), the SPINE
index costs **$0.21 to write and $0.011 per subsequent turn to re-read** — about **$0.41 for a
20-turn session**, before the agent has answered anything. A 74% cut is ~$0.30/session. Honest framing:
that is real for a heavy user and rounding error for a light one. **The latency is the better argument
than the dollars.**

## E2b — the zero-model router cannot tell when it is wrong

This is the result that changed what E3 is for.

A router is only safely cheap if it knows when to abstain: on a request the index does not cover, a
confident wrong route costs more than the full SPINE read it saved. So: does the winning router's
score separate its right answers from its wrong ones?

| signal | correct top-1 (median) | wrong top-1 (median) | separable? |
| --- | --- | --- | --- |
| fused RRF score | 0.03279 | 0.03252 | **no** — wrong max == correct max |
| rank1 − rank2 gap | 0.00079 | 0.00177 | **inverted** — the gap is *larger* when it is wrong |
| raw BM25 (best surface) | 18.1 | 11.4 | partly — ranges overlap (3.3–…, …–12.1) |

The first row is structural, not bad luck. RRF gives anything ranked first by both rankers exactly
`1/(k+1) + 1/(k+1)`, so the top of the scale is a **constant**. Rank fusion buys ordering and throws
away magnitude — which is precisely what a confidence signal is made of.

The raw BM25 score is a weak but usable **out-of-scope** detector. Calibrated against the 30 in-scope
queries plus 10 deliberately out-of-scope ones ("what's the weather", "write me a haiku", "hello"):

| threshold | keeps in-scope | rejects out-of-scope |
| --- | --- | --- |
| 6.0 | 30/30 | 6/10 |
| **7.5** | **28/30** | **10/10** |
| 9.0 | 26/30 | 10/10 |

7.5 is the knee, and the two in-scope queries it drops fall back to the full SPINE read — expensive,
never wrong. That asymmetry is what makes the whole mechanism safe.

**What no threshold here can do is catch a wrong pick on an in-scope request.** BM25 has no calibrated
notion of "this is probably not it". Laya does: it returns a calibrated probability and a separate
confidence per question, and it was trained for exactly that judgment.

So E3's question is no longer "can a 421M model beat BM25 on accuracy" — on this evidence it probably
cannot, and that would be a fine result. The question is now:

> **Can Laya supply the abstention signal that BM25 structurally lacks — at a cost worth paying?**

A model that routes no better but *knows when it is unsure* would let the shortlist mechanism fall
back exactly when it should, which is worth more than a few points of top-1.

**Answered, negatively.** Laya's probabilities do not separate its hits from its misses on any arm
(E3). The abstention problem is still open, and no mechanism tried here solves it.

## E3 — Laya as router and abstention oracle (RUN — clean negative)

Ran 2026-09-22 on MPS once the other agent freed the machine. Three arms, all scored on accuracy
**and** on whether their probabilities separate hits from misses (the E2b question):

| arm | top-1 | easy | hard | top-3 | latency | peak RSS | probability separates hit/miss? |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **zero-model BM25 rank-fusion** | **0.87** | 0.93 | **0.80** | 0.90 | **4.85 ms** | **29 MB** | no (structural, see E2b) |
| `laya-rerank` (BM25 top-10 → Laya choice) | 0.67 | 0.93 | 0.40 | 0.87 | 43.8 ms | 5,655 MB | no — miss max 0.92 > hit min 0.44 |
| `laya-hier` (section → file) | 0.40 | 0.60 | 0.20 | 0.60 | 238 ms | 5,653 MB | no — miss max 0.55 > hit min 0.19 |
| `laya-yn` (65 yes/no, one forward pass) | 0.17 | 0.13 | 0.20 | 0.27 | 1,895 ms | 5,683 MB | no — miss max 0.98 > hit min 0.69 |

**The 421M local model lost to 40 lines of BM25 on every arm, and lost on both properties.** It is not
that it routes worse but abstains better — its probabilities are no more diagnostic of its own errors
than the zero-model score is. Model load is ~50 s; peak RSS is ~5.7 GB, not the ~3 GB predicted from
parameter count (PyTorch/MPS allocator overhead plus a 65-item batch — the estimate was wrong by ~2×
and that error was reported to the agent whose memory it could have taken).

Three things the failures teach, in increasing order of transferability:

- **`laya-rerank` (best Laya arm) still destroys value.** BM25 hands it a top-10 containing the right
  answer 90% of the time and Laya reorders it down to 0.67 top-1. A reranker that is worse than its
  own input's ordering is worse than not reranking.
- **`laya-hier` shows where the loss happens:** easy tier 0.60 but hard tier 0.20. Section labels
  built from concatenated titles are exactly the "index text" surface E1 already showed is the weak
  retrieval key — the hierarchy inherits that weakness at the top of the tree, and a wrong section
  cannot be recovered from below.
- **`laya-yn` is the most informative failure, and it generalises past this model.** 65 independent
  yes/no questions produce 65 probabilities that were *never compared with each other*. They are not
  on a common scale, so ranking by them is close to meaningless — hence 0.17, below what the easy
  tier alone should give. Any pipeline that scores N candidates with N independent calls and then
  sorts by the score has this bug, and it does not announce itself: the numbers look like confidences.

### Verdict

**For this task, on this evidence, a small local judgment model is not worth its overhead** — and that
was a real possible outcome of the experiment, not a fallback. The honest statement is narrow: Laya
loses *at ranking 65 knowledge files from a short request*. That is a high-cardinality retrieval
problem, which is what BM25 was built for and not what a 421M classifier was built for. It says
nothing about Laya on the tasks it is shaped for — few options, rich state, a genuine judgment call.

**What would change this verdict:** an arm where the candidate set is already small and the decision
is semantic rather than lexical. The natural one is E2b's fallback gate — given the *top-1 file's
actual content* and the request, "does this file answer it?" — two options, real state, one call.
That is the shape Laya is for, and it is the one question BM25 provably cannot answer. Not run.

## E4 — the distillation pre-filter, killed by arithmetic and replaced

The original hypothesis: most transcript turns carry no durable signal, so a cheap local classifier
could cut what the extraction stage reads. Before building it, the free arithmetic — where does
transcript volume actually live? Across the 10 real sessions on this machine (1,017,197 chars ≈ 446k
tokens est.):

| component | chars | share | tokens (est) |
| --- | --- | --- | --- |
| tool results | 543,085 | **53.8%** | 238,091 |
| tool_use inputs | 283,874 | **28.1%** | 124,452 |
| user text | 131,195 | 12.9% | 57,516 |
| assistant text | 47,118 | 4.7% | 20,657 |
| assistant thinking | 4,275 | 0.4% | 1,874 |

**82% of a transcript is tool traffic.** A classifier that judges *user turns* is aimed at 13% of the
volume, so even a perfect one — never dropping a real signal, dropping every empty turn — cannot save
more than 13%. The experiment is not worth its own design. **Killed.**

This is the same lesson the knowledge base already records from the marks experiment ("run the free
arithmetic BEFORE designing the experiment"), and it applied again here.

### What replaces it: truncate tool traffic, no model involved

Head-truncating every tool result and tool_use input, because the first lines carry the outcome and
the tail is payload:

| tool cap | tokens (est) | reduction |
| --- | --- | --- |
| uncapped | 445,943 | — |
| 4,000 chars | 355,428 | 20% |
| 1,000 chars | 248,802 | 44% |
| **500 chars** | **194,323** | **56%** |
| 200 chars | 139,378 | 69% |
| dropped entirely | 80,047 | 82% |

**This is a knob, not a free win, and it must not ship as one.** Tool results carry real signal — a
command that failed with a specific error is exactly the kind of thing distillation should catch, and
that error is often *not* in the first 500 chars. The honest open question, which this data cannot
answer, is what fraction of durable knowledge entries trace back to tool output rather than to
something the user said. Until that is measured, the release frame's rule applies: any
token-vs-something trade is an explicit opt-in knob with documented consequences.

**The measurable next step** (not run): take knowledge entries with `origin: evidence` and trace each
back to its transcript turn. If they overwhelmingly cite user text and assistant text, truncation is
nearly free and the cap can be aggressive. If a meaningful share cites tool output, the cap is a real
accuracy trade and belongs behind a flag. That is an attribution study on existing data — no model,
no runs, no GPU.

## E5 — end-to-end confirmation in the real harness (RUN)

E1/E2 were expected-value arithmetic. This is the measurement. Arm C: the zero-model router's top-3
SPINE bullets are injected into a real headless `claude -p` cell, `Read(SPINE.md)` is denied, and the
agent still chooses and reads the file itself. Same topic, same model, same answer-format rule as the
2026-09-21 baseline — only the index read differs. Warm cells only (a cold cell writes the whole
CLAUDE.md floor to cache and is not comparable):

| | cells | wall | api | turns | cost | cache_creation | cache_read |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **A baseline** (reads SPINE) | 3 | 13.6 s | 12.4 s | **5** | $0.382 | 30,364 | 119,719 |
| **C shortlist** (top-3 injected) | 2 | 10.3 s | 8.9 s | **3** | **$0.139** | **9,132** | 69,080 |
| | | −24% | −28% | −1 round trip | **−64%** | **−70%** | −42% |

**Hit rate 3/3**, no stray reads. Both arms read `ops/linux-shell-ssh.md` *and* `projects/homelab-pi.md`
— identical retrieval, so the comparison is clean.

The number that validates the whole chain: **cache_creation fell by 21,232 tokens**, against a
separately measured SPINE read of **21,247**. Two independent measurements of the same quantity,
agreeing to 15 tokens. The mechanism removes exactly the thing it was designed to remove and nothing
else.

**The round trip is the surprise.** Turns dropped 5 → 3 because the agent read both candidate files in
one turn instead of SPINE-then-files. The arithmetic in E2 credited `shortlist-N` with *zero* saved
round trips; it saved one anyway, and that is where most of the 24% wall-clock came from. Expected-value
models of agent behaviour miss this class of effect — the agent reorganised its own tool use once the
index read was gone.

**Caveat: n=2 warm cells, one topic.** The token accounting is deterministic and trustworthy; the
wall-clock is not (10.3 s median from cells of 7.8 s and 12.8 s). Read −70% tokens as measured and
−24% wall as indicative. Cost for this run: $0.73 across 3 cells.

## Resource protocol (PortCall `system-resources`)

Another agent (*Commodore Sparkling Wombat the Unmerged*) held this Mac's unified memory for a
`Qwen3.8-27B-MLX-8bit` benchmark and had priority. Channel `system-resources` was created for the
handover, every registered agent invited, and messages re-posted because PortCall has no history yet —
a peer that joins late sees nothing, so anything that matters must be sent again.

How it ran: this session stayed single-core / ~15 MB / no GPU for ~50 minutes of the work above while
the peer ran, started only after observing its process exit at 84% free memory, announced start and
finish in-channel, and released the box after 4.7 minutes. Two corrections were posted to the channel
rather than quietly logged — an "active swapping" claim that was a misread of a cumulative counter,
and a peak-RSS estimate that was wrong by ~2× (3 GB predicted, 5.68 GB measured) in the direction that
would have hurt the peer.

**Worth keeping:** the peak-RSS estimate was derived from parameter count. Framework allocator
overhead and batch size roughly doubled it. Quote measured peak RSS to a peer, never a parameter-count
estimate.

## Reproduce

```bash
cd ~/repos/jev-distill-routing
python3 tools/tokens.py                 # F1/F4/F5 — measured token accounting
python3 tools/variants.py               # E1 — four zero-model arms + shortlist curve
python3 tools/route_local.py lexical    # E1 single arm with latency reps
python3 tools/mechanisms.py             # E2 — expected cost per candidate mechanism
python3 tools/distill_cost.py           # E4 — where transcript volume lives + the cap curve
python3 tools/run.py shortlist --reps 3 # E5 — end-to-end arm C in a real headless cell (~$0.25/cell)
~/repos/laya-lab/.venv/bin/python tools/route_local.py laya-yn   # E3, when RAM allows
```

Raw results: `jev-distill-routing/runs/<stamp>-e1*/`. Harness and eval set live in that repo; this
folder holds the write-up and the decision record.

`prototype/spine_router.py` is the E1 winner packaged as a shippable, stdlib-only module: a CLI and a
`--hook` mode for `UserPromptSubmit` that injects the top-3 candidates and abstains below MIN_SCORE.
It is a prototype for measurement, not a merge candidate — `AGENTS.md` requires an issue and an
independent review first.

```bash
python3 prototype/spine_router.py "I'm about to ssh into the pi and pkill a stuck process"
echo '{"prompt":"..."}' | python3 prototype/spine_router.py --hook
```
