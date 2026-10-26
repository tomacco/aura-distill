---
id: task-5
title: "Retrieval protocol v2: persona regex false negative, stale CI sentence"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: []
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/126
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/126

Items for the next protocol version of `tests/retrieval-bench/PROTOCOL.md`. The frozen v1 cannot change; these do not alter the v1 verdict.

1. `s-persona` required regex `\b(never|not|...)\b.{0,80}(real|colleague|teammate|name)` needs the negation before the noun. Scored run `0047-F12-L-s-persona-r0` answered "a real colleague's name never goes in a fixture": a correct refusal, judge PASS, failed by the regex. On judged cases the required regex should only check that the topic is addressed, and the judge should decide the stance.
2. PROTOCOL.md says CI wiring for `test_bench.py` is pending; it shipped in #124.

Part of #77.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
