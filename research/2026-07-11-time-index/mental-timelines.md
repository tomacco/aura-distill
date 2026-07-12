# Mental timelines: how humans reference past time — research behind the Time Index

*2026-07-11 · informs `bin/distill-recent` bucket boundaries, the `TIMELINE.md` landmark
layer, and the fuzzy-phrase table in `rules/distill.md`.*

**Design question:** a time-based retrieval index must answer queries the way people ask
them — "a few weeks ago", "when we did the launch" — never "44 days ago", because nobody
says that. What bucketing scheme matches human temporal memory?

## Findings

### 1. Telescoping — dating errors are directional, not symmetric
People misplace events in time systematically: remote events get pulled toward the present
(**forward telescoping**), very recent ones pushed away (backward). Huttenlocher, Hedges &
Bradburn (1990, *Psych. Review*) explain it mechanistically: reports round to prototype
values (7, 14, 21, 30, 60, 90 days) whose gaps widen with distance, so more values round
*down* — net forward bias. Rubin & Baddeley (1989, *Memory & Cognition*): absolute dating
error grows proportionally with retention interval (a Weber-like law); dating is materially
unreliable beyond a few weeks, increasingly past ~2–3 months.
→ **Design:** a "2 months ago" query must also search ~40% farther back; ranges shift
toward the deeper past, they don't just widen.

### 2. Logarithmic compression (Weber–Fechner)
Subjective temporal distance is log-compressed; hippocampal time cells tile elapsed time
logarithmically with broader fields for older intervals (Howard 2018, *TiCS*; Cao et al.
2022, *eLife*). Usable precision coarsens with distance: day → week → month → season.
→ **Design:** bucket width grows geometrically with age.

### 3. Autobiographical memory is hierarchical (Conway)
Conway & Pleydell-Pearce (2000, *Psych. Review*): lifetime periods → general events →
event-specific knowledge. Retrieval descends via period/event cues; dates are
*reconstructed afterwards*, which is why they're wrong.
→ **Design:** `TIMELINE.md` consolidation mirrors this — events compress into periods as
they age, and old memories are reachable by period/landmark, not date math.

### 4. Temporal landmarks dominate
People date events relative to salient landmarks (Shum 1998, *Psych. Bulletin*); "before/
during COVID" functions as a period boundary as strong as lifetime chapters (Koppel & Rubin
2024, *Memory*). Calendar interviewing exploits this to measurably improve dating accuracy.
→ **Design:** landmark names are first-class retrieval keys, resolved BEFORE numeric
buckets, and never dropped during consolidation.

### 5. Calendar scaffolding — the week is cyclic, not smooth
Day-of-week memory follows a "5+2" weekday/weekend cycle and is reliably recoverable only
~2–3 weeks back (Huttenlocher, Hedges & Prohaska 1992); beyond that people round to weeks,
then months. Calendar structure locally *overrides* log compression — "last Tuesday" can
be more precise than "3 weeks ago" at similar distance.
→ **Design:** THIS WEEK / LAST WEEK are calendar-anchored (ISO weeks), not sliding-day
windows; the rules treat weekday references older than ~2 weeks as weak hints.

### 6. Vague quantifiers have fuzzy, overlapping ranges
TimeML/TIMEX3 marks vague expressions with modifiers rather than exact values; vague-
quantifier studies give approximate mappings: "a couple of" ≈ 2 units, "a few" ≈ 3–4
(fuzzy 2–6), "several" ≈ 3–7 — speaker- and context-variable. (Numeric ranges partly
extrapolated to the temporal domain — treat as tunable, not ground truth.)
→ **Design:** the phrase table in `rules/distill.md` maps phrases to overlapping ranges,
never hard edges. The shipped table folds "some weeks ago" into "a few weeks ago" and
widens the range to 2–8 wk (literature baseline is ~2–6).

## The bucket scheme this produces

| Bucket | Range | Precision regime |
|---|---|---|
| TODAY / YESTERDAY | 0–1 d | day |
| EARLIER THIS WEEK / LAST WEEK | ISO weeks 0–1 | day-of-week reliable |
| A FEW WEEKS AGO | ISO weeks 2–3 | week; weekday decays |
| ABOUT A MONTH AGO | ISO weeks 4–7 | week→month transition |
| A COUPLE OF MONTHS AGO | ~50–104 d | month; telescoping zone |
| A FEW MONTHS AGO | 105–182 d | month/season |
| Calendar months | 183 d+ | period/landmark only |

Boundaries sit on the empirical precision transitions and on Huttenlocher's prototype
values (7/14/30/60/90). Display buckets are disjoint; *query* interpretation is fuzzy and
overlapping (rules layer). Beyond ~6 months the raw view only labels calendar months —
retrieval there belongs to `TIMELINE.md` landmarks (finding 3, 4). `history.jsonl`
rotation (~5–6 weeks observed) makes the same split load-bearing: raw view = recent tail,
timeline = the rest.

## Honest caveats
- The "a few = 2–6 weeks" style numeric ranges are extrapolated from general vague-
  quantifier work, not measured for temporal phrases specifically. They're encoded as
  guidance for the agent. Note: installer updates REPLACE the routing block in
  `rules/distill.md`, so hand-edits there are reverted — durable personal overrides
  belong in the Always-On preferences section, which the installer preserves.
- Weekly cyclicity, landmark discontinuities, and prototype heaping all *violate* smooth
  log-bucketing — the scheme special-cases them (calendar-anchored weeks, landmark-first
  routing) rather than pretending one curve fits.

## Sources
Huttenlocher, Hedges & Bradburn 1990 (*Psych. Review*, PMID 2137861) · Rubin & Baddeley
1989 (*Memory & Cognition*) · Howard 2018, "Memory as Perception of the Past" (*Trends in
Cognitive Sciences*) · Cao et al. 2022 (*eLife*, PMC9651951) · Conway & Pleydell-Pearce
2000 (*Psych. Review*) · Shum 1998 (*Psych. Bulletin*) · Koppel & Rubin 2024 (*Memory*,
PMID 38300754) · Huttenlocher, Hedges & Prohaska 1992, "Memory for day of the week"
(PMID 1402704) · van der Vaart & Glasner 2011 (*Field Methods*) · Pustejovsky et al. 2003,
TimeML/TIMEX3 · "Normalisation of imprecise temporal expressions" 2019 (*KAIS*).
