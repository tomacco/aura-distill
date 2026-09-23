---
domain: projects
scope: Delta webhook relay — retries and dead-letter handling
last_updated: 2026-08-14
last_validated: 2026-08-14
staleness_threshold: 90
---

## State

- Relay in production since 2026-08-01; dead-letter queue drained weekly.

## Decisions

- [DECISION] Exponential backoff capped at 10 minutes, then dead-letter. origin: evidence (load test 2026-07-28).

## Index detail (moved from SPINE 2026-09-11)

Delta webhook relay; retries and dead-letter handling. Read when working in the delta repo.
