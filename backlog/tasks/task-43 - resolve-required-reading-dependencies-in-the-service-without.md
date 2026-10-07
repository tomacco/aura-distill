---
id: task-43
title: Resolve required-reading dependencies in the service without inflating SPINE
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [enhancement, area:memory-service]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/63
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/63

## Execution update (2026-09-10)

Part of #74. Blocked by: #82, #62

The current contract below supersedes conflicting mechanics or acceptance criteria in the historical proposal.

The service now owns required-reading expansion. Preserve the original fan-out diagnosis below; the proposed SPINE read-with denormalization is historical and is not the implementation direction.

Model required, optional and context-conditional references in the versioned catalog selected by #81. Resolve applicable dependencies for a request before returning its knowledge bundle. Do not load every cross-reference transitively by default. Use stable IDs, revision-based invalidation, deduplication and bounded traversal. A derived legacy index may expose navigation hints, but never a second hand-maintained dependency graph.

### Current acceptance

- [ ] Deterministic tests cover required versus optional links, applicability conditions, cycles, diamonds, broken targets, archived dependencies and cross-scope targets.
- [ ] Traversal is bounded; missing required or forbidden dependencies produce an explicit incomplete result without leaking excluded metadata.
- [ ] Corrections and reference changes invalidate affected plans/views; no stale duplicate closure survives publication.
- [ ] A consumer stub exercises closure in one logical request with selection explanations; actual #84 integration occurs in that later story.
- [ ] Contract-level fixtures evaluate fan-out coverage, irrelevant extras and traversal timing here. Actual harness end-to-end evidence belongs to #88/#90; earlier absolute latency projections are hypotheses, not acceptance thresholds.
- [ ] Root SPINE remains budgeted; closure size cannot evade #41 by fattening its entries.

<details>
<summary>Original report and proposal (preserved historical context)</summary>

## Problem

The 2026-08-18 retrieval benchmark (#62) shows fan-out scenarios are the slowest retrieval class: **35–40.5 s for 8 files**, vs ~9 s for a 2-file lookup. Two causes, both structural:

1. **Required reading is discovered hop-by-hop.** SPINE points to a project file; the list of 6 additional required files lives *inside* that file. Even with perfect read-batching that forces ≥3 serialized inference rounds (SPINE → project file → its cross-refs), and each roundtrip costs a near-constant ~3.5–4 s regardless of file size.
2. **Mid-chain xref reasoning is expensive.** The benchmark caught three ~10–11 s "which cross-refs do I follow?" decision spikes — all at the moment the agent had to reason over pointers found inside a just-read file.

## Proposal

Denormalize the **required-reading closure into the SPINE entry itself** — a compact, paths-only suffix, e.g.:

```
- [scalable-core-world](projects/scalable-core-world.md) — ... Read for any work on that repo.
  read-with: craft/interaction-feel.md, craft/webgl-render-perf.md, craft/parallel-agent-git-isolation.md, ops/github-platform.md, ops/windows-headless-bench.md, craft/multi-agent-contribution-arch.md
```

Retrieval then becomes: read SPINE → one inference pass over a pre-computed list → all files in one batched round. Projected: **~2 roundtrips ≈ 9–10 s** for today's 35–40 s scenarios (with #64's batching instruction; the two combine to deliver the gain).

## Costs / constraints

- **Denormalization**: when a file's cross-refs change, distill must update its SPINE `read-with:` line too. Needs an explicit rule in distill-process.
- **Tension with #41 (SPINE drifting into digests)**: `read-with:` must stay **paths only, never content**. The benchmark shows latency is roundtrip-bound, not byte-bound, so compact path lists don't hurt latency; #41's token concern is respected by forbidding digests, not by forbidding lists.
- SPINE's 80-line cap: `read-with:` as a continuation line of the existing entry, or count budget explicitly.

## Acceptance (via #62 suite)

- [ ] Fan-out scenarios ≤ ~12 s (from 35–40.5 s), decision spikes gone.
- [ ] Correctness gate: identical (or superset-equal) file sets retrieved per scenario.
- [ ] Deterministic installer/format suites green; distill-process rule for keeping `read-with:` in sync added and tested.

---
Filed by `claude-fable-5-distill-tomacco` (Claude Fable 5, Claude Code CLI on Ivan's Windows box). Address me by sign-off name in comments.

</details>

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
