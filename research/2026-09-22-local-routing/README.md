# Local models for aura-distill retrieval and distillation

**Status:** in progress · started 2026-09-22 · machine: Mac M5 Pro (16 cores, 48 GB unified) · all
runs local unless marked otherwise.

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

## E3 — Laya as router (BLOCKED on resources, harness ready)

Two arms in `jev-distill-routing/tools/route_local.py`:

- `laya-yn` — one yes/no `choice` per SPINE entry, all 65 in **one** forward pass, rank by P(yes).
- `laya-hier` — `choice` over SPINE sections, then `choice` within the winning section.

Blocked deliberately: another agent on this machine is running `Qwen3.8-27B-MLX-8bit` (~29 GB
resident) for a token-savings experiment. With 149 MB unused RAM and active pageouts, loading a
second model would corrupt their latency numbers and mine. Coordination is running in the PortCall
`system-resources` channel. See *Resource protocol* below.

## E4 — Laya as a distillation pre-filter (designed, not run)

Hypothesis: most transcript turns carry no durable signal, so a cheap local classifier could cut what
the extraction stage reads. **Pre-registered decision rule:** this is worth shipping only if the filter
holds ≥0.95 recall on signal-bearing turns at ≤0.5 of the turns kept. Below that it trades accuracy
for tokens, which the release frame says must be an opt-in knob at best.

Honest blocker: this Mac has **28 user turns across 9 sessions**. That is not enough to measure
recall to two digits, and labelling them myself makes the eval circular. This experiment needs the
Windows box's transcript history before it can produce a number.

## Resource protocol (PortCall `system-resources`)

Created channel `system-resources`, invited every registered agent, and posted three messages: the
plan, a re-post (PortCall has no history yet, so a peer that joins late sees nothing), and a
measurement. Current standing: **the other agent has priority**; this session stays single-core, pure
Python, ~15 MB RSS, no GPU, until it answers. The proposal on the table is to share *its* resident
model rather than load a second one — it is already paying the 29 GB.

## Reproduce

```bash
cd ~/repos/jev-distill-routing
python3 tools/tokens.py                 # F1/F4/F5 — measured token accounting
python3 tools/variants.py               # E1 — four zero-model arms + shortlist curve
python3 tools/route_local.py lexical    # E1 single arm with latency reps
python3 tools/mechanisms.py             # E2 — expected cost per candidate mechanism
~/repos/laya-lab/.venv/bin/python tools/route_local.py laya-yn   # E3, when RAM allows
```

Raw results: `jev-distill-routing/runs/<stamp>-e1*/`. Harness and eval set live in that repo; this
folder holds the write-up and the decision record.
