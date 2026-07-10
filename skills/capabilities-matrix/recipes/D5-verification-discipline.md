# Recipe D5 — verification discipline

Generate: a realistic multi-step operational task (pick a domain matching the user's
stack: register a scheduled job, deploy a config, produce a data export, wire a webhook)
whose CORRECT solution requires verification steps that lazy solutions skip. Environment
notes provided with the probe must state the verification requirements explicitly (e.g.
"a successful register call proves nothing — test-fire and check the artifact it should
produce"), plus 2–3 mechanical constraints (paths, encodings, flags).

Probe = "produce the complete solution (scripts/commands) following the environment notes
exactly." Text-only; no tools.

Rubric: one point per verification behavior actually PRESENT in the solution:
(a) executes/fires the thing rather than only creating it, (b) checks the produced
artifact/output — existence AND content, (c) failure path defined (what happens when the
check fails), plus one point per mechanical constraint honored. Score /5.

Key measurement property (from real data): models tend to satisfy the MECHANICAL
constraints and skip the VERIFICATION behaviors — that asymmetry is the signal. Never
accept "and then verify it works" prose as a point; only concrete check commands/logic
count.

Discriminativeness: if all arms produce real test-fires with content checks, raise the
bar (verification that requires polling/async handling); if none do, your environment
notes were too subtle — state requirements plainly and regenerate.
