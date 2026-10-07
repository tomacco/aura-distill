---
id: task-44
title: "Retrieval benchmark: natural-batching baseline and repeatable end-to-end service comparison"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [enhancement, area:memory-service]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/62
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/62

## Execution update (2026-09-10)

Part of #74. Blocked by: #77

The current contract below supersedes conflicting mechanics or acceptance criteria in the historical proposal.

Implement the protocol from #77. Keep ownership of the benchmark harness and fresh baseline here; #90 owns the eventual release verdict.

The historical 2026-08-18 results below deliberately serialized tool reads. Preserve them as diagnostic observations; do not use their totals as the sole realistic incumbent or promise their projected improvements. The primary file-based arm allows natural batching. The service and file arms use the same authorized corpus/revision and equivalent task requirements. Exact file-set equality is replaced by required-fact/constraint coverage plus harmful-extras checks because record/view boundaries may change.

### Current acceptance

- [ ] Approved protocol, frozen thresholds, independent experiment review and bounded run budget exist before scored comparisons.
- [ ] Executable isolated harness produces raw traces and manifests including actual injected bytes, corpus hashes, model/harness versions, cache state, arm order, failures and real usage when available.
- [ ] Fresh natural-batching baseline and separate diagnostic serialized arm are labeled clearly. Local/remote and cold/warm runs are separate strata.
- [ ] Timings include request-to-usable-knowledge, engine/transport/startup where observable, model/tool turns and task completion. Unsupported measurements remain null/unknown.
- [ ] One raw trace is hand-matched against the report; repetitions/uncertainty follow the preregistered plan, with no unsupported tail percentiles.
- [ ] Service adapter contract/stub allows subsequent #84/#87 implementation without making baseline capture depend on the service already existing.
- [ ] Synthetic fixtures are public-safe; historical live material is not copied into code or fixtures. Historical results remain immutable.

<details>
<summary>Original report and proposal (preserved historical context)</summary>

## Why

We measured retrieval latency for the first time (2026-08-18, 9 clean-context agents) and found clear optimization levers. Before landing any of them we need a **repeatable benchmark suite** so every retrieval change can prove actual gains and no regression — same bar we hold for the installer (deterministic suites).

## Method used for the baseline (to be codified)

- Clean-context Claude Code agents, zero inherited conversation state.
- Scenarios taken from real session history (project context load, PR review, URL lookup, ambiguous query, negative lookup, session start).
- Protocol: exactly one retrieval tool call per assistant turn, each followed by `echo MARK <label> $(date +%s%3N)`; agent returns structured JSON (marks, files read, bytes, decision rationale).
- Note: the one-call-per-turn rule serializes reads on purpose (it's what makes per-step deltas measurable). It inflates fan-out totals vs. real sessions that batch reads — the per-step cost is the primitive being measured.

## Baseline results (2026-08-18, store = 26 files / 88 KB, model claude-fable-5)

| Scenario | Files/calls | Retrieval time | Correct |
|---|---|---|---|
| Session start (SPINE + identity + prefs) | 3 | 10.8 s | yes |
| Direct URL lookup (×2 runs) | 2 | 8.8 s / 9.5 s | yes |
| Ambiguous query | 3 | 14.3 s | yes |
| Negative lookup (miss) | 2 + 2 greps | 18.1 s | yes (found=false) |
| Project context load (xref chain) | 8 | 35.0 s | yes |
| PR-review fan-out (xref chain) | 8 | 40.5 s | yes |
| MCP path: URL lookup | 4 calls | 20.1 s | **no** (divergent corpus) |
| MCP path: search | 5 calls | 23.0 s | **no** (divergent corpus) |

Key facts the suite must be able to reproduce:
- **Per-step cost is a near-constant ~3.5–4 s** (range 2.8–5.9 s) regardless of file size (1.4 KB vs 7.6 KB identical). I/O is sub-ms; the cost is one model inference roundtrip per step.
- **Cross-ref decision spikes of ~10–11 s** appear when required reading is discovered inside a file mid-chain (3 spikes observed, all in the two fan-out scenarios).
- Fit: `total ≈ 3.5 s + ~4 s × sequential_steps (+ ~10 s per xref decision point)`.
- Token cost is nearly flat: 31k–42k per retrieval regardless of fan-out size.
- Run-to-run variance on totals ~7% (repeat run); individual steps swing ±50%, so compare totals/medians, not single steps.

## Deliverables

- [ ] Scripted harness (headless `claude -p` or Agent-spawning driver) + the fixed scenario set above, checked into `tests/` or `bench/`.
- [ ] Stats output: per-step deltas, totals, median/min/max, correctness (right files retrieved, right found/not-found verdict).
- [ ] Documented "how to run" + a stored baseline JSON to diff against.
- [ ] Correctness assertions are the regression gate; latency is the gain metric. A speed win that changes which files get retrieved is a fail.
- Runs against a fixture store (temp HOME, like the deterministic suites) — never against Ivan's live store by default, and obviously never `-LiveRetrieval`.

Related: #49 measures distillation quality; this issue measures retrieval latency — complementary, no overlap.

---
Filed by `claude-fable-5-distill-tomacco` (Claude Fable 5, Claude Code CLI on Ivan's Windows box). Benchmark design, execution and analysis by me; scenarios sourced from real session transcripts. Address me by sign-off name in comments.

</details>

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
