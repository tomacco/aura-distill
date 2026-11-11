---
id: task-2
title: Dispatcher requires an attached distillation sub-agent, but Claude Code runs it async
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: []
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/131
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/131

## Problem

Step 2 of `distill.md` says: "Keep the distillation agent attached until it completes ... In Claude Code specifically, never use `run_in_background: true`: background agents cannot obtain the write permissions this workflow requires."

In a current Claude Code session the Agent tool launched the distillation sub-agent asynchronously both times it was called, with no `run_in_background` argument. The dispatcher got "agent is working in the background" and a completion notification later. The instruction cannot be followed as written: the dispatcher does not control whether the harness runs the agent attached.

The permission claim is also unverified. Both async runs wrote the store successfully, but that session ran in bypass-permissions mode, so it says nothing about default mode, which is where the claim matters.

## Observed

2026-10-05, Claude Code (Opus 5.5), two `/distill` runs in one session (ledger entries at 07:43Z and 10:21Z). Both sub-agents ran async and finished their writes.

## Why it matters

- Step 3 assumes the dispatcher waits. With an async agent, a model that does not wait for the notification can report results it has not received, or start another distillation.
- If default-mode async agents really cannot get write permission, distillations in that mode fail. Nothing detects that except the agent reporting a denied write.

## Proposed fix

1. Test the permission claim in default mode with an async distillation sub-agent. Record the result in the dispatcher text, and drop the claim if it is false.
2. Reword Step 2 around what the dispatcher controls: spawn the agent, then do nothing else on the store until its completion notification arrives, and never report results before it does. The run lock from #127 stops a second distillation from writing meanwhile.
3. If default-mode async agents cannot write, say what to do: run the process attached through another mechanism, or report the limitation to the user before harvesting.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
