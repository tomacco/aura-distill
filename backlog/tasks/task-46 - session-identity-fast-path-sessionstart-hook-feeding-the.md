---
id: task-46
title: "Session-identity fast path: SessionStart hook feeding the distillation ledger"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [enhancement]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/56
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/56

## Context

The distillation ledger (#46) resolves conversation identity with a beacon nonce + transcript grep — zero install surface, works on any client. Ivan approved a **hooks + fallback** design: a SessionStart hook that writes `{session_id, transcript_path}` to a state file is the faster, grep-free path, with the beacon as fallback.

## Why it is not in the #46 PR

Registering a hook means merging a nested `hooks` structure into the profile's `settings.json`. The installer's current settings.json handling is a line-oriented `sed` insert — acceptable for one flat key, structurally unsafe for nested JSON (malformed-JSON user files, key collisions, idempotent re-runs, uninstall). This deserves its own reviewed design rather than riding along:

- Safe JSON merge in BOTH installers with zero new dependencies (PowerShell has ConvertFrom-Json; bash has no guaranteed jq/python — needs a robust strategy or an explicit documented dependency)
- Managed-block semantics for JSON (upsert + clean removal on uninstall), mirroring the markdown managed blocks
- Backup + atomic write per `craft` installer-safety rules
- Codex equivalent (or documented absence — fallback still covers it)

## Acceptance criteria

- [ ] SessionStart hook writes session state; ledger uses it when present, beacon fallback otherwise
- [ ] settings.json merge is idempotent, survives malformed input without data loss, uninstalls cleanly
- [ ] Sandbox tests for fresh/upgrade/malformed/uninstall paths on both installers

Part of #53 (auto-distillation epic). Follow-up to #46.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
