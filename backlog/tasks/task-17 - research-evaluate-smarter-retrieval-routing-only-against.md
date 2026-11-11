---
id: task-17
title: "Research: evaluate smarter retrieval routing only against measured miss classes"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [area:memory-service, type:discovery]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/91
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/91

## User story

As a user, I want smarter retrieval only where it improves observed failures enough to justify added cost and complexity.

## Execution

Phase: Later - Evidence gated.
Blocked by: #90
Part of #74.

## Scope and decisions

Use held-out miss/ambiguity/error classes from the first release evaluation to choose a bounded experiment. Candidates include query expansion, hybrid semantic retrieval, reranking, graph traversal or a model-assisted fallback. No candidate is preselected.

Compare against the deterministic selector with identical corpus, scope, harness, quality criteria and full latency/token accounting. Avoid retrieval-popularity feedback loops: delivered is not useful, maintenance is not user demand, rare directives retain applicability-based priority. Define abstention, fallback, offline and user control.

Before any scored run, write and independently review a fresh protocol, held-out split, decision rule and run budget. If no material unmet need remains, close as not planned with the evidence; no speculative backend build.

## Acceptance criteria

- [ ] A concrete observed failure class and baseline are linked; candidate has a falsifiable benefit hypothesis.
- [ ] Experiment accounts for extra inference/network/index maintenance and cold-start costs, with privacy and scope parity.
- [ ] Outcome is adopt/reject/defer with data; any adopted change gets a separate implementation issue and opt-in policy where it adds a tradeoff.

Implementation PRs must reference this issue and follow AGENTS.md and REVIEW-PROTOCOL.md. Use synthetic isolated fixtures; do not copy live user knowledge into code, tests or public artifacts.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
