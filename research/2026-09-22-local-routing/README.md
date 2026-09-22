# Local models for aura-distill retrieval and distillation

**Status:** E1–E8 run · started 2026-09-22 · revised 2026-09-22 after independent review of PR #101 · machine: Mac M5 Pro (16 cores, 48 GB unified) · all
runs local unless marked otherwise.

## Headline

1. **The turn that reads `SPINE.md` costs 21,247 tokens** (median of 4 real headless cells, spread 16).
   That is the *turn*, not the file — see F1. It is the largest fixed cost of a session and it is
   what the shortlist mechanism removes.
2. A **zero-model** router (BM25 rank-fusion over the index line *and* the file body) routes at
   **0.87 top-1 in 4.85 ms and 29 MB**. Injecting its top-3 into a real headless cell **measured
   −70% cache-creation tokens, −64% cost and one fewer round trip, at 3/3 correct** (E5). That
   measured figure is the headline; projections appear only with their assumptions attached.
3. **Laya lost to it at routing** (best arm 0.67 vs 0.87) at 5.7 GB and 9–390× the latency. Given the
   task it is actually shaped for — "does *this* file answer the request?", with a BM25-selected
   passage — it reaches **0.73 balanced accuracy / 0.83 specificity** (E6).
4. **The representation dominates the model.** Changing only how a candidate is described swings Laya
   0.600 → 0.750 balanced accuracy, more than the whole Laya-vs-BM25 gap (E7).
5. The distillation pre-filter **died to arithmetic**: ~93% of transcript volume is tool traffic.

Nothing here is merged. The two shippable candidates — the router hook and the tool-traffic cap —
need an issue, a held-out eval on mined queries, and an independent review first.

> **Revision note.** An independent review of PR #101 found two blocking errors in the first version
> of this document, both of which are corrected here and neither of which was caught by the author:
> a token figure attributed to this project that this project never published, and a chars-per-token
> constant derived by dividing file size by a turn cost. Both are described where they occur.

## The question

aura-distill spends frontier-model tokens on two steps that may not need a frontier model:

1. **Retrieval.** Every session starts by reading `SPINE.md` (the knowledge index) and choosing which
   domain file to load. That is a classification over ~65 options.
2. **Distillation.** A `/distill` run reads a transcript and decides which turns carry durable signal.
   That is a filter before it is a synthesis.

If a small local model (Laya, Jev, or a quantized LLM) can do either step at equal quality, the
frontier model never pays for it. If it cannot, that is a result too — and the honest comparison
needs a **zero-model control**, because "free" is a real competitor.

## Foundations

Separating what was **measured** from what is **estimated** matters here, because the first version
of this document blurred the two and got a headline wrong.

| # | Fact | Evidence | Kind |
| --- | --- | --- | --- |
| F1 | **The turn that reads `SPINE.md` costs 21,247 tokens** (21,233 / 21,242 / 21,247 / 21,249) | `cache_creation_input_tokens` on the message *after* the one that read `SPINE.md`, 4 headless cells, `tools/tokens.py` | measured |
| F2 | That counter covers the **whole turn** — tool_use block, tool result, surrounding assistant content — not the file alone | definition of the counter; confirmed by F4 | measured |
| F3 | `SPINE.md` **the file** is ≈13.8k–18.6k tokens | 48,461 chars ÷ a 2.6–3.5 chars/token band | **estimated** |
| F4 | Two BPE tokenizers put `SPINE.md` at **~3.5 chars/token** (gpt2 14,017 tokens; ModernBERT-large 13,854), against **3.87** for a prose control | `transformers`, local | measured (proxy tokenizers, not Anthropic's) |
| F5 | This project previously published **3.6k tokens for a 59-entry SPINE** | `docs/research/token-economics.html:94,95,135,143` | measured (prior work) |
| F6 | The index is now **65 entries / 48,461 chars**, median bullet **133 tokens**, mean **191** | `tools/cardinality.py`, `tools/tokens.py` | measured |
| F7 | The routing decision itself takes **2.7 s median** (2.3–4.4) of a ~13 s session | baseline run 2026-09-21, `choose_s` | measured, n=4 |
| F8 | Laya runs on this Mac on MPS; ~50 s load, 5.7 GB peak RSS | `tools/gate.py` summaries | measured |

### What F5 and F6 mean together, and what the first draft got wrong

The first version of this document said the index read was **"2.3× what this project documented"**,
citing ~9k tokens. **That 9k figure does not exist in aura-distill.** It came from a different,
private repository's README, written by the same author the day before. The review caught it; a grep
of this repo confirms the only occurrence was the new page itself.

What this project actually published is F5: **3.6k tokens for a 59-entry SPINE**. Against F3, the
index file has grown roughly **4–5×** since that measurement. And the driver is *not* entry count —
59 → 65 entries is +10%. It is **verbosity per entry**: 61 tokens/entry then, 191 now, with a p90 of
474 and a maximum of 841.

That is a better finding than the one it replaces, and an actionable one: **index cost scales with
how much is written per line, and nobody was watching that number.** The `token-economics.html` page
remains live with 3.6k and now needs a pointer to this one.

### Why the "two independent measurements" claim was withdrawn

The first draft observed that E5's cache-creation drop (21,232) matched F1 (21,247) to 15 tokens and
called them "two independent measurements of the same quantity". **They are not independent.** Both
are the same cache-block accounting of the same turn; removing the turn removes its framing along
with the file, so close agreement is arithmetic, not corroboration. What E5 *does* establish is that
the mechanism removes essentially all of the turn's cost and adds nothing unexpected — which is worth
knowing, and is the claim now made.

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
fall back to the full index when none fits. All projections below use **one** cost model, stated once:
tokens = 3.5 chars/token (F4), index turn = 21,247 (F1), median knowledge file = 1,740 tokens (est),
a miss pays the shortlist **and** the status quo after it. Earlier drafts quoted 74%, 85% and 90% for
this same mechanism from three inconsistent models; that is fixed.

| N | recall@N (`rrf-full+bodyfull`) | E[tokens] | saving |
| --- | --- | --- | --- |
| 1 | 0.87 | 5,123 | 78% |
| **3** | **0.90** | **4,941** | **79%** |
| 5 | 0.90 | 5,718 | 75% |
| 8 | 0.93 | 5,787 | 75% |

**The bar for any model.** ~79% projected saving at 0.87 top-1, obtained for 4.85 ms and 29 MB. The
*measured* end-to-end figure is −70% (E5); projections run a little optimistic, as projections do.

> **Overfitting caveat.** Eight arms were scored on 30 queries the same agent wrote. One topic is
> worth 3.3 points, so gaps under ~10 points are noise, and `rrf-full+bodyfull` winning by 10 over
> `bm25-bodyfull` is at the edge of it. The winner is **pre-registered** for a held-out test against
> mined real queries; it is not to be re-tuned first.

## E2 — which mechanism, and what it is worth

Same cost model as above. `shortlist-N` injects the top-N *bullets* and the agent still chooses;
`inject-files-N` injects the top-N *file bodies*, so there is no index read and no routing turn.

| mechanism | recall | E[tokens] | saving | round-trips saved |
| --- | --- | --- | --- | --- |
| status-quo | 1.00 | 22,987 | — | — |
| **shortlist-3** | 0.90 | **4,941** | **79%** | 0 (predicted) |
| shortlist-1 | 0.87 | 5,123 | 78% | 0 (predicted) |
| shortlist-8 | 0.93 | 5,787 | 75% | 0 (predicted) |
| **inject-files-1** | 0.87 | 6,012 | 74% | **1 (≈2.7 s)** |
| inject-files-3 | 0.90 | 12,554 | 45% | 1 |

Injecting whole files stops paying past N=1 because knowledge files are large (median 1,740 tokens
est., p90 5,332, max 10,360).

### What that is worth in money

At Opus 5 rates ($5/MTok input) with Claude Code's 1-hour cache TTL (2× write, 0.1× read), the index
turn costs **$0.21 to write and $0.011 per subsequent turn to re-read** — about **$0.41 for a 20-turn
session** before the agent has answered anything. A ~75% cut is ~$0.30/session. Honest framing: real
for a heavy user, rounding error for a light one. **The latency is the better argument than the
dollars.**

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

**Answered in two parts.** As a *router*, no — Laya's probabilities do not separate its hits from its
misses on any routing arm (E3). As a *gate over one candidate*, partially yes — 0.83 specificity with
separated probabilities, but only when fed a BM25-selected passage rather than the file head (E6).

## E3 — Laya as router (RUN — negative; narrowed by E6)

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
is semantic rather than lexical — E2b's fallback gate. **Run as E6 below; it partially reverses this
section.** Read E6 before quoting E3's verdict.

## E4 — the distillation pre-filter, killed by arithmetic and replaced

The original hypothesis: most transcript turns carry no durable signal, so a cheap local classifier
could cut what the extraction stage reads. Before building it, the free arithmetic — where does
transcript volume actually live?

> **Dataset caveat, and it is a real one.** `~/.claude/projects` is *live*: it grows while the
> measurement runs, and the session running this analysis is one of the heaviest tool users in it.
> Including it is circular and unstable — a first pass, taken mid-session, gave a materially
> different split from a second pass two hours later. **The session doing the measuring is therefore
> excluded** (`AURA_EXCLUDE_SESSION` in `tools/distill_cost.py`). Nine sessions, 1,903,214 chars,
> snapshot 2026-09-22. Anyone re-running this will get different absolute numbers; the *shape* is
> what transfers.

| component | chars | share | tokens (est) |
| --- | --- | --- | --- |
| tool results | 1,435,564 | **75.4%** | 410,161 |
| tool_use inputs | 332,745 | **17.5%** | 95,070 |
| user text | 65,854 | 3.5% | 18,815 |
| assistant text | 64,776 | 3.4% | 18,507 |
| assistant thinking | 4,275 | 0.2% | 1,221 |

**~93% of a transcript is tool traffic.** A classifier that judges *user turns* is aimed at 3.5% of
the volume, so even a perfect one — never dropping a real signal, dropping every empty turn — cannot
save more than that. The experiment is not worth its own design. **Killed.**

This is the same lesson the knowledge base already records from the marks experiment ("run the free
arithmetic BEFORE designing the experiment"), and it applied again here.

### What replaces it: truncate tool traffic, no model involved

Head-truncating every tool result and tool_use input, because the first lines carry the outcome and
the tail is payload:

| tool cap | tokens (est) | reduction |
| --- | --- | --- |
| uncapped | 543,775 | — |
| 4,000 chars | 224,698 | 59% |
| 1,000 chars | 151,863 | 72% |
| **500 chars** | **116,032** | **79%** |
| 200 chars | 78,759 | 86% |
| dropped entirely | 38,544 | 93% |

**This is a knob, not a free win, and it must not ship as one.** Tool results carry real signal — a
command that failed with a specific error is exactly what distillation should catch, and that error
is often *not* in the first 500 characters. The honest open question, which this data cannot answer,
is what fraction of durable knowledge entries trace back to tool output rather than to something the
user said.

**The measurable next step** (not run): take knowledge entries with `origin: evidence` and trace each
back to its transcript turn. If they overwhelmingly cite user and assistant text, truncation is
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

**Hit rate 3/3 across all three arm-C cells**, no stray reads; the table counts 2 because only the
two *warm* cells are token-comparable (a cold cell writes the whole CLAUDE.md floor to cache). Both
arms read `ops/linux-shell-ssh.md` *and* `projects/homelab-pi.md` — identical retrieval, so the
comparison is clean.

**What this does and does not establish.** Cache creation fell by 21,232 tokens against a measured
index-read turn of 21,247 (F1). These are **not** two independent measurements — both are the same
cache-block accounting of the same turn, so their agreement is arithmetic, not corroboration (an
earlier draft claimed otherwise and the review was right to reject it). What it *does* establish is
that the mechanism removes essentially all of that turn's cost **and adds nothing unexpected** — no
hidden re-read, no compensating growth elsewhere. That was worth checking and it held.

**The round trip is the surprise.** Turns dropped 5 → 3 because the agent read both candidate files in
one turn instead of SPINE-then-files. The arithmetic in E2 credited `shortlist-N` with *zero* saved
round trips; it saved one anyway, and that is where most of the 24% wall-clock came from. Expected-value
models of agent behaviour miss this class of effect — the agent reorganised its own tool use once the
index read was gone.

**Caveat: n=2 warm cells, one topic.** The token accounting is deterministic and trustworthy; the
wall-clock is not (10.3 s median from cells of 7.8 s and 12.8 s). Read −70% tokens as measured and
−24% wall as indicative. Cost for this run: $0.73 across 3 cells.

## E6 — the fair test: Laya as a relevance GATE, not a router (RUN — partial positive)

E3's verdict was weak and I attacked it before publishing. E3 tested a 421M classifier at ranking 65
files from a short request — high-cardinality retrieval, BM25's job, not a classifier's. Concluding
"the model is not useful" from that is the same unfair comparison this document warns about
elsewhere. E6 gives the model the shape it is built for: **two options, rich state, one judgment**.

    state    = the request + the candidate file's content
    question = "does this file answer this request?"   (yes / no)

That is precisely the question E2b proved no zero-model signal can answer, so a win here is a
complement to BM25, not a replacement. 90 balanced items: 30 positives (request + its ground-truth
file), 30 negatives (request + a deterministically-chosen wrong file), 30 realistic (request + BM25's
actual top-1). Balanced deliberately — BM25 only misses 4 of 30, and a 4-item negative class proves
nothing.

### E6a/E6b — it says yes to everything

| formulation | recall | specificity | balanced acc |
| --- | --- | --- | --- |
| A "does `file` contain what `request` needs?" | 0.967 | **0.100** | 0.533 |
| B negated ("is `file` IRRELEVANT?") | 0.333 | 0.633 | 0.483 |
| C strict ("most retrieved files are WRONG, judge strictly") | 0.667 | 0.533 | 0.600 |
| D `score` type, 4 levels | 1.000 | **0.000** | 0.500 |

Chance is 0.500. **B is the diagnostic**: negating the question *inverts* the bias rather than
preserving the judgment, which means the model was answering from option polarity, not from the
content in front of it.

### E6c — the excerpt was the confound, and it mattered

Laya's total sequence is 512 tokens, ~192 of which go to the head, so roughly **700 characters of
state** reach the model. An aura-distill knowledge file opens with YAML front-matter (`domain`,
`scope`, `last_updated`, `staleness_threshold`) and a context line. A/B/C/D were therefore largely
asking the model to judge **front-matter**, which looks nearly identical across all 65 files.

Swapping the file head for the **BM25-best 500-char passage** — the window of the file that best
matches the request:

| state | recall | specificity | balanced acc | p(yes) true | p(yes) false | separated? |
| --- | --- | --- | --- | --- | --- | --- |
| first 1,400 chars (front-matter) | 0.667 | 0.533 | 0.600 | 0.616 | 0.495 | barely |
| **BM25-best passage** | 0.633 | **0.833** | **0.733** | **0.574** | **0.263** | **yes** |

Specificity 0.53 → 0.83, and the probabilities separate (0.574 vs 0.263) where nothing had separated
before — not in any zero-model signal (E2b), not in any routing arm (E3). **This is the first thing
in the whole programme that can tell a right retrieval from a wrong one.**

I nearly shipped E6a's number as the verdict. It was an artifact of feeding the model YAML.

### What the gate is actually worth

**Same cost model as E2** — an earlier draft used a third, inconsistent one that omitted the cost of
injecting the shortlist and so reported 90% where E2 reported 74% for the same mechanism.

Given BM25 top-1 at 0.867 and a gate at recall 0.633 / specificity 0.833, a wrong gate verdict costs
a fallback to the full index (expensive, never wrong) and a missed one costs a wrong answer:

| configuration | wrong-answer rate | falls back | E[tokens] | saving |
| --- | --- | --- | --- | --- |
| status quo (read the index) | 0.0% | — | 22,987 | — |
| shortlist, **no gate** | 13.3% | 0% | **3,243** | **86%** |
| shortlist + gate | **2.2%** | 42.9% | 13,104 | 43% |

**The gate buys an 11-point drop in wrong answers for 43 points of token saving.** Not a free win and
it must not ship as one — it is exactly the "token-vs-something trade" the release frame says is an
opt-in knob with documented consequences. Whether it is worth 5.7 GB resident and ~88 ms is a product
call, not a measurement.

### Corrected verdict on Laya

**Narrowed, not reversed.** Laya cannot route — it loses to BM25 by 20 points at picking among 65
files (E3). But it *can* gate at 0.73 balanced accuracy and 0.83 specificity when handed the right
excerpt, which is the one capability BM25 structurally lacks. The useful architecture, if any, is
**BM25 retrieves and selects the passage, Laya judges** — not either one alone.

Limits worth stating: 90 items on one self-written eval set; four prompt formulations, not a search;
the passage selector is itself BM25, so the "model" arm depends on the zero-model arm; and 0.73 is
a long way from a number anyone should trust a gate to.

## E7 — is the SPINE the limit, or the model? (RUN — the representation dominates)

Direct test of the claim *"with the current state of the SPINE files we barely see improvement from a
decision model"*. Same E6 gate, same 90 balanced items, same prompt — **only the candidate's
description changes**:

| description given to the model | recall | specificity | balanced acc | p(yes) true − false | tuned bal. acc |
| --- | --- | --- | --- | --- | --- |
| file head (1,400 chars ≈ front-matter) | 0.667 | 0.533 | 0.600 | 0.120 | 0.669 |
| **SPINE line** | 0.500 | **0.933** | 0.717 | **0.462** | **0.819** |
| BM25-best 500-char passage | 0.633 | 0.833 | 0.733 | 0.311 | 0.750 |
| **SPINE line + best passage** | 0.700 | 0.800 | **0.750** | 0.437 | 0.789 |

(Tuned = post-hoc optimal threshold on these same 90 items, so it is optimistic; the probability
**gap** is the threshold-free measure and tells the same story.)

**Changing the representation moves the model from 0.600 to 0.750 balanced accuracy — a bigger swing
than the entire distance between Laya and BM25 anywhere in this programme.** The data structure, not
the model, is the dominant variable.

And the surprise inverts an earlier finding: **the SPINE line is the single most *discriminative*
input** (gap 0.462, specificity 0.933), beating the file's own content. E1 found the opposite for
BM25 — there, file bodies beat index lines by 33 points. The two results do not conflict, they
partition:

- **Lexical matching wants volume.** More text means more chances for a term to match, so BM25 wants
  the whole file.
- **A judgment model wants density.** It sees ~700 characters total, so every token of boilerplate is
  a token of evidence it does not get. The SPINE line is hand-written, distinctive and compressed —
  the best 133 tokens about that file that exist anywhere.

**The routing arms could never have benefited from this.** In a choice question all options share a
192-token head budget: at 10 options each label gets **17 tokens**, at 65 options **4 tokens** — 13%
and 3% of a median 133-token SPINE line. The whole SPINE is 12,427 tokens of option text against a
192-token budget, so **1.5% of it could ever fit**. E3 did not measure whether Laya can use the SPINE;
it measured a model that never received it.

### Consequence: a Laya-shaped index is a real design, not a hypothesis

The evidence says what it would have to be, and it is not what aura-distill has:

1. **One record per file, evaluated one at a time** — the gate architecture works, the many-option
   choice architecture is structurally capped. Rank cheaply first, judge one candidate at a time.
2. **~250–300 tokens per record, front-loaded with discriminative content** — distinctive nouns and
   the actual gotchas. YAML front-matter at the top of every file cost 0.13 of balanced accuracy on
   its own (file-head vs best-passage) because it is what survived truncation.
3. **Line + passage, not line or passage** (0.750, the best default-threshold result): the curated
   description says what the file is *for*, the matched passage proves it covers *this* request.
4. It is a **derived view**, rebuildable from the files, so it cannot rot independently — which is the
   existing retrieval-axes design constraint, satisfied.

Worth noting what this does **not** promise: 0.750 is still a long way from a number that should gate
anything unsupervised, and every figure here rests on 90 items from one self-written eval set.

## E8 — how many categories, does cascading rescue it, and does semantics matter?

Candidate sets of size K that **always contain the ground truth**, distractors drawn deterministically
and nested (the K=5 set is a subset of K=10), positions shuffled. The only thing changing is how many
options share the 192-token head budget. n=30 per cell, so one topic = 0.033 and gaps under ~0.10 are
noise.

| K | tokens/label | prose | keywords | path | chance |
| --- | --- | --- | --- | --- | --- |
| 2 | 48 | 0.767 | 0.833 | 0.867 | 0.500 |
| 3 | 48 | 0.867 | 0.833 | 0.833 | 0.333 |
| 5 | 35 | 0.800 | 0.900 | 0.767 | 0.200 |
| **8** | 22 | **0.833** | **0.867** | 0.800 | 0.125 |
| 10 | 17 | 0.733 | 0.733 | 0.667 | 0.100 |
| 15 | 11 | 0.700 | 0.600 | 0.667 | 0.067 |
| **20** | 8 | 0.767 | 0.767 | 0.767 | 0.050 |
| **30** | 5 | **0.533** | 0.533 | 0.533 | 0.033 |
| 45 | 4 | **0.333** | 0.333 | 0.333 | 0.022 |
| 65 | 4 | 0.333 | 0.333 | 0.333 | 0.015 |

### A. The ceiling is ~20 options, and it is a cliff, not a slope

Accuracy is flat in the 0.70–0.87 band from K=2 to K=20, then **falls off between K=20 and K=30** and
flattens again at 0.333 for K≥45. It tracks **tokens per label**, not K itself: 8 tokens still works,
5 does not. K=45 and K=65 score identically because both are clamped to the 4-token floor — the labels
are equally shredded, so adding 20 more of them changes nothing.

Note it is *not* monotonic in the working range: K=3 (0.867) ≈ K=8 (0.833) ≈ K=20 (0.767). Within the
budget, the number of options barely matters. **Design to the token budget, not to a category count.**

### B. Cascading does not rescue it — errors multiply and level 1 is unrecoverable

Projecting a two-level tree from the measured per-level accuracies above:

| design | level 1 | level 2 | end-to-end |
| --- | --- | --- | --- |
| 8 groups × 9 members* | 0.833 | 0.783 | **0.652** |
| 4 groups × 17 | 0.834 | 0.727 | 0.606 |
| 5 groups × 13 | 0.800 | 0.713 | 0.571 |
| 2 groups × 33 | 0.767 | 0.493 | 0.378 |

*\* Group×member products exceed 65 because the per-level accuracies are read off the K-sweep,
which uses equal-sized option sets; a real 65-file tree has ragged groups. The projection is an
upper bound either way, which is all it needs to be to close the question.*
| *flat K=65 (measured)* | — | — | *0.333* |
| *real 2-level cascade (E3 `laya-hier`, measured)* | — | — | *0.400* |
| *BM25 rank-fusion (zero model)* | — | — | **0.867** |

Cascading beats a flat 65-way choice (0.65 vs 0.33) — and still loses to free by 21 points. Two 80%
steps are a 64% pipeline, and a wrong group at level 1 cannot be recovered at level 2. The projection
is also the **optimistic** bound: it assumes random distractors, while real groups contain
semantically confusable siblings. The one real cascade that was measured came in at 0.400, below the
projection, as expected.

### C. Semantics are not doing the work — at these label lengths

`prose` (the hand-written SPINE line), `keywords` (its 12 highest-IDF terms, no grammar) and `path`
(just `ops/linux-shell-ssh.md` → "ops linux shell ssh") are **indistinguishable**. No style gap at any
K exceeds 3 topics. At K=20 all three score exactly 0.767; at K≥30 all three are identical.

**The file path alone performs as well as the carefully written index description.**

### The mechanism this exposes, which is the real finding

Compare with E7, where the *same model* on the *same knowledge* showed the SPINE line to be the most
discriminative input available — beating the file's own content (probability gap 0.462 vs 0.311).

The two results reconcile through the token budget:

> **When labels are compressed to fit, the model stops doing semantics and starts doing keyword
> matching — which is what BM25 already does better, in 29 MB and 9–390× faster depending on the arm
> (`laya-rerank` 43.8 ms, `laya-hier` 238 ms, `laya-yn` 1,895 ms, against BM25 at 4.85 ms).**

At 8–35 tokens a label there is no room for meaning, only for terms. The model degenerates into an
expensive, worse BM25, and that is why every routing arm lost. It only earns its weights where it has
room to read: **one candidate, a few hundred tokens of real content, a yes/no judgment** — exactly the
configuration where it beat everything else in this programme (E6/E7).

**Direct consequence for a Laya-shaped index: it must not be a category taxonomy.** Not 65 options,
not 20, not a 5×13 tree. Cheap retrieval proposes; the model judges candidates one at a time, with the
budget spent on content rather than split across labels.

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
~/repos/laya-lab/.venv/bin/python tools/gate.py --device mps              # E6a
~/repos/laya-lab/.venv/bin/python tools/gate_formulations.py             # E6b
~/repos/laya-lab/.venv/bin/python tools/gate_excerpt.py                  # E6c
~/repos/laya-lab/.venv/bin/python tools/route_local.py laya-yn   # E3
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
