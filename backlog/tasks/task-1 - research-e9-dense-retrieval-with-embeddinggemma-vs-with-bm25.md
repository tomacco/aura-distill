---
id: task-1
title: "Research E9: dense retrieval with EmbeddingGemma vs/with BM25 for knowledge routing"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: []
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/133
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/133

## Context

`research/2026-09-22-local-routing/` compared a zero-model BM25 router against Laya for picking the right knowledge file for a request. BM25 over the whole file body (`bm25-bodyfull`) won at **0.87 top-1 in ~5 ms / 29 MB**; Laya lost at routing (best arm 0.67, 5.7 GB). One family of retrievers was never tested: **dense sentence embeddings**.

[EmbeddingGemma](https://huggingface.co/google/embeddinggemma-300m) (Google, ~300M params, Gemma 3 based, multilingual, ~2K-token input, Matryoshka output 768 → 512/256/128) is small enough to run locally next to the router, so it is the obvious candidate.

Note: an embedding model does not need to have "seen" our content. The knowledge files are embedded once into vectors and queries are matched by similarity, so private, never-trained-on content is the normal use case. The open question is whether it beats or complements BM25 on *this* corpus.

## Questions

1. **Accuracy.** Does dense retrieval, alone or fused with BM25, beat `bm25-bodyfull` on the existing eval set, especially the `hard` tier (requests that avoid the SPINE's distinctive nouns)?
2. **Cross-lingual.** Ivan often asks in Spanish while most knowledge is written in English. BM25 can't bridge that by construction; can embeddings?
3. **Abstention.** BM25's raw score is only a weak out-of-scope signal (overlapping ranges, see README §abstention). Is max cosine similarity a better-separated one?
4. **Cost.** Does it stay in hook territory (latency per query, RAM, one-off index build time)?

## Prior expectation (stated up front)

E8 found that "semantics are not doing the work" with the current queries, and the corpus is full of private jargon (SPINE, distill, project names) that the model has no learned meaning for. **The expected outcome is a small or zero gain on English top-1, with any real gain in the hard tier, in cross-lingual queries, and maybe in abstention.** A null result is a valid result and should be written up as one.

## Design

**Corpus.** Snapshot of the live knowledge store (all non-`archive/` files; `archive/` reported separately), recorded with file list + content hashes in the results dir. **Re-run the BM25 baselines on the same snapshot.** The 0.87 figure was measured on the 2026-09-22 store and the store has changed since, so it can't be compared directly.

**Chunking.** Split by markdown section, capped below the 2K-token input limit, with the file path + section heading prepended to each chunk. File score = max over its chunks (also report mean-of-top-2 as a secondary).

**Model usage.** Use the model's documented retrieval prompts (`task: search result | query: …` for queries, `title: … | text: …` for documents). Run via `sentence-transformers`, CPU and MPS.

**Arms**
| arm | description |
|---|---|
| `bm25-bodyfull` | baseline, re-run on the snapshot |
| `dense-768` | EmbeddingGemma, full-dimension vectors, chunk max-pool |
| `dense-256` | same, Matryoshka-truncated (cost/quality curve) |
| `hybrid-rrf` | reciprocal rank fusion of `bm25-bodyfull` + `dense-768` (k=60, fixed in advance) |

**Queries**
- The existing 30-query `topics-eval.json` (easy + hard), unchanged.
- The existing out-of-scope queries used for the abstention calibration.
- **New:** Spanish versions of the same 30 queries, same expected labels, committed *before* any arm is scored. They're translations, so treat them as a probe, not a held-out set.

**Metrics.** Same as the earlier experiments: top-1, top-3, per tier; plus Spanish top-1/top-3; in-scope vs out-of-scope score ranges for abstention; p50/p95 query latency, peak RSS, index build time.

**Pre-registration.** Arms, chunking rule, RRF k and the winner criterion (top-1 on the `hard` tier, ties broken by overall top-1) are fixed in the README before running. The same rule as before applies: no tuning on the eval set, and a winner here is a candidate for a held-out eval on mined queries, not a ship decision.

## Where it can run

- **The knowledge store** lives in `~/.aura-distill` on the Mac, but it's also readable through the read-only aura-distill MCP connector (`list_knowledge` / `read_knowledge`). A cloud session can snapshot it from there. That's enough for this experiment.
- **Raw session transcripts** exist only on the Mac. They aren't needed here, but the follow-up held-out eval on mined queries will have to run there.
- **Model weights.** `google/embeddinggemma-300m` is gated on Hugging Face (accept the license + HF token). Whichever machine runs it needs that, plus network access to huggingface.co.
- Latency/RSS numbers that matter for the hook should be measured on the Mac (M5 Pro), as the earlier ones were.

## Out of scope

- Changing `search_knowledge` or shipping a router hook. That needs its own issue after this result.
- Fine-tuning the embedding model.
- Other embedding models (one model first, then a bake-off only if the result is promising).

## Done when

- `research/<date>-embedding-routing/` holds the README (question, pre-registration, results, verdict), the tooling, the corpus manifest and scored `results/` snapshots, in the same layout as the local-routing study.
- The README gives a clear verdict per question (accuracy, cross-lingual, abstention, cost), including "no gain" where that is the answer.
- Independent review per `REVIEW-PROTOCOL.md`.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
