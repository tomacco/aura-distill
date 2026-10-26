---
id: task-51
title: SPINE.md entries drift into full digests, inflating per-session token cost
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: []
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/41
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/41

## Summary
Over many sessions, `SPINE.md` entries drift from one-line pointers into multi-sentence digests that duplicate the content of their target files. Since `SPINE.md` is read at the start of every session, this inflates the fixed token cost of every session before the user asks anything, and partially defeats the purpose of a thin index that routes to detail files.

## Evidence (observed on a real profile)
- The header states the intended contract: `Max 80 lines` and `Each entry: - [Title](path.md) -- when to read this`.
- Line count was within budget (73 lines), but total size had reached ~31 KB (~8K tokens loaded every session start).
- The largest single entry had grown to ~2,200 chars (~550 tokens); six entries exceeded 800 chars.
- The detail in those entries was already fully present in their target `.md` files, so the index content was redundant.
- Trimming the four largest entries back to one-line pointers cut the file from ~31 KB to ~27.5 KB with zero knowledge loss.

## Root cause
`/distill` appends and enriches entries as knowledge accumulates, but nothing enforces the per-entry length budget implied by the header. The 80-line cap constrains entry *count*, not per-entry *length*, so entries fatten instead of the file growing longer. The one explicit budget in the file is never checked.

## Proposed fix (options, not mutually exclusive)
1. Enforce a per-entry length budget in `/distill` (for example, flag or auto-compact any entry over ~300 chars), in addition to the 80-line cap.
2. When an entry would exceed the budget, push the detail into the target file and keep only the "when to read" trigger in the index.
3. Add a lightweight check that reports total `SPINE.md` size and the largest entries, so drift is visible before it costs tokens.

## Impact
Every session pays the SPINE cost up front. Keeping the index thin directly reduces baseline context usage for all users, not just at session start but again each time a matching domain file is loaded on top.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
