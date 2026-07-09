# Capability-data landscape (research sweep, 2026-07-09)

Method: web research agent, ≥2 sources where possible, single-source claims marked in the
full brief (agent transcript). Condensed classification against our 7-demand taxonomy:

## Reusable AS-IS (do not rebuild)
- Cost/pricing/context/feature metadata: models.dev (MIT, models.json), LiteLLM
  model_prices_and_context_window.json, OpenRouter /models API. Machine-readable, free,
  joinable by model ID. None carry quality scores — pure metadata.

## Reusable WITH CAVEATS (contamination/saturation triage required)
- Code comprehension: SWE-bench Pro / Terminal-Bench / LiveCodeBench (SWE-bench Verified is
  contamination-COMPROMISED — OpenAI stopped reporting it; ~19.8% of "solved" entries
  semantically wrong per 2025 audit).
- Sustained constraints: τ/τ²-bench pass^k (domain-narrow: retail/airline/banking).
- Long-context synthesis: AA-LCR + Epoch — BUT Artificial Analysis free tier BANS
  redistribution (licensing trap for imports).
- Tool-use orchestration: Terminal-Bench, τ-bench, BFCL (open) — no delegation-failure
  decomposition.
- General aggregate: LiveBench (open, monthly refresh), Epoch ECI (longitudinal,
  saturation-resistant). HELM in maintenance mode since 2026-06. LMArena = preference Elo,
  no task decomposition, no official API.

## GENUINE GAPS (where a new matrix adds value — matches our discriminative demands)
- Adversarial inference / review acuity: scored NOWHERE.
- Verification discipline (self-checking): scored nowhere; SWE-bench's solved-but-wrong
  rate demonstrates the absence.
- Verbosity factors (unprompted output-length tendency): published nowhere.
- Delegation-failure taxonomy (not-initiated / insufficient-info / wrong-order — arXiv
  2605.08761) layered on tool-use data.

## Commercial state
No router (Martian, Not Diamond, Azure, Bedrock, GPT-5 auto-router) publishes capability
characterizations as reusable data; "Explainable Model Routing" (arXiv 2604.03527) calls out
the missing auditable rationale. Transparency = real, defensible differentiator.
RouterArena: no router universally optimal; commercial routers over-select expensive models.
2026 Berkeley study: 8 major agent benchmarks gameable to near-perfect scores.

## Build implications (pre-steelman)
1. Matrix = JOIN layer: import metadata (models.dev/LiteLLM), reference open benchmark
   scores with triage flags, measure IN-HOUSE only the gap demands (D4 adversarial
   inference, D5 verification discipline, verbosity factor).
2. Licensing: no AA imports without tier compliance; prefer MIT/permissive sources.
3. Known threat to public probes: a public probe bank on GitHub is contaminated by
   construction for next-generation models (steelman verdict pending on this).
