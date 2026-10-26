---
id: task-31
title: "Discovery: preregister retrieval latency and quality comparisons before optimization"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [area:memory-service, type:discovery]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/77
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/77

## User story

As a user, I want evidence of how much faster retrieval becomes without losing relevant knowledge, so architecture decisions are based on comparable outcomes.

## Execution

Phase: 0 - Discovery.
Blocked by: None; ready for discovery.
Part of #74.

## Scope and decisions

Extend #62 through an experiment protocol; #62 remains the owner of the executable harness and fresh baseline.

Define arms: current supported file retrieval with natural batching; a diagnostic serialized arm only when needed to explain the historical #62 baseline; the same-corpus service path. Separate transport-only comparisons from changes in selection or compaction. Compare local and remote paths separately.

Define timing boundaries: user request to usable knowledge available in the harness, engine duration, transport, tool discovery/startup, model orchestration turns, and time to completed correct task. Use monotonic clocks within processes and correlated trace IDs across them; never subtract unsynchronized host clocks. Include retries and failures.

Cover startup, exact entity/URL, aliases, ambiguous queries, scoped misses, cross-reference fan-out, rare directives, archived recall, conflicts, time/status/artifact queries, offline and cold/warm caches. Mark unsupported axes honestly. Use synthetic personas and scalable corpora; historical live content must not be copied into public fixtures.

Pin corpus hashes, implementation commits, harness/model/tool versions, injected instructions, budgets, cache state and randomized/interleaved order. Equalize unrelated style and permissions. Verify actual injection. Pre-register primary latency and quality endpoints, repetition/sample-size rule, tail-statistic eligibility, practical gain and non-inferiority thresholds, stop conditions and run/token budget before scored comparisons. Calibrate sample-size/variance on a separate pilot, then freeze; do not tune against held-out cases.

Measure required-fact/constraint coverage and harmful extras, not exact file-set identity. Where judgment is needed, keep the judge outside scored arms and blind arm identity. Preserve contested cases and failures. Report real usage where available; proxies and missing values stay labeled.

Compare three editions: current files, redesigned files, and later service. Initial calibration uses the incumbent harness or disposable instrumentation, not the future telemetry layer. Freeze staged comparisons before their scored runs; discovery uses separate pilot cases.

## Acceptance criteria

- [ ] Protocol contains all timing boundaries, reproducibility manifest, scenario generation recipes, held-out separation and frozen decision rules.
- [ ] Independent adversarial review precedes scored runs; findings and revisions are recorded.
- [ ] One raw trace is manually reconciled with reported timings, counts and usage before trusting the instrument.
- [ ] A cheap pilot establishes variance and a bounded run plan; no speed multiplier is promised from historical serialized results.
- [ ] #62 is updated to implement this protocol; verification story consumes it without changing thresholds after seeing outcomes.

Implementation PRs must reference this issue and follow AGENTS.md and REVIEW-PROTOCOL.md. Use synthetic isolated fixtures; do not copy live user knowledge into code, tests or public artifacts.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
