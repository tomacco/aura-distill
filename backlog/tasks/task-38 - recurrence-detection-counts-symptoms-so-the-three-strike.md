---
id: task-38
title: Recurrence detection counts symptoms, so the three-strike mechanism rule cannot fire
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [enhancement]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/70
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/70

## Problem

`distill.md` instructs: when the same type of correction recurs three or more times despite being encoded, treat the mechanism as limited and flag it for a structural change.

The rule assumes the recurring thing has one name. In practice a user reports each instance in the vocabulary of that instance, so one underlying cause arrives as several differently named corrections. Each name gets its own counter. No counter reaches three. The rule stays silent while the friction repeats.

Observed case: four voice rules recorded separately over six weeks (em dashes, antithesis, hype words, throat-clearing). One cause. Highest individual counter: two.

## Contributing factor

The same entry was marked `confidence: hardened`. That marker describes how well established a rule is. It was read as evidence that the domain was covered, which is a different claim. A rule can be perfectly valid and cover a third of its own domain.

## Proposal

Two changes, both small.

1. **Count at the domain level, not the rule level.** Track how many distinct corrections a single domain has absorbed. A domain that keeps absorbing new sibling rules is the signal, whatever the siblings are called. Suggested threshold: three distinct rules added to one domain without any being retired.

2. **Separate validity from coverage.** `confidence: hardened` should not imply that a domain is understood. Either add an explicit coverage field, or state in the vocabulary documentation that confidence describes a single entry and says nothing about whether its domain has been mapped.

## Test for the fix

Replay the voice-rules history. A working implementation raises a flag at the third sibling rule, before a human notices the pattern independently.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
