---
id: task-30
title: "Ship the files-only redesign: thin catalogs, preserved evidence and recoverable migration"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [enhancement, area:memory-service]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/78
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/78

## User story

As a files-only user, I want a bounded navigation surface and concise operational knowledge while retaining the evidence needed to revisit decisions.

## Execution

Phase: A1 - Files-only implementation.
Blocked by: #75, #62
Part of #74.

## Scope and decisions

Implement the reviewed files-only design in architecture, dispatcher/process/monitor instructions and supported client files. Keep source history, protected wording, applicability and exceptions intact; use catalogs/pointers rather than expanding every archived name in startup context. Source/operational separation is a file convention here, not a new database.

Coordinate #41 for thin-SPINE checks, #64 for natural batching and #73 for reversible lifecycle. Expose scoped/partial misses in agent instructions without waiting for the service-specific #66. No mandatory new runtime, daemon, connector, account or background process.

Provide preview and recoverable migration via existing harness capabilities, support manual edits and interrupted runs, and describe limitations honestly. Align all supported adapters; do not assume unmerged PR #68 has shipped. Add isolated synthetic fixtures and validate instructions with fresh agents.

## Acceptance criteria

- [ ] Synthetic mature-store before/after fixtures preserve source hashes, directive wording, applicability, corrections and reachable archived knowledge.
- [ ] Fresh supported-harness sessions retrieve required facts using only files and existing capabilities, with scoped misses and explicit overflow/uncertainty.
- [ ] Migration preview, interruption recovery, repeated runs and restore preserve originals and subsequent user changes.
- [ ] All runtime/install surfaces are inventoried; no new mandatory software/network/account dependency is introduced.
- [ ] #62 measures files-only versus incumbent with natural batching; results distinguish instruction compliance from deterministic enforcement.

Implementation PRs must reference this issue and follow AGENTS.md and REVIEW-PROTOCOL.md. Use synthetic isolated fixtures; do not copy live user knowledge into code, tests or public artifacts.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
