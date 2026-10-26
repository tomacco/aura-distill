---
id: task-49
title: "Auto-distiller: opt-in background agent for undistilled conversations"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [enhancement]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/51
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/51

## Problem

`/distill` was deliberately an MVP shape: user-triggered, so the user FEELS the system working (full magic prevents observing the effect). Long-term, distillation must be **fully automatic**: a background agent that silently picks up conversations that were never distilled.

## Proposal

An opt-in background auto-distiller with four components:

1. **Discovery** — diff transcript directories against the distillation ledger → list of pending conversations (never re-process; `skipped` entries prevent re-reads of trivial sessions)
2. **Scheduler** — OS-native (Task Scheduler / launchd / cron), NOT in-session scheduling (in-session jobs die with account pauses). Runs headless; must never distill a session that is still live/active.
3. **Executor** — headless `claude -p` per pending conversation: marks-mode when inbox items exist, full-transcript otherwise; model per the routing issue (never frontier); **fail-fast on rate-limit** (headless dies first on account limits — detect the limit string and stop the batch, don't grind)
4. **Reporting** — a digest per run ("learned X, updated Y, 3 conversations processed"). This preserves the feel-it-working property even when the trigger is automatic: the magic is in not having to ask, not in invisibility.

## Release frame (binding)

- **Opt-in**, with full control day one: enable/disable, schedule, model-tier, and mode knobs — all persisted.
- **First release defaults to propose-mode:** the auto-distiller produces staged knowledge changes + digest for one-tap approval; fully-silent auto-commit is the knob you turn after trusting it. (Background writes to real knowledge are the highest-risk surface this project has — see the `_distill_isolation_bak` incident.)
- Subscription-aware: respects metering data; skips runs under limit pressure rather than eating the user's working window.

## Acceptance criteria

- [ ] Never processes the same conversation twice; never touches a live session
- [ ] Survives and fail-fasts cleanly on rate limits (no half-written knowledge)
- [ ] Propose-mode and auto-mode both tested in the sandbox harness (NEVER against real profiles)
- [ ] Digest report emitted per run
- [ ] Cross-platform twins (bash/PowerShell) for discovery + scheduling setup, parity-tested

Part of the auto-distillation epic. Depends on: ledger, routing. Benefits from: INBOX, pre-distill marks.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
