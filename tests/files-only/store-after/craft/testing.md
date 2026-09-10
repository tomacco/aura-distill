---
domain: craft
scope: Testing philosophy for Noor's services — contract tests, failing-test-first, flakiness discipline
last_updated: 2026-08-30
last_validated: 2026-08-30
staleness_threshold: 120
evidence: evidence/craft/testing.md
---

## Principles

- [PRINCIPLE] Contract tests over mocks for every external client.
  confidence: hardened (9 confirmations, 0 corrections)
  last_validated: 2026-08-30
  Why: a mock encodes what we believe the dependency does; a contract test encodes what it actually does. The 2026-06 payment-client incident (schema change hidden for three weeks) is the canonical case.

- [PRINCIPLE] Every bug fix ships with a test that FAILS without the fix. Verify the failure before committing the fix.
  confidence: validated (5 confirmations, 0 corrections)
  last_validated: 2026-08-12
  Why: a test written after the fix that passes either way is theatre.

- [PRINCIPLE] "Flaky" is a hypothesis, not a verdict. Reproduce, then name the cause (timing, shared state, order dependence, external service).
  confidence: validated (4 confirmations, 1 correction)
  last_validated: 2026-07-30

- [PRINCIPLE] No sleep-based waits. Poll on the condition with a bounded timeout, or use the framework's clock.
  confidence: validated (3 confirmations, 0 corrections)
  last_validated: 2026-07-02

- [NON-NEGOTIABLE] Test personas are generic (Sofia, Marcus, Noor-test). Never use a real colleague's name or data in a fixture.
  confidence: hardened
  last_validated: 2026-08-30
  origin: directive (Noor, 2026-04-18)

- [PRINCIPLE] CI runs the shipped script, never a copy of it. Extract the script under test so the test executes the same bytes users get.
  confidence: provisional (2 confirmations, 0 corrections)
  last_validated: 2026-08-12

Evidence: 2026-04-18 to 2026-08-30 in `evidence/craft/testing.md` (32 entries).
