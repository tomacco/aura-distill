---
domain: ops
scope: Deploy procedure for Noor's services — canary, staging, prod, rollback, paging
last_updated: 2026-07-20
last_validated: 2026-08-25
staleness_threshold: 180
---

## Procedure

1. Deploy to canary (one pod). Soak 5 minutes. Watch error rate and p95 latency.
2. Promote to staging. Soak 30 minutes. Run the smoke suite: `make smoke ENV=staging`.
3. Promote to prod. Announce in the deploys channel with the change list.

## Rollback

- `deployctl rollback <service> --to previous` — takes about 40 seconds.
- Roll back FIRST, investigate second. A rolled-back deploy is not a failed deploy.

## Paging

- Errors above 2% for 5 minutes page the on-call.
- Latency p95 above 800 ms for 10 minutes pages the on-call.

## Notes

- [UPDATED 2026-07-20] Previously staging soak was 10 minutes. NOW 30 minutes. Reason: the 2026-07-08 incident (DB migration locked a table for 4 minutes and only showed at minute 12).
