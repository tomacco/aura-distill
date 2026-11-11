---
id: task-40
title: Return scoped retrieval misses without claiming global knowledge absence
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [enhancement, area:memory-service]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/66
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/66

## Execution update (2026-09-10)

Part of #74. Blocked by: #82, #62

The current contract below supersedes conflicting mechanics or acceptance criteria in the historical proposal.

Replace the proposed unconditional SPINE completeness footer. A domain index does not establish absence of a fact, and archived or inaccessible knowledge may exist outside the startup view.

Define response semantics with #81: matches; no match in searched scope; ambiguous; partial/incomplete; unavailable/stale. Include authorized store revision and coverage, without revealing excluded topics. A complete catalog supports enumeration/integrity; lexical or semantic search does not prove a natural-language fact was never recorded. Distinguish exact identifier absence from failure to find an answer.

### Current acceptance

- [ ] No match is explicitly bounded to searched scope/revision; a model is never instructed to convert it into an unconditional never-distilled claim.
- [ ] Tests cover alternate wording, facts inside broad domains, archives, stale indexes, excluded scopes, offline snapshots and malformed/unindexed records.
- [ ] Active/archive catalog integrity checks run deterministically, but passing them does not assert semantic search completeness.
- [ ] Unknown/partial/forbidden outcomes are distinguishable and do not trigger unbounded whole-store retry loops.
- [ ] Consumer-stub fixtures validate miss outcomes here; #84/#87 later integrate them. Full harness timing and behavior are measured in #88/#90.

<details>
<summary>Original report and proposal (preserved historical context)</summary>

## Problem

In the 2026-08-18 benchmark (#62), the negative-lookup scenario ("did we distill X?", where X was never distilled) took **18.1 s** — twice a positive single-file lookup (~9 s). The agent correctly answered "no", but only after reading SPINE, grepping the whole store, reading the closest-plausible file, and grepping again: absence currently requires 4–5 verification steps because the agent doesn't know whether the index is exhaustive.

## Proposal

Make the SPINE's completeness an **explicit contract** instead of an implicit hope. A one-line footer, maintained by distill:

> This index is complete: every distilled domain is listed above. If a topic has no matching entry, no knowledge exists for it — answer "not distilled" without store-wide verification.

With that contract, a miss is answerable right after the SPINE read: ~4 s instead of 18 s.

## Risk

If distill ever writes a knowledge file without its SPINE entry, the contract turns a maintenance bug into confident false negatives. Mitigation: a deterministic test that every `*.md` under the store (excluding archive/) is reachable from SPINE — the contract line is only honest while that test is green. (The rules already say "The SPINE is your memory. Treat it as authoritative" — this issue makes that claim verifiable and actionable for misses.)

## Acceptance (via #62 suite)

- [ ] Miss scenario ≤ ~8 s with correct `found=false`.
- [ ] Orphan-file test added to the deterministic suites; contract line present only when it passes.
- [ ] No regression on positive lookups.

---
Filed by `claude-fable-5-distill-tomacco` (Claude Fable 5, Claude Code CLI on Ivan's Windows box). Address me by sign-off name in comments.

</details>

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
