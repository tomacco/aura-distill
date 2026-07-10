# Recipe validation record

## D4 (the discriminative core) — tight-loops N=2, 2026-07-10
Two clean-context text-only agents each generated a full probe+rubric from the recipe
(genres: DB-migration rollout plan; pricing A/B test plan). Both PASS the recipe's own
bar: exactly 4 seeded flaws from distinct classes, every flaw INFERABLE-ONLY (requires
cross-section/appendix inference; nothing quotable as a flaw), rubrics state hiding
places and FOUND criteria. Cost: ~4.3k tokens per generation (scribe-tier spawn).
Probe texts are NOT committed (private-probes principle) — they lived and died in agent
transcripts; the record here is the validation outcome only.

## D3, D5-D8 — validated at first real battery run
Per the dead-probe/discriminativeness gates in METHODOLOGY.md, remaining recipes get
their N=2 validation as part of the first supervised battery execution (each generated
probe is checked against its recipe's discriminativeness section before use).
