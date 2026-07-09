# Routing policy v1 (name-free, durable)

The rules an orchestrator follows when choosing where work runs. No model names, no scores —
those come from the LOCAL contracts file at decision time.

## The decision
For a task with declared demands **D** and risk **R**:
1. Candidates = models in the local contracts file whose records are FRESH (not expired)
   and cover every demand in **D** with margin (see below).
2. Choose the candidate with the lowest **expected per-task cost** = price × measured
   verbosity factor for the dominant demand — never unit price alone.
3. Apply the risk modifier: if **R** is elevated (irreversible actions, externally visible
   output, hard-to-detect errors), route one tier up from the cost-optimal choice.
4. Pair with the spawn tier (tool set) independently: text-only jobs get text-only spawns
   regardless of model choice.

## Fail UP — the safety axiom
If capability data is missing, expired, ambiguous, or the demands are unrecognized:
route to the MOST capable available model. Degraded routing may only ever cost money,
never quality. (Externally validated: independent router benchmarking found the
over-select-the-strongest failure mode is the safe one; we adopt it deliberately for
exactly the cases where we don't know better.)

## Margin, not threshold-kissing
Route down only when the cheaper contract covers each demand with headroom derived from
the measurement's own dispersion (per METHODOLOGY.md) — never on a bare pass. A contract
that barely passed D4 once does not get D4 traffic.

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
