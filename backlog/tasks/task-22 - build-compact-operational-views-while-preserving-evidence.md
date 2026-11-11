---
id: task-22
title: Build compact operational views while preserving evidence and directive applicability
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [enhancement, area:memory-service]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/86
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/86

## User story

As a user, I want the knowledge loaded for a task to stay concise while the full supporting history remains inspectable.

## Execution

Phase: B3 - Maintenance.
Blocked by: #85, #63
Part of #74.

## Scope and decisions

Separate durable evidence from current operational views. The compiler may include a bounded synthesis stage with declared inputs/output, model-policy controls and checks; ordinary retrieval does not rerun it. Cache/version materialized views and invalidate on source changes.

Preserve applicability, rationale needed for decisions, exceptions, counterevidence, corrections, citations and binding directive wording. Importance does not imply global loading. A small root/domain index is a derived compatibility/navigation view; the complete catalog lives behind retrieval. Connect SPINE byte/token budgets to #41 without introducing another unbounded list of archived names.

Budget enforcement is code at publication, not another instruction to compact. If no valid view fits, retain source/pending content and return an unresolved budget outcome; do not silently publish a misleading summary.

Implement the software-enforced lifecycle operation using the policy already delivered in #73: preview/apply/restore, reversible cold demotion, pins, unknown activity, exception reporting and oscillation control. Use #83 task-activity signals and the common transaction path. This is where the later runtime enforcement of the files-only policy is completed.

## Acceptance criteria

- [ ] Golden semantic fixtures retain conditions, exceptions, conflicts, exact protected wording and source traceability after compaction.
- [ ] Views rebuild from source and invalidate after changes; citations and required-reading references remain valid.
- [ ] Configured root/per-view byte or token budgets are enforced mechanically, with estimator/tokenizer version recorded.
- [ ] Overflow is recoverable and visible; original history is never rewritten to make a size metric pass.
- [ ] #62 measures loaded context and relevant-knowledge coverage as well as latency; compactness alone is not the quality gate.
- [ ] The #73 policy runs through the service with safe repeat/crash/retry, task-versus-maintenance activity separation and archived/rare-directive recall tests.

Implementation PRs must reference this issue and follow AGENTS.md and REVIEW-PROTOCOL.md. Use synthetic isolated fixtures; do not copy live user knowledge into code, tests or public artifacts.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
