# Model routing rules (learned; E1 run 2026-07-09 + task-taxonomy literature)

Route subagent work by TASK SHAPE, not by how important the session feels:

- Mechanical transforms / format conversion with unambiguous rules → claude-haiku-4-5.
  (E1: zero rubric violations; identical output values to the frontier arms.)
- Structured extraction from noisy text/logs → claude-haiku-4-5.
  (E1: 6/6 exact; note even the expensive arm fumbled one count — verify counts by rule, not by tier.)
- Bulk repo sweeps (grep/TODO inventory, file listings, symbol search) → claude-haiku-4-5.
  (Literature: near-zero quality gap on search/inventory work.)
- Code comprehension of unfamiliar code → claude-sonnet-5 floor.
  (E1: haiku earned partial credit only — misses subtle control-flow side effects.)
- Debugging with multiple interacting causes → frontier (claude-opus-4-8+).
  (E1 cell contested; literature consistently keeps sustained-constraint diagnosis on frontier.)
- Adversarial/methodology review, experiment design judgment → frontier (claude-opus-4-8+).
  (E1: the cheap arm found surface flaws but missed the inference-only ones.)
- Verbosity warning: cheap models can emit 3-7x more output tokens for the same task —
  unit price is not the whole cost; check output discipline.
