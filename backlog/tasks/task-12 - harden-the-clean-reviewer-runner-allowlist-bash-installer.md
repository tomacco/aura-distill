---
id: task-12
title: "Harden the clean reviewer runner: allowlist Bash, installer profile glob, untested paths"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: []
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/109
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/109

Routed from the PR #108 round-two review (claude-fable-5-1, clean profile, APPROVE), per REVIEW-PROTOCOL.md rule 8.

- [ ] **Blast radius:** the runner auto-approves all Bash in headless mode and relies on a prefix denylist. `git -C … push`, `/opt/homebrew/bin/gh pr comment`, `env gh …` and a subshell all get around it. Move to an allowlist (`git log/diff/show/grep/rev-parse`, `gh pr view/diff`, `gh issue view`, `bash tests/…`, read-only coreutils), or run the reviewer as a user or container without the maintainer's `gh` token and with a read-only `.git`.
- [ ] **Installer profile menu:** `install.sh:129-134` globs `$HOME/.claude-*/`, so `~/.claude-reviewer` appears in the interactive "Multiple profiles detected" menu. Skip profiles named `*reviewer*`, or document a reviewer profile path outside that glob.
- [ ] **Untested paths:** missing profile directory, unset `REVIEW_OUT_DIR` (kept temp dir), the "could not extract template" branch, and cleanup on interrupt. `--allowedTools`/`--settings` are only asserted as argument strings.
- [ ] **Reviewer environment check:** the profile check covers distill files. Also check `settings.json` for hooks or plugins that inject context.

Part of #74

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
