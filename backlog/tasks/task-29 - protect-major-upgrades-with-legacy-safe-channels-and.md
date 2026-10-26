---
id: task-29
title: Protect major upgrades with legacy-safe channels and explicit review before installation
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [enhancement, area:memory-service]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/79
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/79

## User story

As a user, I want same-line updates to respect my preferences and major changes to wait until I review and explicitly accept the new requirements.

## Execution

Phase: A1 - Upgrade protection.
Blocked by: #76
Part of #74.

## Scope and decisions

Implement the approved legacy-channel strategy before any software major artifacts can reach old auto-update URLs. Software-layer adoption is a semver major (next major, currently expected 2.0.0; verify version at release). Keep a supported files-only channel and a pin/stay-on-files option.

Before installing, executing, registering a service/connector, creating an account requirement or migrating to the new major, display a concise notice linking the full migration/change guide. Explain runtime/dependencies, processes/startup, network/data destinations, storage changes, permissions, resource implications, company-approval responsibility and rollback. Require explicit target-major consent; old auto-update preference, a timeout or a headless session is not consent.

Do not block harmless release metadata/change-guide retrieval needed to show the notice. Gate installation/execution and format migration. Respect decline/defer persistently without repeated interruption. Recheck the approved manifest if payload requirements change. Keep existing user knowledge/preferences intact on download or validation failure.

Update both installers and every shipped updater adapter/path; constrain the version-bump/release workflow so merges do not inadvertently expose a software payload to legacy readers.

Track A closure uses a complete synthetic future-major manifest and guide to prove the mechanism. Before offering the real software major, #88/#90 must validate its actual finalized requirements/guide through the same checks. Track A does not wait for software implementation.

## Acceptance criteria

- [ ] Oldest supported skipped-release, current auto-update on/off, pinned files-only, fresh install, declined/deferred and noninteractive cases have deterministic sandbox coverage.
- [ ] Without explicit major consent, no new software is installed/executed, no connector/service is registered and no major storage migration happens; files-only still works.
- [ ] A synthetic future-major manifest exercises actual installed updater paths, including old fixed URLs and mixed/failed responses.
- [ ] Notice precedes side effects and links a complete requirements/migration guide; controls and decisions persist.
- [ ] Publication ordering and release workflow are verified so a client that missed the guard release remains safe. No claim relies solely on newly added prompt text.

Implementation PRs must reference this issue and follow AGENTS.md and REVIEW-PROTOCOL.md. Use synthetic isolated fixtures; do not copy live user knowledge into code, tests or public artifacts.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
