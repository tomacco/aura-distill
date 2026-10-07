---
id: task-16
title: "Homebrew tap pinned to v1.0.0: fresh macOS installs land in legacy ~/.claude/distill while reporting v1.1.17"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: []
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/95
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/95

## Summary

`brew install tomacco/aura-distill/aura-distill` (the macOS path advertised in README.md:45-47) still installs the **v1.0.0** tarball. Its bundled `install.sh` (VERSION 1.0.1) predates the shared-store change and hardcodes the knowledge directory to the legacy `~/.claude/distill`. Because that old installer also fetches `distill.md`, `rules/distill.md`, `distill-process.md` etc. from **`main`**, the result is a hybrid install: current 1.1.x rule/command text, with `{DISTILL_DIR}` resolved to the legacy path, and no `~/.aura-distill` at all.

The `/distill` in-place updater then keeps this install "current" (`.version` = 1.1.17) without ever re-running an installer, so the folder never migrates. Observed on a fresh Mac install, 2026-09-18.

## Observed state (fresh macOS install, 2026-09-18)

```
/opt/homebrew/bin/aura-distill -> ../Cellar/aura-distill/1.0.0/bin/aura-distill
/opt/homebrew/Cellar/aura-distill/1.0.0/libexec/VERSION        -> 1.0.1
/opt/homebrew/Cellar/aura-distill/1.0.0/libexec/install.sh:190 -> DISTILL_DIR="$PROFILE_DIR/distill"
~/.aura-distill                                                -> does not exist
~/.claude/distill/.version                                     -> 1.1.17
~/.claude/rules/distill.md                                     -> "**/Users/ivan/.claude/distill** = the shared Aura Distill directory, normally `~/.aura-distill/`..."
~/.claude/CLAUDE.md                                            -> old "# Distill — knowledge system ... GATE:" block (the format install.sh:416-421 on main now classifies as *legacy* and strips)
```

Meanwhile a Windows machine on the same version writes to `%USERPROFILE%\.aura-distill` (per `ops/agent-patterns.md`: "multi-client since v1.1.12; the old `.claude\distill` path is history"). Cross-machine transfer tooling (e.g. `aura-sync`, courier repos) that assumes `~/.aura-distill` silently misses the Mac's knowledge.

## Root cause

1. `homebrew/Formula/aura-distill.rb` (and the published tap `tomacco/homebrew-aura-distill`) pin `url ".../archive/refs/tags/v1.0.0.tar.gz"` — never bumped since the shared-store change in v1.1.12. `[version-bump]` commits don't touch the formula.
2. The v1.0.0 formula's wrapper `uninstall` subcommand also hardcodes `$PROFILE/distill/...`, so it would not clean a correct `~/.aura-distill` install either.
3. The `/distill` update procedure (distill.md "Update procedure") only overwrites dispatcher/process/monitor + `.version` at the already-resolved `{DISTILL_DIR}`; it never re-runs `install.sh`, so no path migration can happen through auto-update. (This is the same class of problem #94 / #76 are auditing for the future major — but it has already happened once for a minor.)

## Suggested fix

- Bump the tap formula (and `homebrew/Formula/aura-distill.rb`) to the current tag, and have the `[version-bump]` workflow update the formula `url`/`sha256` (or point the formula at `head` / a `latest` release asset) so brew can't drift again.
- Make the formula wrapper's `uninstall` honor `AURA_DISTILL_HOME` / `~/.aura-distill`.
- Consider having the `/distill` version check detect "`.version` ≥ 1.1.12 but `{DISTILL_DIR}` resolves to `<profile>/distill`" and tell the user to re-run the installer (the legacy-seed logic in `install.sh:224-233` already handles the copy).
- Optionally: install.sh could refuse to run (or warn loudly) when its bundled `VERSION` is older than the `main/VERSION` it is about to fetch files from — that mismatch is exactly what produced the hybrid install.

## Workaround applied locally

Knowledge kept at `~/.claude/distill` (where the resolved rules/commands point) until the installer is fixed; re-running the corrected installer will seed `~/.aura-distill` from the legacy dir via the existing `.legacy-imported` path.

Related: #94, #76.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
