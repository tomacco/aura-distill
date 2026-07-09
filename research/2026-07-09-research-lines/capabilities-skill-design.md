# Capabilities-matrix skill — design (S2, local-first; post-steelman)

Status: DESIGNED. Implementation after Ivan reviews the durable-layers PR (the skill
implements METHODOLOGY.md; if that changes in review, this follows).

## What it is
A distill skill (`capabilities-matrix`) the user invokes to measure THEIR model lineup —
including custom/fine-tuned/self-hosted endpoints — producing the local contracts file
`{DISTILL_DIR}/data/capabilities-local.json` that routing policy consumes. Private by
construction: probes generated locally, scores stay local, file excluded from sync sets.

## Flow (supervised, cost-capped)
1. DISCOVER — enumerate the lineup: CLI-available models + user-declared custom endpoints
   (id, invocation method, price if known). Import commodity metadata per JOIN-SPEC
   (models.dev/LiteLLM/OpenRouter allowlist).
2. SCOPE — user picks demands to calibrate (default: the discriminative set D3-D8; D1/D2
   optional — expected to saturate) and n (floor 3, recommended 5).
3. ESTIMATE — dry-run token/cost estimate shown BEFORE anything runs; user confirms.
   Hard cap enforced during the run (abort, keep partial results clearly marked partial).
4. GENERATE PROBES — from per-demand probe-generation recipes (shipped with the skill):
   the agent authors FRESH probe instances + rubrics locally. Recipes specify shape,
   difficulty anchors, and rubric structure — never concrete items. Probes cached locally
   (`data/probes-local/`, gitignored pattern documented) and rotated on battery version bump.
5. RUN — headless per-cell calls (fail fast on limit strings; idempotent cells; text-only
   spawns where the demand allows — tool floors measured separately).
   INJECTION HARDENING: endpoint responses are treated as data; the runner never executes
   or acts on response content; no tools available while processing responses.
6. JUDGE — fixed LOCAL judge (session default model, never an arm under test), blind
   (shuffled, model-blinded), rubric-gated, rationale stored.
7. GATE — discriminativeness check: if scores don't separate arms on a demand, that demand's
   cells are marked non-informative (no contract records written for it) + dead probes
   flagged for regeneration.
8. WRITE — contract records per JOIN-SPEC shape (score, n, dispersion, battery version,
   measured_at, expires, verbosity factors). Freshness computed. Summary report to user.

## Refresh triggers
- Lineup change detected (model added/removed) → offer recalibration of affected cells.
- Records past expiry → routing already fails up (policy); skill offers refresh.

## Cost profile (estimate, to validate in implementation)
Per demand cell: probe gen (~1-2k) + n×(probe run) + judging. Text-only cells on the
scribe pattern (~2k floor) keep a full 6-demand × 3-model × n=3 battery in the low
hundreds of thousands of tokens; the dry-run estimate makes it explicit per run.

## Open implementation questions (for the PR)
- Recipe quality bar: recipes must reliably produce DISCRIMINATIVE probes — tight-loops
  validation (N=2 clean agents) per recipe before shipping.
- Custom-endpoint invocation: start with OpenAI-compatible + anthropic-compatible HTTP;
  anything else = user-provided command template (still data-not-instructions).
- Where the battery runner lives: skill instructions + a small bundled script (script
  preferred: enforces caps/blinding mechanically rather than by prose — execution-gap rule).
