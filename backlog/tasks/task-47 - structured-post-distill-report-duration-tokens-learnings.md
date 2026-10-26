---
id: task-47
title: "Structured post-distill report: duration, tokens, learnings, auto-runs since last manual"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [enhancement]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/55
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/55

## Problem

Many users have learned to distill by hand — that stays a first-class flow alongside the auto-distiller; with the improved features, auto-distill is sometimes simply faster. The end-of-run message of a manual `/distill` is the moment the user *feels* the system working, and today it is unstructured. It should become the visibility surface for the whole program.

## Proposal

A structured post-distill report, fixed template (terse, scannable, comparable across runs), emitted at the end of every manual `/distill`:

- **Duration** — wall-clock time of the distill run
- **Token consumption** — per stage, with the model that ran each stage (routing transparency, #50)
- **Learnings** — what was captured: new entries, updates, corrections, confidence changes, conflicts flagged
- **INBOX** — items consumed this run (#47)
- **Auto-distill since your last manual run** — run count, conversations processed, digest highlights (#51); section absent when auto-distill is disabled

## Dependencies / notes

- Accurate token accounting depends on the economics ledger input/output/cache split (#40) — this issue is a consumer of that fix
- Data sourced from `data/economics.jsonl` + the distillation ledger (#46), not re-estimated
- Auto-distill runs (#51) reuse the same template for their digest, so manual and auto reports read as one system

## Acceptance criteria

- [ ] Fixed report template documented
- [ ] Duration, per-stage tokens + model, learnings, inbox, auto-run summary all present
- [ ] Degrades cleanly when auto-distill is off or ledgers are absent (fresh install)
- [ ] Sandbox-tested

Part of #53 (auto-distillation epic).

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
