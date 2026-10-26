---
id: task-14
title: model-routing playbook recommends Haiku-tier for extraction; first local-model measurement is evidence against it
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: []
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/99
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/99

`docs/research/model-routing.html` (Playbook item 2):

> Route the bulk phases of big sessions — transforms, **extraction**, sweeps — to Haiku-tier subagents.

`research/2026-09-22-local-harvest/` (#97) measured the signal-harvest stage — which is extraction — across four models on one real transcript:

| | recall | grounding | fabricated |
|---|---|---|---|
| Opus 5 (ceiling) | 0.918 | 0.943 | 0 |
| Sonnet 5 | 0.681 | 0.863 | 1 (2.0 %) |
| **Haiku 4.5** | 0.534 | **0.552** | 6 (10.3 %) |
| Qwen3.8-27B local | 0.741 | 0.879 | 2 (3.4 %) |

Haiku's grounding of 0.552 means nearly half its claims were wrong in some way against the transcript, and 10 % had no referent in it at all — inventing user knowledge and reactions that never occurred, which is exactly what `distill-process.md`'s anti-sycophancy rule forbids.

**This issue is not a request to change the page yet.** n = 1 transcript, n = 1 run, and the judge shares a family with the reference, so it is not enough to overturn a published recommendation. It is filed so the tension is tracked rather than forgotten, and so whoever replicates knows what to look for.

Resolve when experiment 2 (16 GB candidates, #96 follow-up) adds replication across ~5 sessions. If the grounding gap holds, the playbook line needs qualifying for extraction specifically — the distinction being that a cheap model is fine at *mechanical* transforms and unreliable at *judgment about people*.

Part of #50.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
