---
id: task-8
title: "Files-only runtime follow-ups from the #114 closing check"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: []
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/116
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/116

Routed from the PR #114 closing check (claude-fable-5-1, clean profile, CONFIRMED), per REVIEW-PROTOCOL.md rule 8. Neither item is `[HARM]`.

- [x] **Ask-first paragraph vs pre-1.2 bullet** (`distill-process.md` ~:740). The standalone "whatever the lifecycle setting … archive it the same way (ledger, move)" paragraph follows the bullet that says "move nothing" on an unmigrated store. Add "on a migrated store".
- [ ] **"Exactly where it was" after reverting a first migration.** Revert keeps `archive/LEDGER.md` with its appended restore lines, but on a first migration the ledger is a path the migration created. Decide whether revert deletes a ledger the plan created, or state that it stays. Check that a leftover ledger doesn't affect Step 0 classification or a later `migrate-store`. Extend fresh-agent part D to assert it (it currently checks only `store-before`'s files).
- [x] **DECISIONS.md D-2026-09-23-13 text is stale:** it says the updater doesn't fetch the helper, but #113's updater does.

Part of #78 · Part of #74

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
