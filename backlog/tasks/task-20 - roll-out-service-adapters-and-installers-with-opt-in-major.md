---
id: task-20
title: Roll out service adapters and installers with opt-in major adoption and files-only fallback
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [enhancement, area:memory-service]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/88
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/88

## User story

As a user, I want my supported harness to adopt the software edition only after I review its requirements, with a working files-only option if I cannot install it.

## Execution

Phase: B2 - Major client rollout.
Blocked by: #87, #79
Part of #74.

## Scope and decisions

Integrate the transport core into supported Claude Code/Codex client configuration and installer lifecycle. Coordinate Antigravity #67/PR #68 explicitly; discovery freezes which clients are required for the release. Missing/unreleased integrations do not silently expand the gate.

Use the major-consent/channel mechanism from #79; do not add a second approval convention. Fresh install, same-major update, legacy major transition, decline, disable/remove and offline/degraded behavior all preserve knowledge and persisted preferences. Test actual startup/discovery/invocation through harness traces; schema exposure is not evidence of invocation.

Keep file-only users on their supported path and identify instrumentation gaps for fallback. Do not claim remote writes are supported by a read-only chat credential.

This story closes on installation/configuration/consent plus a migration-interface stub. Actual format cutover, post-cutover writes/export and rollback belong to #89, avoiding a completion cycle.

## Acceptance criteria

- [ ] Each release-required client has observed contract/invocation tests and a documented support/degraded-mode matrix.
- [ ] Sandbox fresh/upgrade/skipped-major/reinstall/decline/disable/uninstall cases pass on supported platforms.
- [ ] Existing user files/preferences remain intact; major adoption always uses the pre-side-effect review boundary.
- [ ] Both selected CLI and MCP transport paths include discovery/startup overhead in #62-derived traces; legacy fallback remains available.

Implementation PRs must reference this issue and follow AGENTS.md and REVIEW-PROTOCOL.md. Use synthetic isolated fixtures; do not copy live user knowledge into code, tests or public artifacts.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
