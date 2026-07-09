# Research line: index caps & retrieval scaling (are SPINE limits real?)

Status: DESIGNED, NOT EXECUTED. Absorbs the retrieval-reliability follow-up.

## Problem
Distill's structural limits — SPINE ≤80 lines, tier-2 files ≤60 lines, always-on ≤15 lines —
were design intuition (echoing CC's ~200-line CLAUDE.md guidance), never validated. Two open
questions: (1) are the caps at the right level TODAY, and is "lines" even the right unit?
(2) how do optimal caps move as reader models get more capable — should limits be
contract-dependent rather than constants?

## Provenance audit (step 0, cheap)
Trace each cap to its origin (repo history, knowledge-architecture.md). Pre-registered
expectation: gut feeling + analogy. Record honestly; gut feelings that survive testing
become validated design, not embarrassments.

## Hypotheses
- H1: retrieval quality depends on token density + distinctive-noun retention, not line
  count (E3 evidence: 8-word trigger compression lost recall by dropping nouns, and the
  caps-as-lines proxy misses this entirely). Prediction: a 120-line SPINE with distinctive
  entries beats an 80-line SPINE with compressed entries.
- H2: there is a real degradation knee (context-rot literature: 0.92→0.68 accuracy as
  irrelevant context grows), but it sits FAR above 80 lines for frontier models and lower
  for cheap models → the cap should be a function of the reading model's measured retrieval
  capability (same contract abstraction as capability-contract-routing.md — an INDEX BUDGET
  per contract).
- H3: the binding constraint today is not index size but retrieval COMPLIANCE (SPINE was
  Read in only 17/33 real sessions) — a cap optimized for an unread file is meaningless.

## Design
### E-A: size/density × retrieval grid (synthetic, controlled)
- SPINE variants: {40, 80, 120, 200 entries-worth} × {rich descriptions, noun-preserving
  compressed, aggressive 8-word compressed}. Entries beyond the real 59 are synthesized
  filler domains (realistic, non-overlapping) — pre-registered before variants are built,
  authored by a clean agent (E3a lesson: train/test separation; commit order ≠ independence).
- Probe battery: held-out paraphrased probes per E3 methodology (clean-agent authored),
  n≥2, plus over-read + read-token-cost metrics (E3b lesson: recall alone is off-target).
- Readers: 3 model tiers, same battery → per-tier curves. Output: recall/precision/token-cost
  vs (size × density × reader tier). The knee per tier, if any, IS the evidence-based cap.
### E-B: compliance instrumentation (real usage, passive)
- Instrument session starts: did the monitor read SPINE? which files? (transcript mining,
  contamination-safe method). 2+ weeks of real data. If compliance <100%, the intervention
  test is a session-start hook (structural checkpoint — execution-gap prediction: hook ≫ rule).
### E-C: capability-scaling probe
- Rerun E-A's battery on the cheapest tier vs frontier: if cheap models hold recall at 200
  entries, caps are theater; if they knee early, caps must be contract-dependent and the
  SPINE has a REASON to stay small while cheap models participate in sessions.

## Integrity requirements
- Pre-register probe sets and grid BEFORE building variants; clean-agent authorship both
  sides; judge/scorer outside variant-authoring context; report per-cell, no invented
  thresholds (craft/self-benchmark-integrity.md — all of it applies).

## Decision mapping (pre-committed)
- Caps validated at ~current levels → keep, re-document as validated, add token-budget
  equivalent alongside line counts.
- H1 confirmed → change distill-process caps from LINES to TOKEN BUDGETS + noun-preservation
  rule (free win only if retrieval holds; else opt-in knob per release policy).
- H2 confirmed → index budget enters the model-contract record (ties the two lines together).
- H3 dominant → priority shifts to the compliance hook, caps become secondary.

## Why this matters for the economics strategy
SPINE carry is re-priced every request (measured $12/window at 3.6k tokens). If caps can be
evidence-based token budgets per reader contract, index size becomes a MANAGED cost with a
known quality frontier instead of a folk rule.
