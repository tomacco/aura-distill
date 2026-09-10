---
evidence_for: projects/atlas.md
---
- 2026-09-11 spine-detail: Atlas data-platform migration from the legacy warehouse to the lakehouse; phase 2 (dual-write) done 2026-03, phase 3 (cutover) planned then paused when the vendor contract moved to Q4; decisions: parquet over ORC (evidence: 30% smaller at our row width), partition by ingest_date not event_date (constraint: late events), schema registry mandatory (directive from the data lead 2026-02); open items: backfill of the 2024 partitions, the two dashboards still reading the warehouse, the cost alert threshold. Read when working in the atlas-* repos.
