---
id: task-59
title: "Feature: Confidence scoring + proportional surprise response"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: []
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/6
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/6

## Problem

All corrections are currently treated equally. A correction on a principle validated 10 times should trigger MORE investigation than a correction on something mentioned once. Currently distill has no mechanism for this.

## Proposed mechanism

Knowledge entries gain confidence through repeated validation:
- Praised/confirmed → confidence goes UP
- Corrected → confidence goes DOWN (and triggers investigation proportional to prior confidence)

The key insight: **surprise is proportional to confidence.** A high-confidence failure is an alarm, not just an update.

## Response scaling

| Prior confidence | Correction response |
|---|---|
| provisional | Update silently |
| validated 2-3x | Update + note what changed |
| validated 5x+ | Investigate: wrong principle or new context? |
| non-negotiable | Full metacognition — check all dependent principles |

## Biological analogy

In cognitive science: belief revision under surprise. Low-confidence failure = "oh well." High-confidence failure = system-2 activation: "if THIS was wrong, what else is wrong?"

## Implementation areas

1. `rules/distill.md` — retrieval applies knowledge with assertiveness proportional to confidence
2. `distill-process.md` — encoding tracks praise/correction signals, bumps confidence
3. Knowledge file format — add confidence metadata
4. New: paradigm failure detection when high-confidence belief is contradicted

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
