---
id: task-21
title: Expose the memory contract through CLI and MCP transports with scope/version parity
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [enhancement, area:memory-service]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/87
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/87

## User story

As a user switching harnesses, I want the same memory semantics and known corpus scope with minimal client-specific retrieval instructions.

## Execution

Phase: B2 - Client integration.
Blocked by: #84, #85, #63, #66, #61, #65
Part of #74.

## Scope and decisions

Implement the selected CLI/local and remote MCP transports over the common engine. Both are required for this story; runtime/deployment details come from the approved ADR. Reuse #61's sync protocol and preserve its existing read-only versus sync scopes. Do not silently grant chat clients write access.

Implement version negotiation, timeouts, offline snapshot semantics where available, explicit remote inability to access local-only knowledge, and transport error mapping. Same authorized shared revision must mean the same knowledge across paths (#65). Contract-level synthetic tests can close this story without a full interactive client installation.

Actual harness instructions, tool discoverability, installers and rollout belong to #88. Transport code implementation waits for the Track A files-only release through its foundation dependencies.

## Acceptance criteria

- [ ] CLI and MCP return equivalent knowledge for the same authorized synthetic shared corpus/revision; intentional local overlays remain explicit and isolated.
- [ ] Version/permission/timeout/stale/offline/error outcomes match the reviewed contract and regression tests cover #65.
- [ ] Read-only credentials cannot write and excluded data never enter remote requests or results.
- [ ] Contract/stub tests pass independently of interactive harness rollout; endpoint timings are labeled transport-level only.

Implementation PRs must reference this issue and follow AGENTS.md and REVIEW-PROTOCOL.md. Use synthetic isolated fixtures; do not copy live user knowledge into code, tests or public artifacts.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
