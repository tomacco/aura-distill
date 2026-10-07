---
id: task-33
title: "Discovery: specify a files-only memory redesign for restricted environments"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [enhancement, area:memory-service]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/75
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/75

## User story

As a user on a managed laptop, I want improved memory organization using the tools I already use, without installing a new runtime, daemon, database service or connector.

## Execution

Phase: A0 - Files-only discovery.
Blocked by: None; ready for discovery.
Part of #74.

## Scope and decisions

Design the first deliverable as plain files plus instructions executed by the existing supported harness. Existing installation tooling may remain; runtime use must not require a new executable, background process, service, MCP connection, cloud account or network dependency. Developer test tools are not end-user dependencies.

Resolve root/domain catalog shape, evidence versus operational knowledge, directive applicability, stable file references, scoped miss wording and reversible demotion. Identify which invariants remain best-effort instructions in this edition; do not promise software-enforced transactions or automatic retrieval statistics.

Design safe migration from current files, compatibility with old harness instructions, restart/recovery and manual edits. Separate activity from last edit/validation; no observed read history means unknown. Reuse #41/#64 and the lifecycle diagnosis #73. Service-specific enforcement is explicitly deferred.

Record the release-version decision: keep this within the files-only compatibility line if backward compatible; if its file format breaks compatibility, apply the same major-review gate rather than silently calling it a minor update. Do not assume any version number until the compatibility audit concludes. Keeping files-only supported after the software major is a product requirement.

## Acceptance criteria

- [ ] Reviewed design and sample synthetic before/after store establish file format, routing, evidence preservation, migration/recovery and scoped miss semantics.
- [ ] Dependency inventory proves no new end-user executable/service/account/connector is required; existing tooling assumptions are stated.
- [ ] Agent-managed limitations are explicit, including observability gaps and lack of transactional guarantees.
- [ ] Correctness-blocking format and compatibility questions are resolved before implementation; remaining optional questions have owners.
- [ ] Design maps first-release work to #41, #64, #73 and the file-redesign story without waiting for the service.

Implementation PRs must reference this issue and follow AGENTS.md and REVIEW-PROTOCOL.md. Use synthetic isolated fixtures; do not copy live user knowledge into code, tests or public artifacts.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
