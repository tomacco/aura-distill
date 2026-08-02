# Pre-distill marks — analytic pre-check (zero benchmark tokens)

Date: 2026-08-02. Question: would opt-in "pre-distill marks" (every session writes ~120-token signal marks to an inbox; a background auto-distiller processes marks instead of cold-reading transcripts) plausibly save tokens, or is it dominated by its own overhead? This arithmetic decides whether a redesigned benchmark is worth running.

All figures are in **mid-tier-input-token-equivalents per session** (mid-tier input = 1.0; cache read 0.1; 1h cache write 2.0; output 5.0; batch 0.5x; cheap-tier input 1/3).

## 1. Data actually used

**Raw per-session data (used for everything below):**
- `C:\Users\Ivan\repos\aura-distill-token-econ\research\2026-07-08-token-economics\data\aggregates.json` — 33 sessions (2026-05-29 to 2026-07-08), each with per-model fresh input (`inp`), 1h cache writes (`c1`), cache reads (`cr`), output (`out`), `n_requests`, and `distill_invoked`.
- `...\data\distill_events.json` — 12 manual distill invocations, context-per-request distribution (n=3,364: median 153,442; mean 193,914; p90 388,804).
- `...\data\e5_decomposition.json` — cost decomposition (cache read 50.8–56.8%, 1h write 22.1–33.9%, output 14.9–20.6%, fresh input 0.4%); total $867.52 API-equivalent.

Checked but not needed: `usage.json` (E1 per-model task runs), `e3_scored.json`, `friction_events.json`, `recovery.json`; `C:\Users\Ivan\repos\aura-distill-overnight\` (no additional usage data).

**Correction to a published aggregate:** "12 of 33 sessions manually distilled" is actually **12 invocations across 7 unique sessions** (`distill_invoked` true for 7). Measured p_auto = 26/33 = 0.79, not 21/33 = 0.64. The table keeps the prescribed 21/33 row and adds the measured-indicator variant.

**Measured request distribution (n=33):** total R = 3,360; mean 101.8; **median 30**; p90 240. Heavily right-skewed — the model is evaluated per session, not on the mean.

**Transcript size S (the cold-read volume) is NOT directly measured.** Two data-driven bounds per session:
- `S_low = inp + out` (user text + assistant text; misses tool results, which dominate transcripts) — mean 142k, median 40k
- `S_high = inp + c1` (every token that entered context, inflated by 1h-cache-expiry rewrites in multi-day sessions) — mean 509k, median 137k
- Headline `S_mid` = geometric mean — **mean 255k, median 66k, p90 578k**

## 2. Model

- Marking tax per session: `m = 15R + k(600 + 6R)` (I=150 instruction tokens carried at cache-read weight over R requests; k marks of T=120 tokens at output weight 5.0 plus cache carry over mean R/2 remaining requests).
- Avoided cost: `C_avoided = S × 1/3` (cheap-tier cold read), halved with batch. Marks-mode residual (auto-distiller reading k×120 marks at cheap input) ≤ 800 units at k=20 — negligible, not subtracted.
- `EV = p_auto × C_avoided − m`, computed per session then averaged (so the R–S correlation is preserved).

## 3. EV table (S_mid headline; EV_mean brackets = [S_low, S_high] bounds)

| k | batch | p_auto | m (mean) | C_avoided (mean, p-weighted) | EV mean | EV median session | sessions EV<0 |
|---|-------|--------|---------:|------------------------------:|--------:|------------------:|--------------:|
| 3 | off | 21/33 | 5,160 | 54,138 | **+48,978** [+25,050, +102,803] | +11,250 | 1/33 |
| 3 | off | 1.00 | 5,160 | 85,074 | +79,914 [+42,312, +164,496] | +19,190 | 1/33 |
| 3 | off | 0.36 | 5,160 | 30,627 | +25,467 [+11,930, +55,916] | +5,224 | 7/33 |
| 3 | on | 21/33 | 5,160 | 27,069 | +21,909 [+9,945, +48,822] | +4,313 | 9/33 |
| 3 | on | 1.00 | 5,160 | 42,537 | +37,377 [+18,576, +79,668] | +8,277 | 2/33 |
| 3 | on | 0.36 | 5,160 | 15,313 | +10,153 [+3,385, +25,378] | +1,479 | 11/33 |
| 10 | off | 21/33 | 13,636 | 54,138 | +40,502 [+16,573, +94,327] | +6,000 | 11/33 |
| 10 | off | 1.00 | 13,636 | 85,074 | +71,438 [+33,836, +156,020] | +13,929 | 9/33 |
| 10 | off | 0.36 | 13,636 | 30,627 | +16,990 [+3,454, +47,440] | +513 | 16/33 |
| 10 | on | 21/33 | 13,636 | 27,069 | +13,433 [+1,469, +40,345] | −287 | 17/33 |
| 10 | on | 1.00 | 13,636 | 42,537 | +28,901 [+10,100, +71,192] | +3,191 | 11/33 |
| 10 | on | 0.36 | 13,636 | 15,313 | +1,677 [−5,091, +16,902] | −3,943 | 21/33 |
| 20 | off | 21/33 | 25,745 | 54,138 | +28,393 [+4,464, +82,218] | −500 | 17/33 |
| 20 | off | 1.00 | 25,745 | 85,074 | +59,329 [+21,727, +143,911] | +6,458 | 11/33 |
| 20 | off | 0.36 | 25,745 | 30,627 | +4,881 [−8,655, +35,331] | −7,526 | 21/33 |
| 20 | on | 21/33 | 25,745 | 27,069 | +1,324 [−10,641, +28,236] | −8,417 | 23/33 |
| 20 | on | 1.00 | 25,745 | 42,537 | +16,792 [−2,009, +59,083] | −3,278 | 18/33 |
| 20 | on | 0.36 | 25,745 | 15,313 | −10,432 [−17,200, +4,793] | −11,690 | 32/33 |

**Measured-indicator variant** (the 7 actually-distilled sessions contribute C_avoided = 0, S_mid):

| k | batch | EV mean | EV median | EV<0 |
|---|-------|--------:|----------:|-----:|
| 3 | off | +29,749 | +5,467 | 8/33 |
| 3 | on | +12,294 | +1,487 | 9/33 |
| 10 | off | +21,273 | +385 | 16/33 |
| 10 | on | +3,818 | −3,393 | 18/33 |
| 20 | off | +9,163 | −6,711 | 18/33 |
| 20 | on | −8,291 | −9,693 | 25/33 |

## 4. Distributional caveat

Median session: R = 30, S_mid ≈ 66k, so m(k=3) ≈ 2,790 vs batch-cheap cold read ≈ 11k — the median clears at small k but by only a few thousand units. The mean EV is 3–9x the median EV in every row because **the top 5 sessions carry 60% of total S_mid** — and those are exactly the sessions the user already distills manually (the 7 manually distilled sessions hold 59% of total S_mid). Under the measured indicator, marks in the biggest sessions are pure tax. Fraction of sessions with negative EV: 8–9/33 in the best rows (k=3), 16–25/33 at k=10–20 with batch on. Short sessions are always a loss, but a small one (m ≈ 2.8k at k=3, R=30).

## 5. Verdict

At low mark volume (k=3) EV is positive in essentially every scenario — the feature is **not dominated by its own overhead** — but the prize is capped by how cheap the alternative already is: the number that drives everything is **C_avoided ≈ S × 1/6 ≈ 27k–43k mid-tier-equivalent tokens/session** (cheap-tier batch cold read of a median-66k / mean-255k transcript). Against a measured corpus burn of ~3.58M mid-tier-equivalents per session (118M total over 33 sessions), the best defensible row (k=3, batch on, measured p_auto: +12,294) saves **~0.34% of session cost**, and even the most favorable row (+79,914) saves ~2.2%. Batch belongs ON in the fair baseline (a background distiller is latency-insensitive), which halves the ceiling; k must stay ≤~5, or the median session goes negative. Conclusion: a redesigned *token* benchmark is **not worth running** — no scenario clears a meaningful cost ceiling, and the decision to build marks should rest on distill *quality* (do marks find signals a cheap cold read misses?), which is a different benchmark than the one that was rejected.

## 6. Assumptions a real benchmark would need to validate

1. **S** — actual transcript token count per session (the dominant uncertainty: S_low and S_high differ 3.6x; the EV bounds span ~4x). Directly measurable from `.jsonl` transcript files.
2. **Marks fully substitute for the cold read** (assumed 100% here). If the auto-distiller still needs transcript excerpts around each mark, C_avoided shrinks toward zero and EV goes negative almost everywhere.
3. **Cheap-tier distill quality** — that a Haiku-class cold read + summarization produces acceptable distillate at all (if not, the counterfactual changes and marks compete against mid-tier cold reads, tripling C_avoided).
4. **I = 150** instruction tokens is achievable as always-on prompt (and that it rides the cache at 0.1 weight rather than forcing cache re-writes at 2.0 — a cache-invalidation interaction would multiply the carry cost ~20x and flip every row negative).
5. **T = 120 and k ≤ 5 in practice** — mark discipline; k = 20-style chatty marking is negative-EV in most scenarios.
6. **Marking does not degrade the main session** (attention/behavior side effects; zero-cost assumption here).
7. **p_auto** — whether the auto-distiller actually targets the 26 undistilled sessions, given they hold only ~41% of transcript volume; and whether uniform-mark-timing (mean carry R/2) matches reality (late-session marks are cheaper, early marks costlier).
