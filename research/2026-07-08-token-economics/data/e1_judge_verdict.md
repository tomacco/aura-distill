# E1 blind-judge verdict (judge=claude-fable-5, labels decoded post-hoc)

Decoded per mapping.json. Scored arms: haiku-4-5 / sonnet-5 / opus-4-8. n=1 per cell — single-trial observations, not capability claims.

| Task | haiku-4-5 | sonnet-5 | opus-4-8 | verdict (rubric-gate) |
|---|---|---|---|---|
| T1 transform | 6/6 | 6/6 | 6/6 | ROUTABLE to haiku (this trial: identical values across arms) |
| T2 extraction | 6/6 | 6/6 | 5/6 (Q1 wrong) | ROUTABLE to haiku; even opus fumbled once |
| T3 comprehension | 2.5/3 | 2.5/3 | 3/3 | sonnet floor; haiku partial |
| T4 debugging | 4/4* | 4/4* | 1.5/4* | CONTESTED CELL — rubric point (transform breaks sticky) conflicts with reference output; inverted scoring flips ranks; no tier verdict |
| T5 design judgment | ~3.25/4 | 4/4 | 4/4+bonus | frontier for adversarial review; haiku missed inference-only flaws; sonnet matched opus on points |
| T6 instruction application | (judged separately after rerun) | | | |

Notes: cheap arms can be far more verbose (T2: haiku 453 output tokens vs opus 63 for the same 6 answers). T4 rubric flaw traces to the author's own knowledge file — filed as a distill signal (encoded overgeneralization).
