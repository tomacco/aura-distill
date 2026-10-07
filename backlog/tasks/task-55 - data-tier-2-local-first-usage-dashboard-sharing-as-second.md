---
id: task-55
title: "Data Tier 2: local-first usage dashboard, sharing as second consent"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: []
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/32
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/32

The distill-native telemetry model: give the USER their own numbers first, ask about sharing second.

Local dashboard (dashboard/ dir already exists) showing the user's own:
- /distill cadence and per-invocation cost
- KB growth curve (files, tokens; the vector/graph-backend crossover is ~10x current KB)
- retrieval hits per session (under-retrieval is the real risk — measured: SPINE read in only 17/33 sessions)
- marker distribution over time ([DEPRECATED] accumulation = memory-rot early warning)
- measured distill token overhead (research baseline: ~5-6% of spend)

Then, separately: "share these aggregates?" — opt-in, aggregate-only, published schema, counts and sizes only, content never qualifies. Matches the public promise on docs/token-saving.html.

Build only when a concrete development question needs the data. From the 2026-07-09 session.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
