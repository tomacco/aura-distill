#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Ivan Gonzalez (tomacco) - https://github.com/tomacco/aura-distill
#
# Enforces the rule in AGENTS.md ("never touch real user data") for the test tree (#155):
#   1. every test script that names a real profile path sources tests/lib/real-profile-guard.sh
#      (directly, or through tests/lib/isolate.sh) before anything else runs;
#   2. each of them, started without the opt-in, exits nonzero and changes nothing;
#   3. no runner injects test knowledge through a path the rules file no longer contains.
# Runs every script with HOME pointing at an empty temp directory, so it is safe to
# run anywhere, including on a machine with a real profile.
set -euo pipefail
cd "$(dirname "$0")/.."

# Scripts that name a real profile path but do not rewrite it. Keep this list short
# and say why for each entry.
#   test-sandbox.sh  installs into a mktemp HOME; reads the profile only for API auth.
ALLOWED="test-sandbox.sh"

fail=0
tmp_home=$(mktemp -d)
trap 'rm -rf "$tmp_home"' EXIT

mutators=$(grep -rlE 'REAL_CONFIG|\$HOME/\.claude|lib/isolate\.sh' --include='*.sh' tests test-*.sh \
           | grep -v -e '^tests/lib/real-profile-guard\.sh$' -e '^tests/check-real-profile-guard\.sh$' | sort)
[ -n "$mutators" ] || { echo "error: found no profile-touching test scripts; the pattern is stale" >&2; exit 1; }

checked=0
for f in $mutators; do
    case " $ALLOWED " in *" $f "*) continue ;; esac
    checked=$((checked + 1))
    if ! grep -qE 'lib/(real-profile-guard|isolate)\.sh' "$f"; then
        echo "FAIL $f names a real profile path but does not source tests/lib/real-profile-guard.sh" >&2
        fail=1; continue
    fi
    # The guard must come before the first line that names a profile path.
    guard_line=$(grep -nE 'lib/(real-profile-guard|isolate)\.sh' "$f" | head -n 1 | cut -d: -f1)
    first_use=$(grep -nE 'REAL_CONFIG|\$HOME/\.claude' "$f" | grep -vE '^[0-9]+:[[:space:]]*#' | head -n 1 | cut -d: -f1 || true)
    if [ -n "$first_use" ] && [ "$f" != tests/lib/isolate.sh ] && [ "$guard_line" -gt "$first_use" ]; then
        echo "FAIL $f names a profile path on line $first_use, before its guard on line $guard_line" >&2
        fail=1
    fi
    rc=0
    out=$(env -u AURA_DISTILL_ALLOW_REAL_PROFILE -u DISTILL_TEST_CONFIG HOME="$tmp_home" \
              bash "$f" </dev/null 2>&1) || rc=$?
    if [ "$rc" -eq 0 ] || ! printf '%s' "$out" | grep -q 'AURA_DISTILL_ALLOW_REAL_PROFILE=yes'; then
        echo "FAIL $f started without the opt-in (exit $rc)" >&2
        fail=1
    fi
    if [ -n "$(ls -A "$tmp_home")" ]; then
        echo "FAIL $f wrote into HOME before refusing: $(ls -A "$tmp_home" | tr '\n' ' ')" >&2
        rm -rf "$tmp_home"; mkdir -p "$tmp_home"; fail=1
    fi
done

# rules/distill.md addresses the store as {DISTILL_DIR}. A runner that substitutes only
# the old literal path injects nothing and the model falls back to the real store.
grep -q '{DISTILL_DIR}' rules/distill.md || { echo "error: rules/distill.md no longer uses {DISTILL_DIR}" >&2; exit 1; }
for f in $(grep -rlE 's\|[^|]*\.claude/distill\|' --include='*.sh' tests || true); do
    if ! grep -q 's|{DISTILL_DIR}|' "$f"; then
        echo "FAIL $f substitutes ~/.claude/distill but not {DISTILL_DIR}: test knowledge is not injected" >&2
        fail=1
    fi
done

[ "$fail" -eq 0 ] || exit 1
echo "OK: $checked profile-rewriting test scripts refuse to run without the opt-in"
