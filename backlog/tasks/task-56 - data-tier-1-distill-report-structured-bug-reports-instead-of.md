---
id: task-56
title: "Data Tier 1: /distill-report — structured bug reports instead of WhatsApp"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: []
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/31
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/31

A command that packages a diagnostic the USER reads before sending (user is the transport — this is not telemetry):

- distill version, Claude Code version, OS/platform
- the error or unexpected behavior (user-described)
- structure stats only: file counts per tier, SPINE line count, marker distribution
- NEVER knowledge content, never prompts

Output: a markdown block the user can paste into a GitHub issue (or a `gh issue create` one-liner if gh is present).

Directly replaces the WhatsApp anecdote channel with actionable reports. Zero collection; payload readable before sending.

From the 2026-07-09 token-saver session (telemetry design discussion).

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
