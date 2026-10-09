---
id: task-15
title: AGENTS.md says research/* is never merged to main, but research folders live on main
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: []
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/98
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/98

`AGENTS.md` → Branch conventions:

> `research/*` — experiments and published research (**never merged to main directly**)

But `research/2026-07-09-token-saver/` has been on `main` since #29, and `research/2026-09-22-local-harvest/` merged in #97. The convention line and the practice disagree; an independent review flagged it on #97 as a maintainer decision rather than something to change silently.

Pick one:

- **Practice is right** → drop or reword the AGENTS.md line (research folders merge to main; the `research/*` branch prefix just marks the work in flight).
- **Convention is right** → research folders stop merging and live on long-running branches, which means the two already on main need relocating and the docs site needs to source from somewhere else.

Low urgency, but every agent reads AGENTS.md as authoritative, so a contradiction in it costs something each time.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
