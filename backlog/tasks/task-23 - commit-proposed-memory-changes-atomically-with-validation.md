---
id: task-23
title: Commit proposed memory changes atomically with validation, provenance and conflict recovery
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [enhancement, area:memory-service]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/85
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/85

## User story

As a distiller, I want to submit a versioned change proposal so Aura handles durable writes and validation without requiring filesystem bookkeeping from the model.

## Execution

Phase: B2 - Write path.
Blocked by: #82, #83
Part of #74.

## Scope and decisions

Implement proposal -> validation -> commit against a declared base revision. Validate schema, scope, stable references, source preservation and derived-view budgets. Semantic judgments remain explicit synthesis results with provenance; deterministic checks cannot certify their truth.

Publish canonical changes and matching catalog/view revision atomically under the ADR's selected transaction mechanism. Preserve rejected proposals outside the active view; acknowledge explicit saves only after durable acceptance. Support idempotency, retry after uncertain completion, and explicit conflict recovery. Reuse #61 CAS semantics for shared writes; do not replay overlapping semantic proposals blindly.

Preserve existing authorization: a read-only chat/MCP credential cannot gain write access because a new API exists. Offline write behavior must match the reviewed contract. Provide a supported path for manual edits/import; conflicting direct edits cannot be silently overwritten.

This issue owns the minimal deterministic lossless view builder/validator required for transactional publication. #86 later adds compaction through that same interface; writes must be independently completable without that later compiler. Explicit result states distinguish durable pending evidence, published retrievable knowledge and rejected proposals.

## Acceptance criteria

- [ ] Crash injection at each publication boundary leaves readers on a complete old or new revision; rejected proposals remain recoverable.
- [ ] Duplicate delivery, timeout-after-commit and concurrent overlapping/disjoint edits have tested, documented outcomes.
- [ ] No budget violation drops original evidence, an explicit save, or protected directive wording; overfull active views have an explicit disposition.
- [ ] Unauthorized writes and cross-scope proposals fail without content disclosure or partial mutation.
- [ ] Manual distillation and inbox ingestion can call the API in synthetic integration tests; semantic conflicts are visible in the result.

Implementation PRs must reference this issue and follow AGENTS.md and REVIEW-PROTOCOL.md. Use synthetic isolated fixtures; do not copy live user knowledge into code, tests or public artifacts.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
