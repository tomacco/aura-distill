# Research line: capability-contract routing (name-free, deprecation-resistant)

Status: DESIGNED, NOT EXECUTED (Ivan directive 2026-07-09: design first, careful with
staleness — do not ship anything that rots in 2 months or names models).

## Problem
Routing knowledge expressed as model names ("haiku for X") deprecates with every lineup
change and silently degrades performance when capabilities shift. E1's verdicts carry a
July-2026 expiry for exactly this reason. We need routing decisions grounded in measured
capability and cost STATS, with names appearing only in refreshable data, never in policy.

## First-principles decomposition

Three layers, separated by how fast they rot:

| Layer | Content | Rot speed | Where it lives |
|---|---|---|---|
| POLICY (durable) | matching rule: "cheapest contract covering the task's demands with margin; fail UP on missing/stale data" | years | knowledge (craft/ops) |
| TAXONOMY (slow) | demand dimensions tasks can declare | ~yearly | knowledge |
| CONTRACTS (fast) | per-model measured demand-coverage + cost ratios | weeks-months | data file with expiry + provenance, auto-refreshed |

### Demand taxonomy (draft v0 — from E1 archetypes + external task-taxonomy findings)
- D1 mechanical fidelity (exact-rule transforms, extraction) — saturates early, cheapest tier
- D2 code comprehension (unfamiliar code, control-flow side effects)
- D3 sustained constraints (multi-file refactors, invariants held across long output)
- D4 adversarial/latent inference (flaws that must be INFERRED, not read)
- D5 verification discipline (test-fire habits, checking own work — E1: the habit-shaped miss)
- D6 long-context synthesis
- D7 tool-use orchestration
Each task/spawn declares its demands; the orchestrator matches, doesn't name.

### Model contract (per available model; a DATA record, not knowledge)
- capability vector: measured pass/margin per demand (from the calibration battery)
- cost: price ratio vs cheapest available tier (input + output separately; ratios are more
  stable than $), tokenizer factor, context window, verbosity factor (E1: 3-7x output-token
  spread for identical answers — unit price ≠ per-task price)
- provenance: battery version, date, n; staleness_threshold (default 60d) + INVALIDATED-ON:
  any model added/removed from the lineup

### Calibration battery (the hard design problem)
- Small (cost-bounded) but DISCRIMINATIVE: E1 showed mechanical probes saturate (every tier
  passes); separation comes from D4/D5-shaped probes. Battery = 1-2 probes per demand,
  rubric-gated, blind-judged by a model outside the battery, n≥2.
- Auto-trigger: lineup change detected (CLI model list) or contracts past expiry.
- Anti-saturation maintenance: when all tiers pass a probe, the probe is dead — retire and
  replace (probe bank versioned; scores comparable only within battery version).

### Safety principles (non-negotiable in design)
1. FAIL UP: missing/stale/ambiguous contract → best available model. Degraded routing may
   only cost money, never quality.
2. Margin, not threshold-kissing: route down only when the cheaper contract covers demands
   with headroom (define margin from probe score distribution, not invented constants).
3. Risk modifier: irreversible/externally-visible tasks route up one tier regardless.
4. Verbosity-adjusted cost: rank by expected per-task cost (price × verbosity factor), not
   unit price.

## Relationship to spawn profiles
The same contract abstraction covers the tier axis (scribe/scout/builder = TOOL contracts).
A spawn decision = (tool tier × model contract) matched to (task demands × risk). This line's
real payoff is likely delegation shaping more than model choice (E2: orchestrators already
choose sensibly; lever order puts routing 3rd of 4).

## Validation plan (when executed)
- V1: battery discriminativeness — do probe scores actually separate current tiers? (If not,
  the whole line stalls here — this is the go/no-go gate.)
- V2: policy-vs-table A/B — orchestrator with contracts+policy vs with E1-style named table
  vs nothing (E2 rerun): decisions quality + staleness behavior under a simulated lineup change
  (remove a model → does the policy fail up?).
- V3: cost-outcome on real delegated work (spawn logging feeds this — see learned-spawn-profiles
  in follow-ups; the logging schema should record declared demands from day one).

## Deliverable shape (if validated)
- knowledge: `craft/routing-policy.md` (policy + taxonomy, no names, no numbers)
- data: `{DISTILL_DIR}/data/model-contracts.json` (names live ONLY here, with expiry)
- mechanism: calibration battery script + probe bank (distill repo, versioned)

## Pre-registered risks
- Battery cost vs discriminativeness tension (hard probes are the expensive ones).
- Contract expiry cadence vs Anthropic release cadence mismatch → long fail-up periods
  (acceptable by principle 1; measure how often).
- Overfitting the taxonomy to today's model landscape — taxonomy review yearly.
