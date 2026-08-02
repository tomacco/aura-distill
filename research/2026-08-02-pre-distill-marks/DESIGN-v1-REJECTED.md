# Pre-distill marks benchmark — pre-registered experiment design

**Status: DESIGN.** No benchmark runs happen until BOTH gates pass:
1. Adversarial design review by a clean-context agent (verdict recorded below).
2. Ivan ratifies the decision threshold and token budget on issue #49.

This ordering is deliberate: the threshold is fixed BEFORE any data exists, so it cannot be
picked to flatter a result.

## Question

Does in-session pre-distill marking (#48 — writing `session-signal` items into the INBOX as
signals occur) reduce end-to-end distillation cost enough — without losing knowledge quality —
to justify taxing every session with marking overhead?

## Decision rule (pre-registered — values pending Ivan's ratification)

APPROVE #48 as an opt-in feature only if ALL hold; otherwise DISCARD (no weak middle path):

- **Net token saving:** `(F − M − m) / F ≥ 25%` on the median session, and `≥ 0%` on every
  tested session shape — where `F` = full-transcript distill cost, `M` = marks-mode distill
  cost, `m` = the marking tax paid during the session itself.
- **Quality non-inferiority:** the marks arm captures every must-capture signal the full arm
  captures, allowing at most ONE dropped must-capture signal across all sessions combined —
  and zero drops of signals the judge rates critical (corrections, [NON-NEGOTIABLE]-class
  preferences).
- **No new failure class:** the marks arm introduces no wrong encodings absent from the full arm.

Rationale for 25%: marking is paid on EVERY session; distillation savings materialize at most
once per session; sessions that never get distilled pay the tax for nothing. A thin margin
would be erased by that asymmetry. (Ivan may set a different value — the point is it is set now.)

## Arms & replay mechanics (single-replay, dual-arm)

Per session: replay the REAL session's user turns against a fresh agent that has the marking
instructions injected at session start and writes marks to a sandboxed inbox. This yields ONE
conversation artifact with marks. Then:

- **Arm A (marks):** distillation reads ONLY the inbox marks (no transcript access).
- **Arm B (full):** distillation reads ONLY the replayed transcript (marks stripped/hidden).

Same underlying conversation for both arms — arm parity by construction. The marking tax `m`
is computed from the replay's usage records: (a) marking-instruction tokens × number of
requests they rode on (cache-aware: 1h-TTL write once + cached reads after), plus (b) the
tokens of every mark-writing tool call and its result. This accounting is pre-registered here;
no post-hoc reallocation.

## Data: real sessions first

- **n = 3 real sessions from this machine**, one per shape: terse-ops, long build, discursive
  strategy. Selection criteria fixed BEFORE reading content: most recent completed session of
  each shape exceeding 40 user turns, excluding sessions about aura-distill itself
  (self-reference contamination).
- All processing stays local; transcripts never leave the machine; artifacts published to
  docs/research/ contain aggregate numbers only, never transcript content.
- **Synthetic sessions only if calibration passes:** a synthetic session may supplement n only
  after showing (on one real/synthetic pair) that its signal density and token profile fall
  within the real sessions' observed range. If calibration fails: real-only, smaller n,
  honest error bars.

## Judging (blind, pinned outside the arms)

- Judge model: pinned in the run config before execution; NEVER a model that produced either
  arm's output; sees no arm identity (outputs relabeled `K1`/`K2`, order randomized per session).
- **Ground truth first:** from the ORIGINAL transcript alone, the judge lists must-capture
  signals (corrections, taught facts, preferences, failures) with a criticality rating —
  before seeing any arm output.
- Then scores each arm's encoded knowledge for coverage of that list, correctness, and
  placement. Coverage judged semantically, not by string match.

## Measurements

Per session per arm: tokens in/out (distill), marking tax `m` (arm A only), max resident
context during distillation, must-capture coverage, wrong-encoding count, wall time.
$-figures reported only as API-equivalent counterfactual; tokens are the primary unit.

## Budget & execution guardrails (binding)

- **Hard cap: 3M tokens for the whole experiment** (replays + distills + judging), declared
  here, ratified with the threshold. The run script tracks cumulative usage and aborts over cap.
- Replay + extraction stages on the cheapest capable tier; judging on mid tier; frontier never.
  Limitation (stated up front): marks produced by a cheap-tier replay may not match
  frontier-session marking behavior; marking is extraction-shaped work, which the E1 routing
  data shows cheap models handle at parity — this is why the limitation is acceptable.
- Runs scheduled outside Ivan's working windows; fail-fast on account-limit strings; every
  aborted run is recorded, not silently retried.
- All file writes sandboxed (`mktemp -d` roots) — never a real profile, never `~/.aura-distill`.

## Contamination & integrity guards

- Verify what is ACTUALLY injected: dump each arm's effective prompt to the run artifacts
  before execution.
- The judge's ground-truth pass happens before arm outputs exist in its context.
- No invented precision: n=3 gives directional evidence; report ranges, not decimals.
- Contested cells stay contested: if judge and re-check disagree, report both.

## Deliverables

- `docs/research/pre-distill-marks.html` (house style) + raw run data on this branch
- Go/no-go verdict against the pre-registered rule, posted to #49
- If GO: the documented-consequences text for #48's opt-in knob (what the tax costs, what it saves)
- If NO-GO: #48 closed as discarded, INBOX (#47) remains the explicit-save channel

## Adversarial design review

_Pending — verdict and design changes will be recorded here before any run._
