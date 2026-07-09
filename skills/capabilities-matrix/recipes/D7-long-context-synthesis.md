# Recipe D7 — long-context synthesis

Generate: a document set (8–15 fresh synthetic documents, 20k–60k tokens total — size to
the smallest context window under test, minus headroom) about a coherent fictional
subject (an org, a system, an incident history). Plant:
1. 3 conclusion-critical facts in documents FAR APART, none restated elsewhere, at least
   one buried mid-document (never in an opening/closing paragraph).
2. 1 contradiction pair (two documents disagreeing on a fact) whose resolution requires a
   third document's date/version information.
3. Distractor content structurally similar to the critical facts.

Probe = the full set + 3 questions: one requiring joining the 3 distant facts, one
requiring the contradiction to be surfaced AND resolved (not just noticed), one answerable
only with "the documents don't establish this" (tests refusal-to-invent under context
pressure).

Rubric: joined-fact question — all 3 facts present in the answer (/1); contradiction —
surfaced (/0.5) and correctly resolved via the dating document (/0.5); unanswerable —
correctly declined (/1); any invented specifics anywhere = −1 (floor 0). Score /3.

Discriminativeness: position and burial depth are the knobs. If all arms join the facts,
move them deeper and farther apart; keep total size FIXED within a battery version so
cells are comparable.
