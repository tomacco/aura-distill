---
id: task-19
title: Migrate existing Markdown stores with a dry run, source preservation and rollback
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [enhancement, area:memory-service]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/89
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/89

## User story

As an existing user, I want to adopt the memory service without losing knowledge or being trapped if I disable it.

## Execution

Phase: B3 - Migration.
Blocked by: #86, #88, #73
Part of #74.

## Scope and decisions

Provide a versioned migration plan and dry-run report showing source counts/hashes, inferred metadata, unresolved records, scope boundaries and active-view changes. Preserve ambiguous records for resolution rather than inventing authority or validation dates.

Import from the reviewed legacy format, retain originals, verify references/indexes, then switch the active generation atomically. Handle interrupted/repeated migration and mixed-version/direct-edit clients explicitly. Keep machine-local content structurally outside shared requests/storage. No test imports from real user profiles.

Provide export and rollback that include knowledge accepted since cutover; reverting to an old backup alone loses post-migration writes. Keep the opt-in enable/disable/remove contract and storage-format compatibility documented. Archive/cold demotion never means project completion or semantic invalidity.

This story is migration into the software major; Track A file-format migration is owned by #78. Software migration runs only after the explicit major-review boundary from #79.

## Acceptance criteria

- [ ] Synthetic mature, malformed, archived, overlapping-scope and protected-entry stores survive dry run/import/export with source-hash and reachability checks.
- [ ] Interrupted and repeated migrations are safe and deterministic; no active generation is partially published.
- [ ] Rollback after new writes preserves those writes or durably queues them for explicit reconciliation; no silent loss.
- [ ] Unsupported legacy/mixed-client writes are detected and reconciled or rejected according to the ADR.
- [ ] Operational runbook shows adoption, diagnosis, disable, export and recovery; defaults do not alter real stores without opt-in.

Implementation PRs must reference this issue and follow AGENTS.md and REVIEW-PROTOCOL.md. Use synthetic isolated fixtures; do not copy live user knowledge into code, tests or public artifacts.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
