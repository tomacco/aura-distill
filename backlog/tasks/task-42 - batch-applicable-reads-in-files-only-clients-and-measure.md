---
id: task-42
title: Batch applicable reads in files-only clients and measure realistic retrieval
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [enhancement, area:memory-service]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/64
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/64

## Execution update (2026-09-10)

Part of #74. Blocked by: #75, #62

The current contract below supersedes conflicting mechanics or acceptance criteria in the historical proposal.

Track A prerequisite for #80. Implement natural batching using existing supported harness capabilities, coordinated with #78. No new end-user software is required.

### Current acceptance

- [ ] After discovering independently applicable files, issue reads together when the client supports it; preserve sequential discovery only for genuine data dependencies.
- [ ] Verify batching capability and behavior per supported client; unavailable parallelism is explicit rather than claimed.
- [ ] #62's reviewed protocol measures required-fact/constraint coverage, harmful extras and observed timing against the realistic incumbent. Historical <=8-second projections and identical-file-set rules below are superseded.
- [ ] Fresh isolated agent tests demonstrate the revised instructions; legacy fallback remains usable when the later service is disabled.

#84 later owns service-side traversal/batching. This files-only improvement does not wait for it.

<details>
<summary>Original report and proposal (preserved historical context)</summary>

## Problem

The retrieval instructions (distill.md rules) don't say anything about *how* to read matched knowledge files, and the 2026-08-18 benchmark (#62) shows each sequential read costs a near-constant ~3.5–4 s inference roundtrip — file size is irrelevant (1.4 KB and 7.6 KB cost the same). An agent that reads matched files one-by-one pays ~4 s × N; one that batches them pays ~4 s once.

## Proposal

Add an explicit retrieval protocol to the distill rules text:

> After reading SPINE, issue ALL matched knowledge-file Reads in a single message (parallel tool calls). Only serialize when a file's content genuinely determines what to read next.

Gains stand alone even without #63:
- Session start (3 files): 10.8 s → ~7 s (2 roundtrips).
- Ambiguous (3 files): 14.3 s → ~7–8 s.
- Multiplies with #63's `read-with:` closures: fan-outs (8 files) 35–40.5 s → ~9–10 s.

## Notes

- Pure instruction-text change — no store format change, no migration.
- Installer's managed-block rewrite applies it to both Claude's and Codex's pointer targets; verify the Codex harness also supports parallel tool calls (if not, note it as Claude-only wording).

## Acceptance (via #62 suite)

- [ ] Session-start and ambiguous scenarios ≤ ~8 s with identical file sets retrieved.
- [ ] No scenario regresses in correctness (right files, right miss verdicts).

---
Filed by `claude-fable-5-distill-tomacco` (Claude Fable 5, Claude Code CLI on Ivan's Windows box). Address me by sign-off name in comments.

</details>

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
