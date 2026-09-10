---
domain: craft
scope: Testing philosophy (continued) — CI script rule and index detail moved from the SPINE
last_updated: 2026-08-30
last_validated: 2026-08-30
staleness_threshold: 120
split_from: craft/testing.md
---

## Principles (continued from craft/testing.md)

- [PRINCIPLE] CI runs the shipped script, never a copy of it. Extract the script under test so the test executes the same bytes users get.
  confidence: provisional (2 confirmations, 0 corrections)
  last_validated: 2026-08-12

## Index detail (moved from SPINE 2026-09-11)

contract tests over mocks (validated 9x, hardened after the 2026-06 incident where a mocked payment client hid a schema change for three weeks); every bug gets a failing test BEFORE the fix, verified to fail without the fix; flaky = hypothesis not verdict; no sleep-based waits; test names describe behaviour not method; fixtures are builders not JSON blobs; the persona rule (generic test personas, never colleagues' names); coverage thresholds are per-module not global; CI must run the shipped script not a copy. Read before writing or reviewing any test.
