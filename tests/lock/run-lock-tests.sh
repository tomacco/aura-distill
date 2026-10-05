#!/usr/bin/env bash
# Distill lock test: mutual exclusion, owner checks, stale takeover and .status forms for
# bin/distill-lock.sh, plus the same suite against bin/distill-lock.ps1 and a mixed run
# (bash and PowerShell callers on one store) when a PowerShell host is available.
#
# Every run works in a mktemp store via DISTILL_DIR; it never touches ~/.aura-distill.
set -uo pipefail
cd "$(dirname "$0")"

SH="$(pwd)/../../bin/distill-lock.sh"
PS1="$(pwd)/../../bin/distill-lock.ps1"
PS_BIN="${PS_BIN:-}"
[ -z "$PS_BIN" ] && command -v pwsh >/dev/null 2>&1 && PS_BIN=pwsh
[ -z "$PS_BIN" ] && command -v powershell.exe >/dev/null 2>&1 && PS_BIN=powershell.exe
PASS=0; FAIL=0

check() { # check <desc> <cmd...>
    local desc=$1; shift
    if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok: $desc"
    else FAIL=$((FAIL+1)); echo "  FAIL: $desc"; fi
}

# lock <impl> <args...> -- run one implementation; impl is sh or ps1
lock() {
    local impl=$1; shift
    if [ "$impl" = sh ]; then "$SH" "$@"; else "$PS_BIN" -NoProfile -File "$PS1" "$@"; fi
}

new_store() {
    local d; d=$(mktemp -d)
    case "$d" in "$HOME/.aura-distill"*) echo "refusing to test against the real store" >&2; exit 1 ;; esac
    echo "$d"
}

ISO_RE='[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z'

# Mutual exclusion under contention: N workers start together, each takes the lock, marks
# itself inside a critical section for a while, and releases. Two workers inside at once,
# or a missing enter/exit pair, fails the test. impls is a space-separated list cycled over
# the workers, so "sh ps1" runs a mixed field.
run_exclusion() {
    local label=$1 impls=$2 n=$3 hold=$4 store i impl arr
    store=$(new_store); export DISTILL_DIR=$store
    read -r -a arr <<< "$impls"
    for i in $(seq 1 "$n"); do
        impl=${arr[$(( (i - 1) % ${#arr[@]} ))]}
        (
            while [ ! -e "$store/go" ]; do sleep 0.01; done
            lock "$impl" acquire "w$i" --wait 120 >/dev/null || { echo "TIMEOUT w$i" >> "$store/log"; exit 1; }
            if ! mkdir "$store/inside" 2>/dev/null; then echo "OVERLAP w$i" >> "$store/log"; fi
            echo "enter w$i" >> "$store/log"
            sleep "$hold"
            echo "exit w$i" >> "$store/log"
            rmdir "$store/inside" 2>/dev/null
            lock "$impl" release "w$i" >/dev/null || echo "RELEASE-FAIL w$i" >> "$store/log"
        ) &
    done
    sleep 0.2; touch "$store/go"; wait
    check "$label: no two workers inside at once" bash -c "! grep -qE 'OVERLAP|TIMEOUT|RELEASE-FAIL' '$store/log'"
    check "$label: all $n workers ran" test "$(grep -c '^enter' "$store/log")" -eq "$n"
    check "$label: every enter is followed by its own exit" \
        bash -c "awk '/^enter/{if(cur!=\"\")bad=1;cur=\$2} /^exit/{if(cur!=\$2)bad=1;cur=\"\"} END{exit bad}' '$store/log'"
    check "$label: lock is free afterwards" test "$(lock sh status)" = "free"
    check "$label: .status ends idle" grep -qE "^idle $ISO_RE$" "$store/.status"
    rm -rf "$store"
}

# Many callers race to take over the same stale lock; exactly one may win each round.
run_stale_race() {
    local label=$1 impl=$2 rounds=$3 n=$4 store r i wins
    for r in $(seq 1 "$rounds"); do
        store=$(new_store); export DISTILL_DIR=$store
        echo "dead 1000 2001-09-09T01:46:40Z" > "$store/.lock"
        for i in $(seq 1 "$n"); do
            (
                while [ ! -e "$store/go" ]; do sleep 0.005; done
                if lock "$impl" acquire "s$i" >/dev/null; then echo "s$i" >> "$store/won"; fi
            ) &
        done
        sleep 0.2; touch "$store/go"; wait
        wins=$(wc -l < "$store/won" 2>/dev/null | tr -d ' ')
        if [ "${wins:-0}" -ne 1 ]; then
            FAIL=$((FAIL+1)); echo "  FAIL: $label: round $r had ${wins:-0} winners (want exactly 1)"
            rm -rf "$store"; return
        fi
        check_owner_matches "$store" "$(cat "$store/won")" || { FAIL=$((FAIL+1)); echo "  FAIL: $label: round $r lock owner is not the winner"; rm -rf "$store"; return; }
        rm -rf "$store"
    done
    PASS=$((PASS+1)); echo "  ok: $label: exactly one winner in each of $rounds rounds of $n racers"
}

check_owner_matches() { [ "$(cut -d' ' -f1 "$1/.lock")" = "$2" ]; }

run_unit() {
    local impl=$1 store out rc before
    echo "-- $impl: owner checks, stale takeover, .status forms"
    store=$(new_store); export DISTILL_DIR=$store

    check "$impl: status on an empty store is free" test "$(lock "$impl" status)" = "free"
    check "$impl: first acquire succeeds" lock "$impl" acquire alpha
    check "$impl: lock line is '<owner> <epoch> <iso>'" grep -qE "^alpha [0-9]+ $ISO_RE$" "$store/.lock"
    check "$impl: acquire writes 'running <iso>'" grep -qE "^running $ISO_RE$" "$store/.status"
    out=$(lock "$impl" acquire beta); rc=$?
    check "$impl: second owner is refused with exit 1" test "$rc" -eq 1
    check "$impl: refusal names the holder" bash -c "echo '$out' | grep -qE '^held alpha [0-9]+s$'"
    check "$impl: re-acquire by the holder succeeds" lock "$impl" acquire alpha
    before=$(cat "$store/.lock")
    lock "$impl" release beta >/dev/null; rc=$?
    check "$impl: release by a non-owner exits 3" test "$rc" -eq 3
    check "$impl: non-owner release leaves the lock alone" test "$(cat "$store/.lock")" = "$before"
    lock "$impl" heartbeat beta >/dev/null; rc=$?
    check "$impl: heartbeat by a non-owner exits 3" test "$rc" -eq 3
    check "$impl: owner heartbeat with a checkpoint" lock "$impl" heartbeat alpha step:2 signals:9
    check "$impl: checkpoint writes 'running step:N signals:M <iso>'" grep -qE "^running step:2 signals:9 $ISO_RE$" "$store/.status"
    check "$impl: owner release succeeds" lock "$impl" release alpha
    check "$impl: release writes 'idle <iso>'" grep -qE "^idle $ISO_RE$" "$store/.status"
    check "$impl: lock file is gone after release" test ! -e "$store/.lock"
    before=$(cat "$store/.status")
    lock "$impl" release alpha >/dev/null; rc=$?
    check "$impl: releasing a free lock exits 3" test "$rc" -eq 3
    check "$impl: ...and does not touch .status" test "$(cat "$store/.status")" = "$before"

    echo "dead 1000 2001-09-09T01:46:40Z" > "$store/.lock"
    out=$(lock "$impl" status)
    check "$impl: an old heartbeat reads as stale" bash -c "echo '$out' | grep -qE '^stale dead [0-9]+s$'"
    out=$(lock "$impl" acquire gamma); rc=$?
    check "$impl: a stale lock is taken over" test "$rc" -eq 0
    check "$impl: takeover is reported" bash -c "echo '$out' | grep -q 'took over stale lock from dead'"
    lock "$impl" heartbeat dead >/dev/null; rc=$?
    check "$impl: the dead owner's heartbeat reports the loss (exit 3)" test "$rc" -eq 3
    lock "$impl" release gamma >/dev/null

    echo "garbage" > "$store/.lock"; touch -t 200101010000 "$store/.lock"
    check "$impl: a malformed old lock is taken over" lock "$impl" acquire delta
    lock "$impl" release delta >/dev/null
    echo "garbage" > "$store/.lock"
    lock "$impl" acquire eps >/dev/null; rc=$?
    check "$impl: a malformed fresh lock still blocks" test "$rc" -eq 1
    rm -f "$store/.lock"

    lock "$impl" acquire alpha >/dev/null
    local t0=$SECONDS
    lock "$impl" acquire beta --wait 3 >/dev/null; rc=$?
    check "$impl: --wait gives up with exit 1 when the holder stays" test "$rc" -eq 1
    check "$impl: --wait honours its timeout (3s, allowing startup)" test $(( SECONDS - t0 )) -le 8
    lock "$impl" release alpha >/dev/null

    # Near the stale cutoff the owner refreshes through the aside-and-check path.
    export DISTILL_LOCK_STALE_SECONDS=4
    lock "$impl" acquire alpha >/dev/null
    before=$(cut -d' ' -f2 "$store/.lock")
    sleep 2.2
    check "$impl: heartbeat past half the stale window keeps the lock" lock "$impl" heartbeat alpha
    check "$impl: ...and refreshes its epoch" test "$(cut -d' ' -f2 "$store/.lock")" -gt "$before"
    lock "$impl" release alpha >/dev/null
    unset DISTILL_LOCK_STALE_SECONDS

    lock "$impl" acquire 'bad owner' >/dev/null 2>&1; rc=$?
    check "$impl: an owner with spaces is a usage error (exit 2)" test "$rc" -eq 2
    lock "$impl" acquire '../x' >/dev/null 2>&1; rc=$?
    check "$impl: an owner with a slash is a usage error (exit 2)" test "$rc" -eq 2
    lock "$impl" frobnicate >/dev/null 2>&1; rc=$?
    check "$impl: an unknown command is a usage error (exit 2)" test "$rc" -eq 2
    check "$impl: no temp files left behind" test -z "$(ls -A "$store" | grep -vE '^\.status$')"
    rm -rf "$store"
}

echo "== bash implementation"
run_unit sh
run_exclusion "sh: 4 concurrent distills" "sh" 4 0.4
run_exclusion "sh: 12 concurrent distills" "sh" 12 0.05
run_stale_race "sh: stale takeover race" sh 20 6

if [ -n "$PS_BIN" ]; then
    echo "== PowerShell implementation ($PS_BIN)"
    run_unit ps1
    run_exclusion "ps1: 4 concurrent distills" "ps1" 4 0.4
    run_stale_race "ps1: stale takeover race" ps1 5 4
    echo "== mixed field (bash and PowerShell share one store)"
    run_exclusion "mixed: 6 concurrent distills" "sh ps1" 6 0.3
else
    echo "== PowerShell implementation: SKIPPED (no pwsh or powershell.exe on PATH)"
fi

echo
echo "lock tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
