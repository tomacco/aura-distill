---
id: task-4
title: "Parallel distillation: sessions propose changes, one merger applies them through a journal"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: []
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/129
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/129

## Problem

A distillation reads one session and then edits the shared store in place: SPINE, cards, `contexts.md`, the profile. Every run owns the whole store for its full duration, so the design has three pains.

1. **Parallel runs collide.** Four sessions distilling at once on 2026-10-05 wrote `SPINE.md` and `contexts.md` within the same second, and one overwrote a card another had just written (#127). The lock in #128 makes them take turns, which turns parallel work into a queue: a run waits up to 9 minutes for the one ahead of it.
2. **A crash leaves the store half-edited.** A run that dies after updating a card but before updating SPINE leaves an orphan or a dangling pointer. The `.status` checkpoint records which step was reached, not which files were written, so a resume cannot tell what to redo.
3. **Cost lands on the wrong session.** The session that starts a distillation pays for the whole run, including work caused by other sessions' changes. If it dies, the tokens it spent are lost and the next run starts over.

## Requirements

1. **Parallel by default.** Any number of sessions can distill at the same time. Analysing a session needs only that session and a read-only view of the store.
2. **Stop anywhere.** A run can die at any point and leave the store coherent. Nothing is half-applied.
3. **Resume without rework.** Work that finished is kept. The next agent that picks up the queue continues from the last completed operation.
4. **Exactly once.** Each session's proposal is applied once, even if it is submitted twice or a merge is replayed after a crash.
5. **History and rollback.** Every applied change can be traced to its source session and undone.
6. **Conflicts are explicit.** When two proposals touch the same knowledge, the merge either combines them by rule or flags them for a model or the user. It never drops one silently.
7. **Small fixed cost.** The merge step for a non-conflicting proposal needs no model call.
8. **Works offline on one machine**, and fits the #61 sync protocol when the store is synced.

## Proposed architecture

Split distillation into two steps: **propose**, which runs in parallel, and **merge**, which runs one at a time and is short.

```
session A ─┐                       ┌──────────── merger (one at a time) ───────────┐
session B ─┼─ propose (parallel) ─▶│ proposals/ ─▶ journal ─▶ apply ops ─▶ commit │
session C ─┘   reads store only    └────────────────────────────────────────────────┘
```

**Propose.** Each run analyses its session against a snapshot of the store and writes one file, `proposals/<session>-<transcript-lines>.json`, by atomic rename. The file holds:
- the store revision it read, plus the hash of each card it based a change on
- a list of operations (below)
- the signals behind each operation, with origin and confidence, so the merger and a later reviewer can judge it

The name is derived from the session and how far it was read, so distilling the same session again replaces the proposal and never duplicates it. The INBOX (#47) is the first form of this queue; proposals generalise it from raw signals to finished operations.

**Operations.** The vocabulary carries meaning, so most merges need no text diff:
- `add-entry(index, key, line)` / `remove-entry(index, key)` for SPINE, `contexts.md` and `private/INDEX.md`
- `create-card(path, body)`
- `upsert-section(path, heading, body, base_hash)` for one section of a card
- `append(path, line)` for ledgers and lists
- `move(path, to)` and `archive(path)` for compaction

**Merge.** One merger at a time holds the run lock from #128, which now guards seconds of work. For each proposal, oldest first:
1. Write `applying <proposal>` to `journal.jsonl`.
2. Apply each operation and journal it as done. Operations are idempotent: applying one twice gives the same result, so a replay after a crash is safe.
3. Commit, then journal `applied <proposal>` and move the proposal to `proposals/applied/`.

A merger that dies leaves the journal pointing at the last completed operation. The next agent that runs a distillation, or a scheduled merger from #51, takes the lock and continues from there. Whoever runs the merge pays for it.

**Conflicts.** An operation whose `base_hash` no longer matches the card was planned against an older version.
- Disjoint changes (different sections, different index keys) apply by rule.
- Overlapping changes on the same section go to a model with both versions and both sets of signals, the same "redo the affected domain" policy #61 uses for an overlapping 409.
- Contradictions between high-confidence or `[DIRECTIVE]` entries go to the user as an open question. They are never merged by a model.

**History.** The store is a git repository. Each applied proposal is one commit whose message names the session and proposal, which gives history, blame and rollback (#82). With #61 enabled, the merger's commit is the CAS `POST /sync/commit`, and a 409 sends the proposal back through the conflict path.

## Relation to open work

- **#127 / #128:** the lock stays. It moves from guarding a whole distillation to guarding the merge step.
- **#47 INBOX:** becomes the proposal queue, or its input.
- **#51 / #53:** the auto-distiller runs propose steps in the background and a scheduled merger drains the queue. Propose-mode, the #51 default, is this design with the merge gated on review.
- **#61:** a directive that sync uses version + CAS and no locks. A local lock on the merge step does not conflict with it: the lock serialises merges on one machine, and CAS orders commits across machines.
- **#82:** the versioned storage and stable references that `base_hash` and rollback depend on.

## Open questions

1. Does the merge step fold into #82, or ship first on plain git as its own milestone?
2. Should a session's proposal wait for the user's review by default (propose-mode) or apply automatically when it has no conflicts?
3. Can a proposal edit the always-on preferences in `rules/distill.md`, or only suggest the change? Those edits change every future session.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
