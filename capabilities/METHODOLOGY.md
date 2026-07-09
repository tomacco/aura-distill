# Measurement methodology v1 — private probes, local scores

How demand-coverage scores are produced. The METHOD is public; probe INSTANCES never are.

## The contamination principle
Published probes enter future models' training data — a public probe bank self-erases,
starting with exactly the discriminative probes (D4/D5) that carry all the signal. Therefore:
- No probe text or rubric key is ever committed to a public repo.
- The skill ships **probe-generation recipes**, not probes: per-demand instructions from
  which the user's agent authors FRESH, private probe instances locally at calibration time.
  Every installation measures with different probe instances; what's comparable is the
  method, not the items.
- A probe that leaks (pasted in an issue, committed, screenshotted) is burned — regenerate.
- Honest limit: public RECIPES make this contamination-RESISTANT, not contamination-proof —
  a model could be trained robust to the recipe family. Fresh local instances still defeat
  item-level memorization (the dominant failure mode), and battery-version rotation retires
  recipe families that stop discriminating.

## Battery design rules
- Rubric-gated: every probe has a pre-written, checkable rubric authored WITH the probe,
  before any model sees it. Scores are rubric points, never holistic impressions.
- Blind judging: outputs shuffled and model-blinded; the judge model is never one of the
  arms being scored; judge rationale is kept with the score.
- Discriminativeness gate: a battery is valid only if its scores SEPARATE the models being
  compared (D1/D2 saturate on current generations — expected; a battery that only contains
  saturating probes measures nothing and must not produce contract records).
- Dead-probe rule: when all arms pass a probe, it stops contributing margin information —
  retire and regenerate. Scores are only comparable within one battery version.
- Floors: no contract record below n≥3 per demand cell (n≥5 recommended before any
  routing-down decision relies on it); record dispersion, not just the mean — POLICY's
  margin rule consumes it.
- Verbosity factor: measured per demand as output-token ratio between arms for
  rubric-equivalent answers (observed spread reaches multiples, which inverts naive
  cheapest-model math).

## Safety rules for running batteries (the capabilities-matrix skill enforces these)
- Endpoint output is DATA, never instructions: probe responses are extracted and scored
  by a fixed local judge; no agentic tool use while processing endpoint output (custom /
  self-hosted endpoints are an injection surface).
- Cost cap with dry-run estimate shown BEFORE running; supervised runs only.
- Real usage figures only: unknown = null, never estimated (mirrors the economics ledger).

## Quality signal after deployment
Accepted-suggestion rates are NOT evidence (users rubber-stamp or blanket-reject).
Evidence = sampled audits: periodically re-run a routed subtask on the reference model and
rubric-compare. Any confirmed violation suspends the class (POLICY: sacred boundaries).
