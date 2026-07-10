# Recipe D3 — code comprehension

Generate: a 100–180 line program in a language the user's stack actually uses, written
fresh for this battery (never copied from any repo), containing EXACTLY these planted
properties:
1. One non-obvious control-flow side effect (e.g. an exception handler that mutates state
   consumed later, a retry loop that masks a failure class, an early-return that skips
   cleanup on one path only).
2. One first-run/fresh-environment behavior that differs from steady-state.
3. One latent double-processing or ordering hazard with a one-line fix.

Probe = the code + 3 questions targeting exactly those three properties (≤3 sentences
each answer). Do NOT hint which lines matter.

Rubric (author WITH the probe): per question, the specific planted fact that must be
identified; partial credit only for naming the mechanism without the consequence.
Score /3. An answer that describes what the code does line-by-line without catching the
planted property scores 0 for that question.

Discriminativeness: the planted properties must require TRACING, not pattern-matching —
if a property is visible from one line's syntax, regenerate. Calibrate difficulty so a
strong model catches 3/3 and weak ones drop points on the side-effect question first.
