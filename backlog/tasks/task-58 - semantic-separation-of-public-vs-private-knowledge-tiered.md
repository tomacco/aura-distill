---
id: task-58
title: Semantic separation of public vs private knowledge (tiered auto-load + gating)
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: []
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/28
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/28

## Problem

distill knowledge is auto-loaded into the agent's context (SPINE → domain-matched files) at session start. That's the point — but it means **all** captured knowledge is equally exposed:

- Users increasingly **demo or share** their distill structure with others.
- Some captured knowledge is **sensitive** — personal information about the user or about third parties — that shouldn't auto-load, shouldn't surface in a demo, and should be safe if the directory ever leaks.

Today the only real mitigation is self-censorship: only write things that are "OK if leaked." That caps how useful distill can be for genuinely personal knowledge work.

## Motivating scenario

Open a fresh agent session and ask *"who am I / what am I working on right now."* With everything in one public tier, it happily reconstructs a full profile from auto-loaded knowledge. Desirable in private; not always desirable in a room full of people.

## Proposed behavior (prototyped locally, provisional)

A **private tier** alongside the normal (public) knowledge:

- Private files are **never auto-loaded**. The "read SPINE-listed domains at session start" rule does not apply to them.
- **Default posture = public-only.**
- The agent **offers** to pull private context when a task plausibly needs it, and reads it only on explicit user confirmation (or a session-level "include private" opt-in).
- Private contents are never surfaced in shared output / artifacts / demos.
- The public index stays leak-safe **by construction** — private topics aren't listed in it.

This keeps the demo/share property intact (the rich public tier is what you show) while shrinking the sensitive surface to a small, gated kernel.

## Open design questions

1. **Granularity — binary or graded?** Is a binary split (`private` / not-private) enough, or is a graded model needed (e.g. `public` / `internal` / `private`)? No strong data yet either way; leaning toward shipping binary first and letting evidence argue for more.
2. **Who classifies?** Human (explicit tag on capture), system (auto-detect sensitivity), or hybrid (system proposes a classification, human confirms)?
3. **Encryption at rest** (separate, stackable layer). Segregation + a behavioral gate protects against *auto-load* and *casual/demo viewing*, but not against someone who has the files. Real at-rest confidentiality (e.g. `age`/`gpg`) is an orthogonal opt-in worth scoping — with one hard constraint stated honestly: anything the agent can read unattended is readable by anyone at that machine, so encryption only helps where the **key is absent** (a leaked copy, a synced backup, a shoulder-surfer).

## Non-goals / notes

- Not trying to make distill a secrets manager.
- The classification taxonomy should stay **deliberately un-opinionated** until there's usage evidence to justify a specific model.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
