# Routing policy v1 (name-free, durable)

The rules an orchestrator follows when choosing where work runs. No model names, no scores —
those come from the LOCAL contracts file at decision time.

## The decision
For a task with declared demands **D** and risk **R**:
1. Candidates = models in the local contracts file whose records are `fresh` — the only
   admitting state; `stale` and `expired` records both trigger Fail UP — and cover every
   demand in **D** with margin (see below).
2. Choose the candidate with the lowest **expected per-task cost** = cost ratio (per
   JOIN-SPEC: prices normalized to the fixed reference unit, never raw vendor prices) ×
   the HIGHEST measured verbosity factor among the declared demands (conservative;
   "dominant demand" = the declared demand with the highest verbosity factor for that
   candidate) — never unit price alone.
3. Apply the risk modifier: if **R** is elevated (irreversible actions, externally visible
   output, hard-to-detect errors), step one position up the CAPABILITY ORDERING — the
   contracts file ranks models by measured demand-coverage breadth and margins (recorded
   at calibration time); "up" always walks toward the Fail-UP target, never toward
   cheaper. This ordering is distinct from spawn/tool tiers (step 4).
4. Pair with the spawn tier (tool set) independently: text-only jobs get text-only spawns
   regardless of model choice.

## Fail UP — the safety axiom
If capability data is missing, stale, expired, ambiguous, or the demands are unrecognized
(the same trigger list everywhere this rule is stated):
route to the MOST capable available model. Degraded routing may only ever cost money,
never quality. (Externally validated: independent router benchmarking found the
over-select-the-strongest failure mode is the safe one; we adopt it deliberately for
exactly the cases where we don't know better.)

## Margin, not threshold-kissing
Route down only when, for each demand, the contract's score clears the pass threshold by
at least k × its measured dispersion (default k=1; the battery version owns k and records
it in every contract record) — never on a bare pass. A contract that barely passed D4
once does not get D4 traffic.

## Consent & transparency (product invariants)
- Routing is OFF until the user opts in, ONCE, at the class level ("route mechanical
  subtasks to cheaper models"), with the class explicitly described.
- Within a consented class, routing is silent (no per-event interruptions); OUTSIDE any
  consented class, no routing happens at all.
- Every routed decision is logged with its rationale (demands, chosen contract, expected
  cost delta) and surfaced in a session-end summary. The rationale is the product.
- One command disables everything; the setting persists across updates.

## Sacred boundaries
- Never route work the user pinned to a model.
- Never route judgment about the user's own data/knowledge below the session's default model.
- Quality evidence beats cost math: any observed rubric violation in a class suspends
  routing for that class until re-validated (evidence is collected per the sampled-audit
  protocol in METHODOLOGY.md — acceptance rates are not evidence).
