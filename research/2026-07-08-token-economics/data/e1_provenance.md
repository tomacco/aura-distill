E1 provenance notes:
- Judged packets snapshot outputs at collection time (e1-judge dir); a validity-check quirk
  (result-length threshold) caused some short-but-valid cells to re-run afterwards; the judged
  record + usage.json snapshot are authoritative.
- T6 prompt amended post-first-attempt (no-tools instruction, identical across all arms)
  because tool-use attempts hit the 1-turn cap; no first-attempt outputs were read before
  discarding (no selection bias).
- T4 rubric point "ancestor transform breaks position:sticky" was flagged by the blind judge
  as conflicting with the unscored reference output; the point traces to craft/css-layout.md
  in the author's own knowledge base (possible encoded overgeneralization — filed as a distill
  signal). Both scorings reported; no routing-tier verdict drawn from T4.
