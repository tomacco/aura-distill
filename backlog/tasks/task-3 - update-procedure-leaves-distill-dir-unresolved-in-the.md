---
id: task-3
title: Update procedure leaves {DISTILL_DIR} unresolved in the installed dispatcher and process files
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: []
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/130
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/130

## Problem

The update procedure in `distill.md` (Version Checking, "Update procedure", lines 252-263) downloads `distill.md`, `distill-process.md` and `distill-monitor.md` with plain `curl -o`. The installers pipe the same files through `sed "s|{DISTILL_DIR}|<store>|g"`; the update procedure does not. After an auto-update, the installed dispatcher and process file contain the literal `{DISTILL_DIR}` placeholder.

Agents cope today only because `rules/distill.md` says to read a literal placeholder as `~/.aura-distill`. That fallback is wrong for anyone who installed with `AURA_DISTILL_HOME` pointing elsewhere: after one update their distillations read and write the default store and miss their real one.

Two smaller problems in the same block:

- `curl -sL` without `-f` writes a 404 page or a proxy error page over a working file when a download fails.
- Each file is overwritten in place, so a failure partway leaves a mix of old and new versions.

## Observed

2026-10-05, updating a Mac install from 1.1.27 to 1.1.28. Following the procedure as written would have left unresolved placeholders in `~/.claude/commands/distill.md` and `~/.aura-distill/distill-process.md`. I resolved them by hand with `sed` during the update.

## Proposed fix

- Download each file with `curl -fsSL` into a temp file, resolve `{DISTILL_DIR}` with the same `sed` the installers use, and move it into place only when every download succeeded.
- Or replace the block with a call to the installer, which resolves the path, preserves the always-on preferences and installs `bin/`. This keeps one update path, so the two cannot drift again.
- Add a check to `tests/test-install.sh` that runs the documented update procedure against a store under a custom `AURA_DISTILL_HOME` and asserts that no installed file contains `{DISTILL_DIR}`.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
