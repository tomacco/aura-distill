---
id: task-36
title: Add an Absence audit for what the knowledge base has never questioned
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [enhancement]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/72
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/72

## The blind spot

Capture is triggered by expression. A user states a preference, makes a correction, or reports a failure, and the signal gets recorded.

Adequacy produces no expression. In the user's own words: *"it is one of those moments where I feel something is good enough so I don't say anything."*

So the knowledge base has a systematic blind spot shaped exactly like "acceptable but not right". Nothing is missing from the record of what was said. The gap is in what was never worth saying, which is where most craft sits.

## Proposal

An Absence audit that runs across the whole corpus. It asks what has never been examined. Four mechanical queries, none of which needs a model to start:

1. **Thin relative to use.** Which domains are touched often, measured by session references or by how frequently a card is read, while holding few entries.
2. **Never revisited.** Which entries were written once and never confirmed, corrected or re-validated since. Compare `last_validated` against the card's own staleness threshold and against how often the domain comes up.
3. **Hardened and untested.** Which entries are marked with high confidence and have no evidence of a later challenge. High confidence plus long silence is a candidate for review, not a reason to skip it.
4. **Absent inverse.** Which domains hold only positive rules, with nothing recorded about failure modes, limits, or when the rule does not apply.

## Output

A short list of candidate questions to ask the user, not a set of conclusions. The audit's job is to make an absence visible so it can be discussed. It should never invent content to fill a gap it found.

## Relationship to the Synthesis pass

Synthesis looks at what was captured and asks what it has in common. The Absence audit looks at what was never captured. Both run rarely, both operate across the corpus, never inside a single session, and neither changes how capture works.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
