# Distill Knowledge Index

<!-- Managed by aura-distill. Max 80 lines. Entry: - [Title](path.md) -- when to read this. last_updated: 2026-08-30 -->

## Profile
- [Noor — core](profile/noor.md) — platform engineer at a fictional logistics company; owns the Atlas, Beacon and Comet services; terse in ops mode, discursive when changing process; wants pushback on architecture calls; identifies things by content quotes not paths; expects evidence for "done?" questions (show the curl, show the test output); dislikes preamble; Spanish/English mixed; reads side notes. Read at session start.

## Craft
- [Testing philosophy](craft/testing.md) — contract tests over mocks (validated 9x, hardened after the 2026-06 incident where a mocked payment client hid a schema change for three weeks); every bug gets a failing test BEFORE the fix, verified to fail without the fix; flaky = hypothesis not verdict; no sleep-based waits; test names describe behaviour not method; fixtures are builders not JSON blobs; the persona rule (generic test personas, never colleagues' names); coverage thresholds are per-module not global; CI must run the shipped script not a copy. Read before writing or reviewing any test.

## Ops
- [Deploy procedure](ops/deploy.md) — canary → staging → prod with the 5/30 minute soak; rollback command; who to page. Read before shipping to production.

## Projects
- [Atlas](projects/atlas.md) — Atlas data-platform migration from the legacy warehouse to the lakehouse; phase 2 (dual-write) done 2026-03, phase 3 (cutover) planned then paused when the vendor contract moved to Q4; decisions: parquet over ORC (evidence: 30% smaller at our row width), partition by ingest_date not event_date (constraint: late events), schema registry mandatory (directive from the data lead 2026-02); open items: backfill of the 2024 partitions, the two dashboards still reading the warehouse, the cost alert threshold. Read when working in the atlas-* repos.
- [Beacon](projects/beacon.md) — Beacon notification service; current focus is the push-provider fallback chain. Read when working in the beacon repo.
- [Comet](projects/comet.md) — Comet billing reconciliation; on hold since 2026-05 but pinned: legal retention rules live here. Read before touching invoices or reconciliation.

## Feedback
- [Preferences](feedback/preferences.md) — output and interaction rules incl. the non-negotiables. Read when shaping output for Noor.
