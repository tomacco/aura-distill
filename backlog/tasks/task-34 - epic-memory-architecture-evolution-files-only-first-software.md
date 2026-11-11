---
id: task-34
title: "EPIC: Memory architecture evolution — files-only first, software layer as an opt-in major"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [area:memory-service, type:epic]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/74
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/74

## User story

As a user, I want a better files-only memory system first, and a separately reviewed major upgrade to software-owned reads/writes when my environment permits it.

## Execution

Phase: Program.
Blocked by: None; ready for discovery.

## Scope and decisions

Deliver two ordered editions. Track A ships a redesigned files-only architecture using existing harness capabilities, without new mandatory runtime, daemon, service, connector, account or network dependency. Track B then implements the read/write software layer as a semver major with explicit informed opt-in. Unknown existing installations and managed-company environments must remain safe and supported.

Legacy updater compatibility is a release prerequisite: a future warning does not protect an old updater fetching fixed main URLs. Resolve and test that path before any software-major payload is published. Prior auto-update consent is insufficient for the new dependency model.

Faster retrieval is a hypothesis to measure in each edition. Reuse #62 with realistic natural batching and identical authorized data. Service discovery and measurement design may proceed alongside Track A; service implementation starts only after the files-only release gate. Keep shared sync under #61, git optional, and local-only knowledge local. Semantic synthesis remains an explicit model operation.

No speculative vector/graph/model-router dependency is required. The complete auto-distillation and synthesis programs remain separate. ROADMAP.md records sequence and backlog disposition; issues own live blockers/status.

## Acceptance criteria

- [ ] A supported files-only redesign is released before service implementation; legacy-skipping auto-update paths cannot silently adopt the software major.
- [ ] Software adoption is a semver major and requires explicit review/consent before new dependency side effects or storage migration; files-only decline/pinning remains supported.
- [ ] Each implementation waits for its applicable reviewed contract and measurement prerequisites. Files-only implementation does not wait for service architecture discovery.
- [ ] One task-intent request can return applicable, budgeted knowledge plus provenance, scope, freshness, and explicit limitations.
- [ ] Writes preserve sources and validate a complete versioned change before publication; rejected changes remain recoverable.
- [ ] Local diagnostics distinguish retrieval delivery from usefulness; no automatic sharing of queries or memory content.
- [ ] Migration, offline behavior, rollback, quality, and measured latency pass the release gate. Manual distillation remains first-class.
- [ ] Child issues, existing backlog relationships, and the repository ROADMAP.md agree. Closing this planning PR does not close the implementation epic.

Implementation PRs must reference this issue and follow AGENTS.md and REVIEW-PROTOCOL.md. Use synthetic isolated fixtures; do not copy live user knowledge into code, tests or public artifacts.

## Execution sequence

- [ ] #75 (A0 - Files-only discovery): Discovery: specify a files-only memory redesign for restricted environments
- [ ] #76 (A0 - Upgrade discovery): Discovery: audit legacy auto-updaters before introducing a software major release
- [ ] #77 (0 - Discovery): Discovery: preregister retrieval latency and quality comparisons before optimization
- [ ] #78 (A1 - Files-only implementation): Ship the files-only redesign: thin catalogs, preserved evidence and recoverable migration
- [ ] #79 (A1 - Upgrade protection): Protect major upgrades with legacy-safe channels and explicit review before installation
- [ ] #80 (A2 - Files-only release): Release gate: deliver the files-only architecture before software-layer implementation
- [ ] #81 (0 - Discovery): Discovery: decide the memory-service boundary, authority, and read/write contracts
- [ ] #82 (B1 - Foundations): Build versioned memory storage and a rebuildable complete catalog
- [ ] #83 (B1 - Foundations): Instrument memory operations with local retrieval traces and honest usage statistics
- [ ] #84 (B2 - Read path): Retrieve a budgeted knowledge bundle from task intent in one service operation
- [ ] #85 (B2 - Write path): Commit proposed memory changes atomically with validation, provenance and conflict recovery
- [ ] #86 (B3 - Maintenance): Build compact operational views while preserving evidence and directive applicability
- [ ] #87 (B2 - Client integration): Expose the memory contract through CLI and MCP transports with scope/version parity
- [ ] #88 (B2 - Major client rollout): Roll out service adapters and installers with opt-in major adoption and files-only fallback
- [ ] #89 (B3 - Migration): Migrate existing Markdown stores with a dry run, source preservation and rollback
- [ ] #90 (B4 - Release evidence): Release gate: demonstrate retrieval speed, knowledge quality and lifecycle safety end to end
- [ ] #91 (Later - Evidence gated): Research: evaluate smarter retrieval routing only against measured miss classes

Existing core stories: #65 (correctness first), #62 (harness/baseline), #63 (required-reading closure), #66 (scoped misses), #73 (files-only lifecycle), #41/#64 (files-only index/batching). Shared sync #61 remains separately owned.

Start with #65, #75, #76 and #77. Baseline #62 follows the measurement protocol. Files-only release #80 precedes service implementation. Smarter-routing research #91 is optional and does not block either initial release.

Repository roadmap: [ROADMAP.md](https://github.com/tomacco/aura-distill/blob/docs/memory-service-roadmap/ROADMAP.md) (planning branch until its PR merges). Issues own current status and blockers; the roadmap owns scope, sequence and backlog disposition.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
