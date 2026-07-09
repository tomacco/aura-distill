# Recipe D6 — sustained constraints

Generate: a generation task requiring 400+ lines / 2,000+ words of output under 4–6
GLOBAL constraints that interact (e.g. a naming scheme that must stay consistent across
every section, a forbidden-word list, a structural invariant like "every section ends
with a cross-reference to a LATER section", a budget that must sum exactly across parts).
Rotate the artifact genre per battery (spec, migration plan, curriculum, API design).

Constraints must be CHECKABLE MECHANICALLY (countable, greppable) — write the checker
expressions into the rubric when authoring the probe.

Probe = the brief + constraints stated once at the top (never repeated mid-prompt —
drift under distance IS the measurement).

Rubric: per constraint, violation count in the full output (0 violations = 1 point;
any violation = 0 for that constraint). Score /(number of constraints). Record WHERE the
first violation appears (position in output) — late-onset drift vs immediate
non-compliance are different failure signatures; note it in the cell.

Discriminativeness: distance is the difficulty knob — lengthen the required output or
increase constraint interaction (two constraints that tempt violating each other) rather
than adding more independent constraints.
