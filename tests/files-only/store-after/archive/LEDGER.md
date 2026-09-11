# Archive ledger

<!-- Append-only. One line per archive move or restore, written BEFORE the move. Synced with the knowledge set. Never rewrite past lines. -->

- 2026-09-11 archive | from: projects/atlas.md | to: archive/projects/atlas.md | sha256: 12c18385e88e5c0d0ebb9607f23ee8da4f5bb6fe96970f3f56a1ecf5fc84f98f | reason: past threshold, no validation observed | spine-entry: - [Atlas](projects/atlas.md) — Atlas data-platform migration from the legacy warehouse to the lakehouse; phase 2 (dual-write) done 2026-03, phase 3 (cutover) planned then paused when the vendor contract moved to Q4; decisions: parquet over ORC (evidence: 30% smaller at our row width), partition by ingest_date not event_date (constraint: late events), schema registry mandatory (directive from the data lead 2026-02); open items: backfill of the 2024 partitions, the two dashboards still reading the warehouse, the cost alert threshold. Read when working in the atlas-* repos.
