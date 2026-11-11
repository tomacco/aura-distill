---
id: task-6
title: "1.2 runtime: every session probes for local/SPINE.md, costing one model turn"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: []
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/125
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/125

Measured by the frozen retrieval benchmark (#77, #62; scored run 2026-10-04, 156 runs): in 76 of 78 F12 sessions the agent spends a tool call checking for `local/SPINE.md`, because `distill-monitor.md` and `rules/distill.md` say to read it if it exists. On a store without the overlay that call finds nothing. Each tool call costs a model round trip (pilot: file I/O is 0.15 s of a 12.8 s answer), so this is likely the main source of the 1.2 slowdown: geometric-mean time to a correct answer 1.17x at scale S (90% interval 1.04 to 1.28, a regression under the frozen rules) and 1.09x at scale L (no practical difference).

Fix to consider: make the overlay's existence known without a probe (for example, the SPINE names `local/SPINE.md` only when the overlay exists, written by `/distill`), then re-run the scored benchmark (the protocol's arms take the 1.2 runtime from a git ref).

Part of #78.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
