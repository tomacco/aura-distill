#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Ivan Gonzalez (tomacco) - https://github.com/tomacco/aura-distill
#
# Sourced as the first action of every test script that rewrites a real Claude
# profile: these scripts blank CLAUDE.md, move rules/, plugins/ and distill/ aside
# and edit settings.json under $HOME/.claude (or DISTILL_TEST_CONFIG), and restore
# them on exit. A killed run leaves the profile stripped. AGENTS.md forbids testing
# against real profile directories, so the scripts refuse to start unless the caller
# opts in for this one invocation. tests/check-real-profile-guard.sh enforces that
# every such script sources this file (#155).

if [ "${AURA_DISTILL_ALLOW_REAL_PROFILE:-}" != "yes" ]; then
    cat >&2 <<'MSG'
refusing to run: this script rewrites a real Claude profile.

It blanks CLAUDE.md, moves rules/, plugins/ and distill/ aside and edits
settings.json under $HOME/.claude (or DISTILL_TEST_CONFIG) while it runs.
A run that is killed leaves the profile in that state.

Use a disposable machine or account. If that is what this is, opt in for
this one run:

    AURA_DISTILL_ALLOW_REAL_PROFILE=yes <command>

Deterministic tests that never touch a profile: tests/test-install.sh,
tests/lock/run-lock-tests.sh, tests/antigravity/run-parity-test.sh.
MSG
    exit 1
fi
