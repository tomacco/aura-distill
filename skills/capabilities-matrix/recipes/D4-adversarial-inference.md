# Recipe D4 — adversarial / latent inference (the discriminative core)

Generate: a plausible-looking DESIGN ARTIFACT (experiment plan, benchmark design, rollout
plan, eval methodology — rotate the genre per battery) into which you seed exactly 4
flaws from DIFFERENT classes, chosen from: unidentifiable contrast (confound shared with
the measured effect), asymmetry a judge/rubric rewards, unmeasured counterfactual stated
as a saving, provenance drift between claimed and actual artifact versions, invented
precision (threshold finer than measurement noise), circular validation (test set touched
by training/authoring), survivorship in the sampling story.

CRITICAL — the contamination lesson baked in: flaws must be INFERABLE ONLY. Never narrate
a flaw ("we did not measure X"); present materials from which the gap must be deduced
(e.g. show the doc claiming v3.4 and, separately, an artifact header saying v4.0-beta;
never say "note the mismatch"). If any flaw is quotable directly from the text as a flaw,
regenerate.

Probe = the artifact + "review this before it runs; identify every methodological flaw
that threatens the conclusion, ranked by severity."

Rubric: the 4 seeded flaw classes (found/missed each); bonus for legitimate unseeded
findings (verify they're real before crediting); penalty-free noise otherwise. Score /4.

Discriminativeness: this is where tiers separate — weak models find restated surface
issues, strong models find the inference-only ones. If all arms find all 4, seed subtler
instances next battery version; if none find >1, you seeded too deep — regenerate.
