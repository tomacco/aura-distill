---
domain: projects
scope: Atlas data-platform migration — legacy warehouse to lakehouse
last_updated: 2026-04-02
last_validated: 2026-04-02
staleness_threshold: 90
---

## State

- Phase 2 (dual-write) complete 2026-03-15.
- Phase 3 (cutover) planned for 2026-05, then paused: the vendor contract renewal moved to Q4.

## Decisions

- [DECISION] Parquet over ORC. origin: evidence (30% smaller at our row width, 2026-02 benchmark).
- [DECISION] Partition by ingest_date, not event_date. origin: constraint (late-arriving events up to 14 days).
- [DIRECTIVE] Schema registry is mandatory for every new table. origin: directive (data lead, 2026-02-10).

## Open items

- Backfill the 2024 partitions (blocked on storage budget).
- Two dashboards still read the warehouse directly.
- Cost alert threshold not set for the lakehouse account.
