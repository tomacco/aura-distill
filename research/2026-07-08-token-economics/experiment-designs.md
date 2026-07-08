# Experiment Designs — Token Economics (2026-07-09, pre-registration)

Status: DRAFT pending clean-context adversarial review (per `craft/self-benchmark-integrity.md`
+ `craft/adversarial-review-methodology.md`). No scored run before the review verdict.

Decision frame (user directive, 2026-07-09): every outcome is classified as either
**FREE WIN** (identical distill output, fewer tokens → release candidate) or
**TRADE-OFF KNOB** (tokens saved vs something lost → opt-in flag + explicit consequence docs).

Platform note: all runs on Claude Code subscription metering (Max), headless `claude -p
--output-format json` for token counts. $ figures are API-equivalent counterfactuals.
Batch runner rules: idempotent per-cell, detect "hit your session limit" → abort with
distinct exit code (ops/session-limits-continuation.md).

---

## E1 — Model routing on real task archetypes

**Question.** Which of Ivan's real task archetypes survive routing to cheaper models
(haiku-4.5 / sonnet / opus-4.8) with no material quality loss vs the default best model?

**Design.** 6 archetype tasks distilled (sanitized) from the mined session dataset, chosen
to span the mechanical→judgment axis:
- T1 mechanical transform: convert a 40-row CSV to a nested JSON schema with 3 exact rules
- T2 extraction: pull 6 specific facts from a ~200-line noisy build log
- T3 code comprehension: answer 3 questions about a ~150-line unfamiliar script
- T4 debugging reasoning: diagnose a CSS sticky-header failure from symptom description + code
- T5 design judgment: steelman/attack a flawed A/B experiment design (seeded with 4 known flaws)
- T6 knowledge application: given `ops/windows-tooling.md` content verbatim, write a
  PowerShell + Python snippet that avoids 3 encoded gotchas (tests: can a SMALL model APPLY
  distilled knowledge — the distill-as-router hypothesis depends on this)

**Arms.** claude-haiku-4-5, claude-sonnet-(latest available in CLI), claude-opus-4-8, and the
session default (fable) as reference. IDENTICAL prompt text per task across arms; no system
prompt differences; run via `claude -p` with tools disabled (pure text tasks) to avoid
tool-availability asymmetry.

**Measurement.** Output tokens + wall time per cell from JSON usage; quality graded by a
clean-context judge agent given a per-task rubric (pre-written BEFORE runs, in this file's
companion `e1-tasks/` dir) and the four outputs SHUFFLED + model-blinded (A/B/C/D labels,
random order per task).

**n=1 per cell** — report direction + magnitude only; NO thresholds, NO percentages implied
precise. A task "survives" routing only if the judge ranks the cheap output equal-or-better
AND finds no rubric violation; ties reported as ties.

**Disclosed builder choices.** Task selection is by the incumbent's author; archetypes were
chosen for coverage, not to flatter routing; T5/T6 are expected to favor big models (this is
stated BEFORE runs).

**Output classification.** Routing table update for `ops/model-tiering.md` (knowledge, not
product) + evidence for whether distill should ENCODE per-task routing rules.

## E2 — Can distilled routing rules change delegation behavior?

**Question.** If distill encodes a routing knowledge file, does a fresh agent actually route
differently (and correctly) vs no routing file?

**Design.** Prototype `ops/model-routing.md` written from E1 results. Two arms, N=2 each
(tight-loops pattern): clean Claude Code agent (worktree, no distill dir except SPINE+file
under test) given the same 5-item task list and asked to delegate each item to subagents
choosing models. Arm A: SPINE + routing file; Arm B: SPINE without it. Measure: model choices
per item + stated rationale. Success = arm A choices match the routing table on ≥ the
mechanical items; report raw choices, no scores.

**Note.** This tests behavior change, not end-quality (quality is E1's job).

## E3 — SPINE diet (process optimization; free-win candidate)

**Question.** SPINE is 3.6k tokens read every session (~65% of distill's fixed floor). Can a
~1.2k-token diet SPINE (title + when-to-read only, compressed descriptions) preserve
retrieval routing?

**Design.** 8 probe scenarios pre-registered in `e3-probes.md` BEFORE the diet SPINE is
written (guards builder bias): each names a user request/action and the knowledge file(s) a
correct session-start monitor should read. Arms: full SPINE vs diet SPINE, clean agent
(haiku? NO — same model both arms, session default), asked: "given this SPINE and this user
message, which files do you read?" N=2 per arm per probe.

**Metric.** File-selection recall (did it pick the file(s)?), reported per probe. If recall
holds → FREE WIN (SPINE compression guideline into distill-process.md). If recall drops on
nuance-dependent probes → TRADE-OFF KNOB (compact-SPINE option).

**Integrity.** Diet SPINE written by the incumbent's author AFTER probes are frozen; both
arms get identical instructions; probe list committed in the same commit as this design
(pre-registration), diet SPINE in a later commit.

## E4 — Distill invocation full cost (measurement, not experiment)

Main-loop cost of 12 real `/distill` turns already measured (median ≈ $1.3 API-equiv).
Missing: the spawned distill subagent (invisible in project transcripts). Measure from THIS
session's live subagent usage tags + one instrumented /distill run at session end (it will
distill tonight's signals anyway — dual use). Report tokens by phase.

## E5 — Cache-cadence arithmetic (deterministic analysis)

From the mined per-request dataset: (a) cost decomposition (cache-read tax vs 1h-write tax vs
output) per model; (b) counterfactual context hygiene: re-price every request with resident
context capped at {60k, 100k} (simulating /clear discipline + leaner always-on context) holding
work constant (output + fresh input unchanged); (c) marginal cost of the distill floor (5.5k of
~30k boot) per session vs per request. No LLM calls; sanity-checked arithmetic; assumptions
stated inline. Known limitation: capping context CAN change work quality — this is a cost
bound, not a behavior claim; stated on the page.

---

## What we will NOT claim
- No cross-vendor orderings, no subscription-$ savings (metering unverified), no "X% saved by
  distill" without netting distill's own costs (write + carry + retrieval), no precision from
  n=1/n=2 cells.
