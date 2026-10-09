---
id: task-39
title: Add a Synthesis pass that names the cause behind a cluster of captured symptoms
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [enhancement]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/69
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/69

## The gap

Distillation captures at the resolution the user speaks at. When a user reports a symptom, the symptom gets recorded faithfully. The cause behind a family of symptoms is never named, because nobody ever said it out loud.

A live example from a real knowledge base. One card accumulated four separate voice rules over six weeks: no em dashes, no antithesis construction, no hype words, no throat-clearing openers. Four rules, four confirmations, one entry marked `hardened`. All four are symptoms of a single cause: assistant post-training optimises a conversational turn, so a generated document carries the shape of a chat reply. That cause surfaced in a session where the user asked for the mechanism. Capture alone was never going to produce it.

## Why the rule did not fire

`distill.md` carries the right instinct: when the same correction recurs three or more times despite being encoded, flag that the mechanism may be limited and ask for a structural change.

That rule could not fire. The four symptoms were filed as four different rules, so each counter sat at one or two. A recurrence counter that counts symptoms never reaches its threshold while the parent is unnamed.

Second contributor: the entry was marked `confidence: hardened`. Hardened is a claim about a rule's validity. It got read as a claim about its completeness, which suppressed re-examination of the domain.

## Proposal

Add a Synthesis pass, run rarely and deliberately, separate from per-session capture. It asks a different question: not what did we learn today, but what do the entries we have written share that nobody has named.

Cheap mechanical entry point, which would have caught the example above:

1. Sweep the corpus for its own distress markers: `[RECURRING FRICTION]`, `[OPEN]`, `[CORRECTED]`, and prose of the form "keeps happening", "still not", "offered N times and never built".
2. Cluster the hits by domain.
3. For each cluster of three or more, propose a single cause that would produce all of them.

The corpus in the example contained this line, written by an earlier session and filed as friction to own: *"the em dashes still get WRITTEN and swept out afterwards rather than avoided at write time"*. That is the system reporting a limited mechanism. Nothing was watching for it.

## Acceptance bar for a proposed cause

Cause-hunting invents plausible false parents, and a confident false cause is worse than an honest list of symptoms. So a candidate cause is accepted only when it does two things:

1. Explains every logged symptom in the cluster.
2. **Predicts a symptom that nobody logged.** That prediction is then measured against real artefacts.

In the worked example the proposed cause predicted a defect no card mentioned: a heading with an appended `, and why it matters` clause. Measurement on the document under review found 7 of 27 headings carrying it. A candidate that predicts nothing new is a summary wearing a cause's clothes, and should be rejected.

## Escalation trigger

The session that found the cause differed in one detectable way. The user asked **why** rather than reporting **that**: "if we understand the motivations and underlying mechanisms we can produce way better results."

Worth adding as a heuristic: a request for the mechanism behind a correction escalates the session from capture to synthesis.

## Scope

This is a new layer, not a change to capture. Capture works and should stay cheap and frequent. Synthesis is rare and expensive by nature, because the pattern is only visible across cards and across months.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
