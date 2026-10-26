---
id: task-53
title: "Follow-ups deferred from Token Saver review (PR #29)"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: []
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/34
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/34

Two review findings deliberately deferred from PR #29:

- [ ] CHANGELOG: stale `## [0.7.0] - 2026-05-15 (unreleased)` heading sits directly under the new [Unreleased] block while VERSION is 1.1.x — pre-existing cruft, reads wrong now (review finding #9)
- [ ] Accessibility: controls-block on token-saving.html uses <br>-separated spans instead of <pre><code> (screen readers get run-on text); --dim small text borderline contrast in light mode — site-wide pattern, fix consistently (review finding #11)

Also worth considering from the same research:
- [ ] Instrument distill-benchmark arms with token telemetry ("tokens-to-outcome" metric) — the missing counterfactual for "distill saves tokens" (research page verdict #2)
- [ ] Upstream feature request to anthropics/claude-code: defer built-in tool schemas in subagent spawns (measured ~22k of the ~27.4k spawn floor; MCP schemas already deferred)

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
