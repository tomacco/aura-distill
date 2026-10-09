---
id: task-25
title: Instrument memory operations with local retrieval traces and honest usage statistics
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [enhancement, area:memory-service]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/83
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/83

## User story

As a user, I want retrieval and write statistics automatically from the access layer so I can see cost, latency, misses and maintenance debt.

## Execution

Phase: B1 - Foundations.
Blocked by: #81, #77, #80
Part of #74.

## Scope and decisions

Implement the agreed event schema at the common read/write boundary. Capture operation/trace ID, schema and service version, client, store revision/scope, timing, candidate/returned counts and IDs, output size, budget truncation, cache state, errors and conflict/retry outcomes where available.

Distinguish requested, selected, delivered, acknowledged and demonstrated-use signals. Maintenance, index rebuild and prefetch do not count as user task use. Expose instrumentation coverage; direct file access is unobserved unless an adapter actually records it.

Operational diagnostics stay local by default with bounded retention and user controls. Raw queries, content and sensitive identifiers are not automatic telemetry; richer local debugging is separately opt-in and redacted. Local-only knowledge cannot leak via remote routing requests, telemetry or caches. Sharing is a separate consent/schema, per #32/#31. Statistics failure must not silently corrupt memory or block a valid read.

Keep footprint, returned tokens/bytes, real model usage and billing separate (#40). Reuse #32 for the dashboard and #55 for distillation reports; expose machine-readable data and a compact CLI report here.

## Acceptance criteria

- [ ] Contract fixtures reconcile at least one raw event with aggregation; repeated/retried operations do not inflate successful retrieval counts.
- [ ] Reports show engine/end-to-end timing coverage, delivery counts, unknown usefulness, actual activity, errors, archive/active/total footprint and budget debt separately.
- [ ] Disabled diagnostics, disk full, retention rotation and partial traces degrade explicitly without failing otherwise valid reads.
- [ ] Privacy fixtures prove excluded local content and queries do not enter shared/exported events; no remote collection starts by default.
- [ ] Consumers #62, #32 and #55 can use the versioned schema without re-estimating missing usage.

Implementation PRs must reference this issue and follow AGENTS.md and REVIEW-PROTOCOL.md. Use synthetic isolated fixtures; do not copy live user knowledge into code, tests or public artifacts.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
