# Adversarial design review — verdict: REDESIGN (2026-08-02)

A clean-context adversarial agent attacked `DESIGN-v1-REJECTED.md` before any run. Verdict:
**REDESIGN, not fix-then-run** — four independent FATALs, each breaking a different
load-bearing joint, plus 21 MAJOR/MINOR findings. Most damning meta-finding: *every*
identified bias in the cost measurement pointed toward APPROVE — the signature of a design
that would have produced a confident wrong answer.

## The four FATALs

1. **Wrong baseline `F`.** Production manual `/distill` harvests from the MAIN context where
   the conversation is already resident and cache-paid — its marginal cost is one harvest
   turn, not a fresh N-token transcript ingest. Measuring `F` as transcript ingest manufactures
   a ~90% "saving" the product never pays.
2. **`m` omitted the dominant term.** A mark written at request 5 of a 120-request session is
   re-carried as cache reads on every subsequent request. Our own token-economics research
   says ~85% of spend is context movement — v1's formula ignored exactly that channel.
3. **User-turn-only replay destroys the signal class under study.** Corrections/failures/
   surprises are responses to specific assistant behavior that a fresh agent won't reproduce;
   by turn 4 the replay is a non-sequitur. Fix: teacher-forced replay (original assistant
   turns fed verbatim; the replay agent's only action is emitting marks) — which also delivers
   true byte-parity between arms.
4. **Missing control arm.** The real shipping alternative is cheap-tier transcript
   pre-summarization at distill time (zero per-session tax). v1 could only conclude "marks
   beat full ingest" — not the decision anyone is making.

Full findings (25 numbered + verdict) preserved in the PR-of-record conversation and
summarized on issue #49.

## The reframe that survives the attack

FATAL 1 accepted — and it RELOCATES the feature's value: marks are nearly worthless for
manual `/distill` (warm context) and potentially decisive for the **auto-distiller (#51)**,
which must cold-read transcripts it never saw. The honest question is now:

> per-session marking tax `m` (with carry) vs `p ×` (cold-read cost the auto-distiller
> avoids), where `p` = fraction of sessions the auto-distiller processes.

## Analytic pre-check (finding #24) — coarse first pass, zero benchmark tokens

Using measured machine data (33 sessions / 3,360 requests ≈ 102 req/session; 12/33 manually
distilled → p_auto ≈ 0.64; price weights: cache-read 0.1×, output 5×):

- Marking instruction (shipping form ≤15 lines ≈ 150 tok) riding every request as cache-read:
  ~1.5k token-equivalents per session. Negligible.
- Marks: ~10/session × (150 output tok × 5 + 150 tok × ~50 remaining requests × 0.1)
  ≈ ~15k tok-eq. **m ≈ 17k tok-eq per session, paid always.**
- Avoided cost per auto-distilled session: NOT the full frontier ingest — the fair comparator
  (Arm C) is a cheap-tier cold read ≈ 300k tok × 0.1 price ratio ≈ ~30k mid-tier-equivalents.
- Expected value: `0.64 × 30k − 17k ≈ +2k` tok-eq per session. **Marginal, sign-unstable** —
  it flips negative with fewer marks-worthy sessions, shorter sessions, or cheaper cold reads
  (batch −50% would roughly halve the avoided cost → EV negative).

Conclusion of the coarse pass: the cost case for marks is NOT clearly positive even in its
best topology; it hinges on parameters (mark volume, session length distribution, batch
pricing, p_auto) that the real 40-day per-request dataset can pin down for free. The
durability benefit (signals survive sessions that never get distilled — attack finding #17)
is real but is a different claim needing a different test.

## Redesign sequence (pre-registered order)

1. **Analytic pre-check on the real per-request dataset** (research/2026-07-08-token-economics
   data): compute the EV formula with measured distributions. If the ceiling is below any
   plausible threshold → close #48 as discarded WITHOUT running the benchmark.
2. Only if the ceiling clears: DESIGN v2 — teacher-forced replay, marks-off control, `F` in
   the auto-distiller topology, carry-inclusive `m`, pre-summarization Arm C, price-weighted
   primary unit, expected-value criterion with measured `p`, pinned mark schema + instruction
   text (≤ always-on cap), judge rubric with fixed list size + intersection-of-two-passes,
   ≥3 replicates per cell, all-sessions (not median) gate.
3. DESIGN v2 goes through adversarial review again before ratification on #49.

**No benchmark tokens are spent before step 1 completes and Ivan ratifies a v2.**
