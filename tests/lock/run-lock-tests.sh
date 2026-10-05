#!/usr/bin/env bash
# Distill lock test: mutual exclusion, owner checks, stale takeover and .status forms for
# bin/distill-lock.sh, plus the same suite against bin/distill-lock.ps1 and a mixed run
# (bash and PowerShell callers on one store) when a PowerShell host is available.
#
# Every run works in a mktemp store via DISTILL_DIR; it never touches ~/.aura-distill.
set -uo pipefail
cd "$(dirname "$0")"

SH="${LOCK_SH:-$(pwd)/../../bin/distill-lock.sh}"
PS1="$(pwd)/../../bin/distill-lock.ps1"
# PS_BIN=none skips the PowerShell twin; LOCK_SH points the bash runs at another script.
PS_BIN="${PS_BIN:-}"
if [ "$PS_BIN" = none ]; then PS_BIN=
else
    [ -z "$PS_BIN" ] && command -v pwsh >/dev/null 2>&1 && PS_BIN=pwsh
    [ -z "$PS_BIN" ] && command -v powershell.exe >/dev/null 2>&1 && PS_BIN=powershell.exe
fi
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
    check "$impl: no temp files left behind" test -z "$(ls -A "$store" | grep -vE '^\.status$|^\.lock\.takeover$')"
    rm -rf "$store"
}

# I/O failures must never read as success: a read-only store makes every write fail, and each
# command has to exit 4 without printing "ok". Skipped where chmod does not block writes
# (root, Windows).
run_io_failure() {
    local impl=$1 store out rc
    echo "-- $impl: I/O failures exit 4"
    store=$(new_store); export DISTILL_DIR=$store
    lock "$impl" acquire alpha >/dev/null
    chmod 555 "$store"
    if touch "$store/probe" 2>/dev/null; then
        rm -f "$store/probe"; chmod 755 "$store"; rm -rf "$store"
        echo "  skip: $impl: chmod does not block writes here (root or Windows)"; return
    fi
    out=$(lock "$impl" heartbeat alpha step:2 signals:3 2>/dev/null); rc=$?
    check "$impl: heartbeat with a checkpoint in a read-only store exits 4" test "$rc" -eq 4
    check "$impl: ...and does not print ok" bash -c "! echo '$out' | grep -qx ok"
    lock "$impl" release alpha >/dev/null 2>&1; rc=$?
    check "$impl: release in a read-only store exits 4" test "$rc" -eq 4
    chmod 755 "$store"; echo "alpha $(( $(date -u +%s) - 200 )) x" > "$store/.lock"; chmod 555 "$store"
    lock "$impl" heartbeat alpha >/dev/null 2>&1; rc=$?
    check "$impl: near-stale heartbeat in a read-only store exits 4" test "$rc" -eq 4
    chmod 755 "$store"; rm -f "$store/.lock"; chmod 555 "$store"
    lock "$impl" acquire beta >/dev/null 2>&1; rc=$?
    check "$impl: acquire in a read-only store exits 4, not 1" test "$rc" -eq 4
    chmod 755 "$store"; rm -f "$store/.lock"
    chmod -R u+w "$store" 2>/dev/null; rm -rf "$store"
}

# Deterministic interleaving (bash): a stale takeover is frozen inside the takeover mutex, right
# before it renames its line over .lock, by an mv shim on its PATH. While it is frozen, the lock
# must never go missing, a second contender cannot win, and the old owner can neither refresh
# nor release. After it resumes there is exactly one owner and the old owner has lost.
run_interleaving() {
    local store shim rc t_pid c_rc hb_rc rel_rc stale
    echo "-- sh: frozen takeover (deterministic interleaving)"
    store=$(new_store); export DISTILL_DIR=$store
    shim=$(mktemp -d)
    cat > "$shim/mv" <<SHIM
#!/usr/bin/env bash
if [ "\$1" = "-f" ] && [ "\${3:-}" = "$store/.lock" ]; then
    touch "$shim/paused"
    while [ ! -e "$shim/resume" ]; do sleep 0.02; done
fi
exec /bin/mv "\$@"
SHIM
    chmod +x "$shim/mv"
    stale=$(( $(date -u +%s) - 1000 ))
    echo "old $stale 2001-09-09T01:46:40Z" > "$store/.lock"

    PATH="$shim:$PATH" "$SH" acquire taker >"$shim/taker.out" 2>&1 &
    t_pid=$!
    local waited=0
    while [ ! -e "$shim/paused" ]; do
        sleep 0.02; waited=$((waited + 1))
        if [ "$waited" -ge 500 ]; then
            touch "$shim/resume"; wait "$t_pid"
            FAIL=$((FAIL+1)); echo "  FAIL: frozen: the takeover never replaced .lock in place (no atomic replace step)"
            rm -rf "$store" "$shim"; return
        fi
    done

    ( while [ ! -e "$shim/resume" ]; do [ -e "$store/.lock" ] || echo MISSING >> "$shim/gaps"; sleep 0.01; done ) &
    local watch_pid=$!
    "$SH" acquire contender >/dev/null 2>&1 & local c_pid=$!
    "$SH" heartbeat old >/dev/null 2>&1 & local h_pid=$!
    "$SH" release old >/dev/null 2>&1 & local r_pid=$!
    wait "$c_pid"; c_rc=$?
    wait "$h_pid"; hb_rc=$?
    wait "$r_pid"; rel_rc=$?
    check "frozen: a second stale contender cannot win (exit 1)" test "$c_rc" -eq 1
    check "frozen: the old owner's near-stale heartbeat cannot refresh (exit 3)" test "$hb_rc" -eq 3
    check "frozen: the old owner's release cannot remove the lock (exit 3)" test "$rel_rc" -eq 3
    check "frozen: the lock line is still the old one" grep -q "^old $stale " "$store/.lock"

    touch "$shim/resume"; wait "$t_pid"; rc=$?; wait "$watch_pid"
    check "frozen: the lock file never went missing" test ! -e "$shim/gaps"
    check "resumed: the takeover completes (exit 0)" test "$rc" -eq 0
    check "resumed: exactly one owner, the taker" test "$(cut -d' ' -f1 "$store/.lock")" = "taker"
    "$SH" heartbeat old >/dev/null 2>&1; rc=$?
    check "resumed: the old owner's heartbeat exits 3" test "$rc" -eq 3
    "$SH" release old >/dev/null 2>&1; rc=$?
    check "resumed: the old owner's release exits 3" test "$rc" -eq 3
    check "resumed: the taker still holds the lock" test "$(cut -d' ' -f1 "$store/.lock")" = "taker"
    rm -rf "$store" "$shim"
}

# Deterministic interleaving (bash), from the second Codex review: an owner's heartbeat is
# frozen after it read the lock line and before it takes the mutex (a perl shim pauses the
# mutex acquisition). The lease expires, another caller takes the lock over, then the heartbeat
# resumes. It must report the loss (exit 3) and leave the new owner's line alone.
run_delayed_heartbeat() {
    local store shim rc h_pid b_rc
    echo "-- sh: delayed heartbeat (deterministic interleaving)"
    store=$(new_store); export DISTILL_DIR=$store
    shim=$(mktemp -d)
    cat > "$shim/perl" <<SHIM
#!/usr/bin/env bash
if [ ! -e "$shim/passed" ]; then
    touch "$shim/paused" "$shim/passed"
    while [ ! -e "$shim/resume" ]; do sleep 0.02; done
fi
exec $(command -v perl) "\$@"
SHIM
    chmod +x "$shim/perl"
    export DISTILL_LOCK_STALE_SECONDS=2
    "$SH" acquire alpha >/dev/null
    PATH="$shim:$PATH" "$SH" heartbeat alpha step:3 signals:1 >"$shim/hb.out" 2>&1 &
    h_pid=$!
    local waited=0
    while [ ! -e "$shim/paused" ]; do
        sleep 0.02; waited=$((waited + 1))
        if [ "$waited" -ge 500 ]; then
            touch "$shim/resume"; wait "$h_pid"
            FAIL=$((FAIL+1)); echo "  FAIL: delayed: the heartbeat never took the mutex (unguarded refresh)"
            unset DISTILL_LOCK_STALE_SECONDS; rm -rf "$store" "$shim"; return
        fi
    done
    sleep 2.5
    "$SH" acquire beta >/dev/null 2>&1; b_rc=$?
    check "delayed: after the lease expires another caller takes over (exit 0)" test "$b_rc" -eq 0
    touch "$shim/resume"; wait "$h_pid"; rc=$?
    check "delayed: the resumed heartbeat reports the loss (exit 3)" test "$rc" -eq 3
    check "delayed: ...and does not print ok" bash -c "! grep -qx ok '$shim/hb.out'"
    check "delayed: the new owner's line is intact" test "$(cut -d' ' -f1 "$store/.lock")" = "beta"
    check "delayed: the stale owner's checkpoint was not written" bash -c "! grep -q 'step:3' '$store/.status'"
    "$SH" release beta >/dev/null 2>&1; rc=$?
    check "delayed: the new owner can still release (exit 0)" test "$rc" -eq 0
    unset DISTILL_LOCK_STALE_SECONDS
    rm -rf "$store" "$shim"
}

# The mutex is an OS lock, so a holder that dies releases it at once and a mutex file left
# behind is harmless. Covers the third Codex review: with the old file mutex, two stale-mutex
# cleaners could each delete the other's fresh mutex and both take the lock over.
run_mutex_os_lock() {
    local store shim t_pid holder rc t0 i
    echo "-- sh: mutex is an OS lock (killed holder, leftover mutex file)"
    store=$(new_store); export DISTILL_DIR=$store

    # A leftover mutex file, old and with junk in it, blocks nobody and is not deleted.
    echo "junk from a crashed run" > "$store/.lock.takeover"; touch -t 200101010000 "$store/.lock.takeover"
    echo "dead 1000 2001-09-09T01:46:40Z" > "$store/.lock"
    for i in $(seq 1 8); do ( "$SH" acquire "v$i" >/dev/null 2>&1 && echo "v$i" >> "$store/won" ) & done; wait
    check "leftover mutex file: exactly one of 8 racers takes the stale lock over" test "$(wc -l < "$store/won" | tr -d ' ')" -eq 1
    check "leftover mutex file: it still exists (no cleaner deletes mutex files)" test -e "$store/.lock.takeover"
    "$SH" release "$(cat "$store/won")" >/dev/null

    # Freeze a takeover inside the mutex, then kill it: the next caller must not wait out a
    # stale-mutex timer, because the OS released the lock with the process.
    shim=$(mktemp -d)
    cat > "$shim/mv" <<SHIM
#!/usr/bin/env bash
if [ "\$1" = "-f" ] && [ "\${3:-}" = "$store/.lock" ]; then
    echo "\$PPID" > "$shim/holder"; touch "$shim/paused"
    while :; do sleep 0.05; done
fi
exec /bin/mv "\$@"
SHIM
    chmod +x "$shim/mv"
    echo "dead 1000 2001-09-09T01:46:40Z" > "$store/.lock"
    PATH="$shim:$PATH" "$SH" acquire victim >/dev/null 2>&1 &
    t_pid=$!
    for i in $(seq 1 250); do [ -e "$shim/paused" ] && break; sleep 0.02; done
    holder=$(cat "$shim/holder" 2>/dev/null)
    check "killed holder: the takeover froze inside the mutex" test -n "$holder"
    pkill -9 -P "$holder" 2>/dev/null; kill -9 "$holder" "$t_pid" 2>/dev/null; wait "$t_pid" 2>/dev/null
    t0=$SECONDS
    "$SH" acquire survivor >/dev/null 2>&1; rc=$?
    check "killed holder: the next caller takes the stale lock over (exit 0)" test "$rc" -eq 0
    check "killed holder: ...without waiting on a stale mutex (under 5 s)" test $(( SECONDS - t0 )) -lt 5
    check "killed holder: the survivor owns the lock" test "$(cut -d' ' -f1 "$store/.lock")" = "survivor"
    rm -rf "$store" "$shim"
}

echo "== bash implementation"
run_unit sh
run_io_failure sh
# The shim-driven interleavings exercise the bash primitives. On Windows the bash script hands
# over to the PowerShell one, so they do not apply there.
case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) echo "-- sh: deterministic interleavings SKIPPED on Windows (bash hands over to PowerShell)" ;;
    *) run_interleaving; run_delayed_heartbeat; run_mutex_os_lock ;;
esac
run_exclusion "sh: 4 concurrent distills" "sh" 4 0.4
run_exclusion "sh: 12 concurrent distills" "sh" 12 0.05
run_stale_race "sh: stale takeover race" sh 40 16

if [ -n "$PS_BIN" ]; then
    echo "== PowerShell implementation ($PS_BIN)"
    run_unit ps1
    run_io_failure ps1
    run_exclusion "ps1: 4 concurrent distills" "ps1" 4 0.4
    run_stale_race "ps1: stale takeover race" ps1 10 8
    echo "== mixed field (bash and PowerShell share one store)"
    run_exclusion "mixed: 6 concurrent distills" "sh ps1" 6 0.3
else
    echo "== PowerShell implementation: SKIPPED (no pwsh or powershell.exe on PATH)"
fi

echo
echo "lock tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
