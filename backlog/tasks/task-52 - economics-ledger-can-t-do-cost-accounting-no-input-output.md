---
id: task-52
title: "Economics ledger can't do cost accounting: no input/output/cache token split"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [enhancement]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/40
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/40

## Summary

The `/distill` economics ledger (`data/economics.jsonl`) mixes two different axes and cannot compute real cost:

- `distill_tokens` is a single **aggregate** (the spawned agent's total usage, when the harness surfaces it). It does not distinguish input, output, or cache tiers.
- `written_tokens` / `spine_tokens` / `kb_tokens` are `chars/4` **size proxies**, not billed tokens.

Neither captures the input vs output vs cache split that actually determines price. Today the ledger is a footprint tracker, not a cost tracker.

## Why it matters

Token pricing is per-class and very uneven (e.g. output around 5x input; cache-read around 0.1x input; cache-write above input). A distill run is input-heavy and cache-read-heavy: the subagent reads `distill-process.md`, the SPINE, and several tier files, then runs many tool turns that re-send a growing (cached) context, and writes comparatively little output. Costing a blended aggregate at one rate can overstate real cost several-fold, because most tokens are cheap cache reads rather than expensive output.

## Where the real split is available

Per API response `usage`: `input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`. Aggregated sources that already carry the split:

- An LLM gateway's per-request spend log (prompt/completion tokens + computed cost), when distill traffic routes through one.
- Claude Code OTLP usage metrics (`claude_code.token.usage`, broken down by `type`: input / output / cacheRead / cacheCreation).

The spawned-agent aggregate the command currently logs does not carry the split.

## Proposal

Separate the ledger's two concerns:

1. Keep the `chars/4` fields as an explicit knowledge-base **footprint** metric (consider renaming, e.g. `kb_footprint_tokens`, so it is not read as a cost figure).
2. Replace the single `distill_tokens` with the four token classes plus a computed `cost_usd`, populated from a real source (gateway spend log or OTLP) rather than the harness aggregate. Leave the fields `null` when no split source is available, consistent with the existing "never invent numbers" rule.

## Notes

- Rates are provider- and model-specific. A `cost_usd` field needs a small rate table, or it should read cost directly from the gateway / OTLP source that already computes it.
- Related: #32 (local-first usage dashboard) would consume this data. This issue is the upstream data-model fix that makes a cost view possible.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
