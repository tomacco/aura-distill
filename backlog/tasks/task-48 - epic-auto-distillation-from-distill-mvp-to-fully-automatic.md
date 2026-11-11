---
id: task-48
title: "EPIC: Auto-distillation — from /distill MVP to fully automatic memory"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: []
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/53
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/53

## Vision

`/distill` was the MVP: user-triggered so the user *feels* the system working. The end state is **fully automatic distillation** — every conversation gets distilled exactly once, cheaply, without being asked — while keeping the visibility that made the MVP convincing (digest reports, propose-mode) and the release frame's full-user-control guarantees.

**Manual `/distill` stays first-class.** Many users have learned to distill by hand; auto-distill complements it (and is sometimes simply faster), never replaces it. The structured post-distill report (#55) is the surface that ties the two together: a manual run reports its own duration/tokens/learnings plus what auto-distill did since the last manual run.

## The program

**Phase 0 — Hygiene (unblocks everything)**
- #52 Agnostic `AGENTS.md`, `CLAUDE.md` pointer, every-PR-references-an-issue rule

**Phase 1 — Foundations**
- #46 Distillation ledger (`data/distill-ledger.jsonl`) — coverage tracking, dedupe, resume-delta handling
- #47 INBOX (`inbox/` folder) — unified pre-distillation channel: explicit user saves + session-signal marks

**Phase 2 — Evidence before defaults**
- #49 Simulated-session benchmark: marks-based vs full-transcript distillation (quality via pinned blind judge, tokens end-to-end including the marking tax). Decision rule: significant, **pre-registered** gain or discard; real replayed sessions primary, synthetic only after calibration; hard token budget — the experiment must not burn the owner's working tokens
- #48 In-session pre-distill marks — approve-or-discard strictly on #49's verdict (no weak middle path)

**Phase 3 — Economics**
- #50 Stage-based model routing: extraction on cheap tier, synthesis on mid tier, frontier NEVER. Builds on the capabilities layer (v1.1.10) and the capabilities skill (PR #38).

**Phase 4 — The auto-distiller + unified visibility**
- #51 Opt-in background agent: discovery (ledger diff) → OS-native scheduling → headless execution with fail-fast on limits → digest report. Propose-mode default; full-auto is the knob.
- #55 Structured post-distill report: duration, per-stage tokens + model, learnings, inbox consumed, auto-runs since last manual run (depends on #40's token split; shared template with #51's digest)

## Dependency graph

```
#52 (hygiene)
#46 (ledger) ──────────────┐
#47 (inbox) ──► #48 (marks) ├──► #51 (auto-distiller) ──► #55 (report; + #40)
        #49 (benchmark) ────┘        ▲
#50 (routing) ───────────────────────┘
```

## Binding constraints (from the release frame)

- Any token-vs-something trade = explicit opt-in knob with documented consequences, or it doesn't ship
- New features get full user control day one (enable/disable/remove + persisted choice)
- Routing: full transparency always, explicit user approval always
- Distillation never runs on frontier-tier models
- All development/testing in the sandbox harness — never against real profile data

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
