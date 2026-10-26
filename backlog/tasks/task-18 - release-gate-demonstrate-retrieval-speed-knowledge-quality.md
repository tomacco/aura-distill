---
id: task-18
title: "Release gate: demonstrate retrieval speed, knowledge quality and lifecycle safety end to end"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [enhancement, area:memory-service]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/90
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/90

## User story

As a user, I want a reproducible result showing whether the new layer makes real retrieval faster and safer before it becomes my normal workflow.

## Execution

Phase: B4 - Release evidence.
Blocked by: #62, #84, #85, #87, #86, #73, #89, #88
Part of #74.

## Scope and decisions

Run the frozen measurement protocol using #62, including natural-batching incumbent, same-corpus service, local/remote strata, cold/warm starts, expected misses, ambiguous/archived/rare-directive cases, growth and churn. Keep transport/selection/view-change effects separable. Include failed/time-out cells and observed harness coverage.

Add release exercises for interrupted writes, stale indexes/caches, concurrency, scope isolation, offline recovery and migration rollback. Use synthetic/public-safe data; optional private field validation is a separate explicitly authorized exercise and never checked into fixtures.

Publish a reproducibility manifest and public-safe aggregate results with sample counts, uncertainty and all overheads. Keep historical #62 results immutable and label incomparable versions. If practical gain or quality criteria fail, record a no-go or scoped release and the next experiment; do not move thresholds or declare victory from server-only latency.

Independent review is required before the release decision. This issue is a gate, not authorization to deploy or merge unrelated PRs.

The service release is a semver major after the files-only release. Exercise legacy-skipping, pinned/declined files-only, noninteractive and explicit-consent upgrade cases. Publish the required-software/change guide before offering adoption; no historical auto-update grant substitutes for major consent.

## Acceptance criteria

- [ ] Frozen quality/non-inferiority and latency decision rules produce an explicit go/no-go, with per-scenario failures and uncertainty visible.
- [ ] Reported end-to-end gain includes discovery/startup/network/model turns and is stratified by observed client and corpus scope.
- [ ] Lifecycle tests recover an archived project and apply rare constraints; lower kb_tokens alone cannot pass.
- [ ] Concurrency, privacy, crash recovery, migration and rollback exercises pass; unresolved release blockers are named.
- [ ] README/roadmap and issue statuses state what is implemented, measured, optional or deferred; no unmeasured speed claim ships.

Implementation PRs must reference this issue and follow AGENTS.md and REVIEW-PROTOCOL.md. Use synthetic isolated fixtures; do not copy live user knowledge into code, tests or public artifacts.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
