---
id: task-57
title: "Data Tier 0: turn on passive distribution metrics (zero telemetry)"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: []
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/30
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/30

From the token-saver research session (2026-07-09): distill development currently has ZERO datapoints — only WhatsApp anecdotes.

Tier 0 costs nothing and touches no user machine:
- [ ] Check GitHub traffic/clones + release download counts regularly (or a tiny scheduled job that snapshots them — GitHub only keeps 14 days of traffic history)
- [ ] Publish install script via a countable channel where possible (release assets have download counts; raw.githubusercontent does not)
- [ ] Homebrew tap analytics (brew provides install counts)

Answers: does anyone install? which versions get adopted? platform split (justifies install.ps1 maintenance)?

Privacy: nothing collected from users. Consistent with the token-saving.html landing promise.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
