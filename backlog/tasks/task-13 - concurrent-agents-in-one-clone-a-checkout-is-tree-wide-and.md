---
id: task-13
title: "Concurrent agents in one clone: a checkout is tree-wide and invisible, and it can push unreviewed commits into main"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: []
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/102
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/102

## What happened

Two agents worked in `~/repos/aura-distill` at the same time on 2026-09-22. Neither did anything unusual; both ran `git checkout`.

Reflog from the shared tree:

```
checkout: moving from main to research/2026-09-22-local-routing      (agent A)
checkout: moving from research/2026-09-22-local-routing to research/2026-09-22-local-harvest   (agent B)
checkout: moving from research/2026-09-22-local-harvest to main      (agent B)
```

Agent B's second checkout silently moved agent A onto `main`. Agent A then made **nine commits believing it was on its own branch**. They landed on local `main`.

## Why this is a correctness problem, not a tidiness one

Agent B pushed `main` twice during that window, from a different clone. Had it pushed from the shared tree instead, **nine unreviewed research commits would have entered `main` inside someone else's push** — bypassing `REVIEW-PROTOCOL.md` entirely, with nothing in either agent's view of the world looking wrong.

The mechanism is the point: **a checkout changes `HEAD` for every process in that tree, and nothing notifies the others.** `git status` looks normal to everyone. The failure is silent by construction, so "be careful" is not a mitigation.

Related, same root cause: one agent quoted shell commands in backticks inside a message, passed the text to a shell, and the backticks were command-substituted — running `git checkout` and a `reset` in the shared tree while writing a message *about not doing that*. Text reaching a shell is a separate bug, but the blast radius came from the shared tree.

## What is already in the repo

`AGENTS.md:70` and `REVIEW-PROTOCOL.md:11,25` require a worktree **for reviewers**. That is the right mechanism, applied to one case. The general case — any two agents in this clone — is undocumented.

## Proposed

Document the rule in `AGENTS.md`: never `git checkout` in a shared clone; use `git worktree add` (or a separate clone); leave the primary checkout parked on `main`. Include the recovery procedure, since the failure is silent and the reflog is the only evidence.

Agreed between both agents involved; the second has said it will review the PR and not touch `AGENTS.md` meanwhile.

## Out of scope

The stale `research/*` line in the same file (#98) stays open — different problem, single-purpose PR.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
