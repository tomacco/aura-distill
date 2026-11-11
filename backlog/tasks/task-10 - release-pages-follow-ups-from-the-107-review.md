---
id: task-10
title: "Release pages follow-ups from the #107 review"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: []
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/111
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/111

Routed from the PR #107 round-two review (claude-fable-5-1, clean profile, APPROVE), per REVIEW-PROTOCOL.md rule 8. Fix these when the 1.2.0-beta.1 page is written.

- [x] `docs/releases/index.html`: "1.1.0 to 1.1.24", "25 versions" and "Updated 2026-09-23" go stale with every auto-bump. Use open-ended wording ("1.1.0 onward") or sync them in bump-version.yml.
- [x] README and template cite REVIEW-PROTOCOL.md rules 6/7 and DECISIONS.md IDs that exist only on `beta/1.2` until promotion; the index's `blob/beta/1.2` link dies when the branch is deleted. Use commit permalinks.
- [x] Template/README: say whether the badge reads `beta` or `beta.1`, with one example.
- [x] README placeholder check: also grep for `href="#"` in the evidence rows.
- [ ] Root README.md link row has no Releases link. Add it with the next non-docs PR.

Part of #74

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
