# Model routing productization roadmap (Ivan directives 2026-07-09)

Status: DRAFT pending steelman (external-evidence adversarial review running).
Governing principles (all [DIRECTIVE]): fully transparent, explicit user approval at every
step, no model names in policy (capability-contract design), nothing ships that rots in
2 months, release frame applies (free-win vs opt-in knob).

## The four stages

### Stage 1 — Capabilities matrix (baseline/cache in the aura-distill GitHub repo)
A versioned, machine-readable capability matrix, published in the repo, acting as distill's
BASELINE + CACHE for routing decisions.
- `capabilities/matrix.json`: per-model records — demand-coverage scores (7-demand taxonomy),
  cost ratios (vs cheapest tier, input/output separate), verbosity factor, context window,
  tool floors; every record carries provenance (battery version, n, date) + `expires` +
  `confidence` (measured | derived | imported).
- `capabilities/README.md`: schema, refresh protocol, honesty rules (no invented numbers;
  n=1 stays labeled n=1; expired data is served with an EXPIRED flag, consumers must fail UP).
- Baseline v0 content: E1 rubric results + spawn floors + verified pricing ratios (thin-n,
  disclosed) + imported public data WHERE license-compatible (see steelman: reuse before
  rebuild — imported entries carry `source` + `imported` confidence).
- Role: distill installations read this as default; it is a CACHE (local overrides win).

### Stage 2 — Opt-in BETA of model routing (next version)
- Installer/update asks EXPLICITLY: "Beta-test model routing? Distill will suggest cheaper
  models for delegated subtasks based on the public capabilities matrix. Fully local; you
  see every suggestion; fail-up default; one command to turn off." Default = OFF.
- Marker `distill/.routing` (enabled-beta | disabled), same persistence pattern as
  `.token-saver` (validated).
- Beta behavior = SUGGEST, not silently route: the orchestrator states "routing this to a
  cheaper tier because <demands>; override?" — trust is built by showing reasoning.
- Landing-page section documents exactly what the beta does + what it never does.

### Stage 3 — Community data contributions (version after)
- In areas where the matrix is thin (pre-identified: per-demand n, non-Anthropic models,
  verbosity factors), distill ASKS the user — explicit approval per event, never automatic:
  "This routing decision had thin data (n=1 on demand D4). Want me to open a pre-filled
  GitHub issue with the anonymized measurement so the community matrix improves?"
- Pre-filled issue template = Tier-1 pattern from the telemetry framework (#31): the USER
  reads the payload before sending; measurements only (scores/tokens), never content.
- Issue labels per demand dimension → maintainers fold verified contributions into the
  matrix with `source: community`, n aggregated.

### Stage 4 — Local/private matrix skill
- A distill skill: "capabilities-matrix" — guides the user's agent through running the
  calibration battery against ANY model lineup (incl. custom/fine-tuned/self-hosted models),
  writing a PRIVATE local matrix `{DISTILL_DIR}/data/capabilities-local.json`.
- Merge semantics: local matrix OVERRIDES repo baseline per model+demand; local entries
  never leave the machine; the skill never suggests publishing (publishing is Stage 3's
  explicit-ask flow, and only for models that exist publicly).
- This is what makes the design durable for enterprises/custom setups — the public matrix
  is a baseline, not an authority.

## Sequencing gates (each stage gated on the previous)
1→2: matrix v0 published + battery V1 discriminativeness gate passed (probes separate tiers).
2→3: beta cohort exists + suggestion accuracy observed (accepted-suggestion rate as signal).
3→4: battery scripts stable enough to run unsupervised on arbitrary endpoints.

## Open items feeding from steelman
- Which public sources are license-compatible for import (reuse-before-rebuild)?
- Does public benchmark data PREDICT agentic-subtask routing outcomes (or is our
  agentic-probe battery the actual moat)?
- Positioning vs commercial routers: our differentiators to validate, not assert —
  (a) transparency (open data + visible reasoning vs black-box), (b) task-demand shape
  (agentic delegation subtasks vs chat queries), (c) memory-learned local adaptation
  (the whitespace), (d) fail-up safety as policy.
