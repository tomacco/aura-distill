---
id: task-24
title: Retrieve a budgeted knowledge bundle from task intent in one service operation
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [enhancement, area:memory-service]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/84
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/84

## User story

As a working model, I want applicable knowledge for my task in one operation so I do not reason through files and cross-reference chains.

## Execution

Phase: B2 - Read path.
Blocked by: #82, #83, #62, #63, #66
Part of #74.

## Scope and decisions

Implement the ADR contract with deterministic scope/entity/alias/text selection first. Route supported entity/time/status/artifact requests to existing capabilities; expose unavailable coverage without invented results. Integrate required-reading expansion (#63) and scoped miss outcomes (#66).

Return applicable knowledge, stable source/version references, short selection reasons, freshness/conflicts, scope and budget status. Keep exact-source inspection available. Preserve conditions and exceptions; include mandatory applicable directives before optional detail. If required content exceeds the budget, expose an explicit incomplete/overflow outcome and retrieval continuation rather than silently omitting constraints.

Bound traversal/work and cache by corpus revision, authorization scope, overlay, query/policy and budget. Shared-cache hits must not reveal another scope. No additional LLM inference in the default retrieval path; advanced routing requires its own measured gate.

One logical request may require pagination on overflow or clarification for ambiguity. Do not conceal those round trips in performance reporting.

## Acceptance criteria

- [ ] Single-operation happy paths cover exact and alias lookup plus fan-out, with scoped misses and ambiguity as first-class outcomes.
- [ ] Required-fact and applicable-directive checks pass across active/archive fixtures; irrelevant authoritative material is not injected solely due to popularity.
- [ ] Bounded cycles, cache invalidation after corrections, cross-scope cache isolation and budget overflow are exercised.
- [ ] Contract-level fixture timings and knowledge coverage pass using the #62 harness/stub; full supported-harness comparisons belong to client rollout and release verification, so this issue can close before those adapters ship.
- [ ] Selection is inspectable and exact-source retrieval works for every returned reference.

Implementation PRs must reference this issue and follow AGENTS.md and REVIEW-PROTOCOL.md. Use synthetic isolated fixtures; do not copy live user knowledge into code, tests or public artifacts.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
