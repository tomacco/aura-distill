---
id: task-26
title: Build versioned memory storage and a rebuildable complete catalog
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [enhancement, area:memory-service]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/82
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/82

## User story

As a user, I want durable source history and stable references so indexing, compaction or a rename cannot erase or orphan knowledge.

## Execution

Phase: B1 - Foundations.
Blocked by: #81, #77, #80
Part of #74.

## Scope and decisions

Implement the selected storage contract, not a speculative backend. Preserve original source material and directive wording separately from operational views. Model applicability, provenance, contradictions and supersession without silently upgrading inferred facts to directives.

Build a catalog spanning active and archived authorized knowledge. Scope catalog identity by store, revision and authorization/local overlay; distinguish missing, incomplete and inaccessible. Rebuild indexes from canonical records. Define how legacy file edits enter a new version; no silent second writer. Connect to #61 through its existing protocol boundary rather than implementing a competing sync engine.

## Acceptance criteria

- [ ] Synthetic import preserves source bytes/checksums and stable references through rename, archive, restore and index rebuild.
- [ ] Every published catalog entry resolves at its declared revision; broken references and unsupported schema versions produce explicit errors.
- [ ] Active/archive state is independent of authority, confidence, last validation and actual task activity.
- [ ] A stale/incomplete catalog cannot claim corpus-wide absence; scope isolation applies to metadata as well as content.
- [ ] Rebuild is deterministic and cannot mutate canonical history; storage failure recovery is tested against the selected design.

Implementation PRs must reference this issue and follow AGENTS.md and REVIEW-PROTOCOL.md. Use synthetic isolated fixtures; do not copy live user knowledge into code, tests or public artifacts.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
