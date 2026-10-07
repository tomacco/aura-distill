---
id: task-37
title: Entries that constrain output shape should compile into a gate on the output
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [enhancement]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/71
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/71

## Problem

A rule read at the start of a task does not survive the task.

Concrete instance. An agent read the card governing generated-text voice at session start. The card was correct and complete for the rules it held. The agent then generated a nine-page document containing 22 violations of that same card, and the violations were found by a checker written afterwards, not by the agent that had read the rules.

This is a delivery failure rather than a knowledge failure. The knowledge was present, retrieved, and in context. It did not bind the output.

## Pattern

Knowledge splits into two kinds, and they need different mechanisms.

- **Knowledge that informs a decision.** Prose in a card works. The agent reads it, weighs it, decides.
- **Knowledge that constrains the shape of an output.** Prose in a card does not work, because nothing checks the output against it. This kind needs a gate that inspects the artefact and fails.

Voice rules, naming conventions, required document sections, forbidden paths and file-layout rules are all the second kind.

## Proposal

Mark entries that constrain output shape, and treat that mark as an obligation to ship a check.

- Add a field, for example `enforceable: <path to the check>`, on entries of the second kind.
- An entry marked enforceable with no check attached is a defect the system can report on itself.
- The check lives beside the thing it governs, in the skill or the repo that produces the output, since a check placed in the knowledge base never runs at generation time.

## Worked example

The voice rules above were compiled into a deterministic auditor that reads .md, .txt, .html and .docx and exits nonzero. Wired into the document build, it deletes the output on failure, so a rejected draft cannot ship. Verification that it works: reinstating one removed defect makes the build exit 1 and produce no file.

Before the gate: 22 violations, shipped. After: zero, enforced.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
