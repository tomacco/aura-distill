# Knowledge catalog

<!-- Complete inventory, rebuilt by /distill. Not loaded at session start. rebuilt: 2026-09-11 -->

## active
- craft/testing-2.md | Testing philosophy (continued) — CI script rule and index detail moved from the SPINE | validated 2026-08-30
- craft/testing.md | Testing philosophy for Noor's services — contract tests, failing-test-first, flakiness discipline | validated 2026-08-30
- feedback/preferences.md | Output and interaction preferences | validated 2026-08-28
- ops/deploy.md | Deploy procedure for Noor's services — canary, staging, prod, rollback, paging | validated 2026-08-25
- profile/noor.md | Who Noor is and how they work | validated 2026-08-28
- projects/beacon.md | Beacon notification service — push-provider fallback chain | validated 2026-08-27
- projects/comet.md | Comet billing reconciliation — on hold, retention rules | validated 2026-05-06 | pinned

## archived
- archive/old-warehouse-notes.md | Superseded warehouse notes (rewritten by an earlier compaction) | legacy
- archive/projects/atlas.md | Atlas data-platform migration — legacy warehouse to lakehouse | archived 2026-09-11 | reason: past threshold, no validation observed | from projects/atlas.md | hook: Atlas data-platform migration from the legacy warehouse to the lakehouse; phase 2 (dual-write) done 2026-03, phase 3 (cutover) planned then paused when the vendor contract moved to Q4; decisions: parquet over ORC (evidence: 30% smaller at our row width), partition by ingest_date not event_date (constraint: late events), schema registry mandatory (directive from the data lead 2026-02); open items: backfill of the 2024 partitions, the two dashboards still reading the warehouse, the cost alert threshold. Read when working in the atlas-* repos.

## evidence
- evidence/craft/testing.md | for craft/testing.md | 30 entries
