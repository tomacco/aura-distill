---
id: task-28
title: "Release gate: deliver the files-only architecture before software-layer implementation"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [enhancement, area:memory-service]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/80
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/80

## User story

As a restricted-environment user, I want a useful supported files-only release before Aura adds software requirements.

## Execution

Phase: A2 - Files-only release.
Blocked by: #78, #73, #41, #64, #79
Part of #74.

## Scope and decisions

Validate and release the files-only redesign through the reviewed compatibility channel. This is an actual deliverable and prerequisite for service implementation, not merely a fallback promised for later.

Use #62's approved protocol for incumbent versus redesigned files. Publish observed latency, loaded context, required-knowledge coverage and limits; do not claim automatic retrieval telemetry or hard runtime enforcement. Exercise archived recall, rare directives, mixed clients, migration/restore and declined-major upgrade.

Confirm the legacy-safe upgrade guard is in place and old skipped-release clients cannot silently receive the software edition. Document the files-only support/maintenance channel and how to stay on it. Service discovery can proceed in parallel; service implementation waits for this gate.

## Acceptance criteria

- [ ] Files-only release exists with reviewed version/compatibility classification, changelog, migration guidance and preserved support channel.
- [ ] Supported-harness synthetic acceptance and fresh-agent retrieval tests pass with no new mandatory user tooling.
- [ ] Comparable benchmark results and limitations are recorded; any regression has an explicit release decision.
- [ ] Legacy-skipping and decline/no-input major-upgrade tests pass before new software publication is allowed.
- [ ] Release evidence and decision are linked; only then are service implementation stories unblocked.

Implementation PRs must reference this issue and follow AGENTS.md and REVIEW-PROTOCOL.md. Use synthetic isolated fixtures; do not copy live user knowledge into code, tests or public artifacts.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
