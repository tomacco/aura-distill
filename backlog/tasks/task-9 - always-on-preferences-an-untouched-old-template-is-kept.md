---
id: task-9
title: "Always-On preferences: an untouched old template is kept forever after the template changes"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: []
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/115
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/115

Routed from the round-three review of PR #113 (REVIEW-PROTOCOL rule 8). Part of #79.

**What happens now.** `install.sh`, `install.ps1` and `bin/distill-update.sh` keep the "Always-On User Preferences" section of `rules/distill.md` byte for byte, unless it is identical (ignoring whitespace) to the template section of the release being installed. If a release edits the template (for example its HTML comments), a user whose section is still the untouched *old* template no longer matches. Their section is kept, so they keep the old comment text forever. The reviewer reproduced this.

**Impact today: none.** The template section has been byte-identical since it landed on `main`.

**Options when the template next changes:**
1. Accept the freeze. It is only template comments, and it is safer than overwriting preferences, which is what happened to bullet-only or prose preferences before #113.
2. Compare against every previously shipped template, for example a small list of known template hashes carried in the installers and the updater, and replace on any match.

The same rule must stay identical in all three places. The preferences matrix in `tests/updater-compat/run.sh` section (j) and in `tests/test-codex.ps1` should gain an "old template" case either way.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
