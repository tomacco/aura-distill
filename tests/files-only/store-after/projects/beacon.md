---
domain: projects
scope: Beacon notification service — push-provider fallback chain
last_updated: 2026-08-27
last_validated: 2026-08-27
staleness_threshold: 90
read_with: [ops/deploy.md]
---

## State

- Fallback chain: primary push provider → secondary → email digest. Shipped 2026-08-20.
- Current focus: per-provider circuit breaker thresholds.

## Decisions

- [DECISION] Circuit opens after 5 consecutive failures, half-opens after 60 s. origin: evidence (load test 2026-08-15).
- [PROVISIONAL] Email digest batches every 15 minutes. May move to 5 if support tickets mention delay.

## Index detail (moved from SPINE 2026-09-11)

Beacon notification service; current focus is the push-provider fallback chain. Read when working in the beacon repo.
