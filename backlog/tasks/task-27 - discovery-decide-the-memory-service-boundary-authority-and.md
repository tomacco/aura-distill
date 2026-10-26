---
id: task-27
title: "Discovery: decide the memory-service boundary, authority, and read/write contracts"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [area:memory-service, type:discovery]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/81
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/81

## User story

As an implementer, I need a reviewed contract and ownership model before building the service, so clients and storage do not develop incompatible meanings.

## Execution

Phase: 0 - Discovery.
Blocked by: #75
Part of #74.

## Scope and decisions

Inspect the actual repository, #61 implementation/field-test evidence, #65, current client adapters, and legacy read/write paths. Record verified facts separately from proposals.

Resolve in an ADR:
- Shared server authority versus local execution, offline snapshots, and the structurally local overlay; precedence and conflict behavior.
- Runtime/package tradeoffs for Windows, macOS/Linux, CLI and MCP, including install weight, startup and network overhead. No runtime or database is preselected.
- Canonical data versus derived indexes/views; stable identity, source/version references, evidence, directives, applicability, contradictions and supersession. Decide record granularity from fixtures.
- Task-intent retrieval, exact source inspection, proposed writes, explicit conflict/error outcomes, budget overflow and version compatibility. Avoid a file-wrapper API that leaves traversal to the model.
- Authorization scopes, sensitivity boundary (#28), and local-only data across requests, results, indexes, diagnostics and backups. Basic isolation is required; a full private-tier product is separate.
- Legacy direct edits: supported reconciliation/import versus rejection; mixed client versions; degraded reads and writes.
- Separate deterministic validation, semantic synthesis, lifecycle policy, and user control. Never equate confidence with authority or coverage.

Produce small disposable synthetic probes where an API/client capability is uncertain. Check prior art before introducing parallel infrastructure. Discovery may split a story when a reviewed contract reveals a genuinely separate deliverable.

Track B discovery may run alongside Track A. Its code implementation waits for #80. Reuse the files-only format and migration decisions where sound. Define pending-evidence versus committed/retrievable states and acknowledgement semantics with examples. Resolve correctness-blocking questions before closing; an experiment plan alone is not a decision.

## Acceptance criteria

- [ ] ADR links observed evidence, alternatives, selected decisions, tradeoffs, unresolved questions and their owners/follow-ups.
- [ ] Versioned request/response examples and invariants cover normal, absent, ambiguous, stale, forbidden, offline, oversized and conflicting cases.
- [ ] A supported-client matrix distinguishes observed capabilities from assumptions and identifies how each client invokes retrieval.
- [ ] Independent design review is recorded and decision-changing findings resolved; implementation tickets reflect the resulting contract.
- [ ] Correctness-blocking experiments are completed and their decisions recorded; only explicitly nonblocking questions remain as follow-ups.

Implementation PRs must reference this issue and follow AGENTS.md and REVIEW-PROTOCOL.md. Use synthetic isolated fixtures; do not copy live user knowledge into code, tests or public artifacts.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
