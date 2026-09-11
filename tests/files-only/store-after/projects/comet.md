---
domain: projects
scope: Comet billing reconciliation — on hold, retention rules
last_updated: 2026-05-06
last_validated: 2026-05-06
staleness_threshold: 90
lifecycle: pinned
---

## State

- On hold since 2026-05-06 pending the finance team's tooling decision.

## Rules that outlive the project

- [NON-NEGOTIABLE] Invoice records are retained 10 years. Never delete, only tombstone. origin: constraint (legal, 2026-01).
- [NON-NEGOTIABLE 2026-01-15] Reconciliation runs are idempotent; a re-run must produce byte-identical output for the same input.
