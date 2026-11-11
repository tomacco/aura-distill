---
id: task-32
title: "Discovery: audit legacy auto-updaters before introducing a software major release"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [enhancement, area:memory-service]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/76
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/76

## User story

As an existing user who enabled auto-update, I need assurance that unknown old installations cannot silently cross into new software requirements.

## Execution

Phase: A0 - Upgrade discovery.
Blocked by: None; ready for discovery.
Part of #74.

## Scope and decisions

Audit released updater instructions, installers, raw download URLs, VERSION checks, optional client skills, mirrors/overrides and release workflows. Current main distill.md instructs an opted-in agent to fetch main/VERSION and then overwrite dispatcher/process/monitor from main. This observation must be checked against actual shipped tags and adapters.

A gate present only in a future updater cannot protect clients that never received it. Decide a compatibility-channel/bootstrap strategy for old fixed URLs before publishing software-layer payloads there. Options are hypotheses: preserved legacy endpoints/branch, channel manifest, safe bootstrap notice or separately distributed major. Account for clients skipping every intervening release, cached/mixed responses, prereleases and unattended/noninteractive runs.

Produce a release/dependency manifest proposal and a precise consent boundary. Prior always-update permission does not authorize a new runtime/service/account/network model. Users must be warned to read and understand changes and explicitly choose the target major before installation/migration. Respect company approval processes; no evasion, silent install or assertion that a tool is approved.

No user-count telemetry is needed to protect unknown installations.

## Acceptance criteria

- [ ] Compatibility matrix covers supported released updater paths and an oldest-supported client that skips directly to the future major announcement.
- [ ] ADR identifies which historical URLs must stay safe, required publication order and the exact point before new payload install/execution/migration where consent is enforced.
- [ ] User notice and noninteractive behavior are specified; no response means remain on files-only, never consent.
- [ ] Sandbox reproductions use captured shipped updater instructions and fixture endpoints; no live-profile testing.
- [ ] Independent review resolves the legacy bootstrap gap before upgrade-policy implementation.

Implementation PRs must reference this issue and follow AGENTS.md and REVIEW-PROTOCOL.md. Use synthetic isolated fixtures; do not copy live user knowledge into code, tests or public artifacts.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
