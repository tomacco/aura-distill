#!/usr/bin/env bash
# distill-lock -- owner-checked mutual exclusion for distillation runs that share one store.
#
# The lock is the file {DISTILL_DIR}/.lock holding one line: "<owner> <epoch-seconds> <iso-utc>".
# It is created with link(2), which fails if the name exists, so exactly one caller wins and
# the line is complete the moment it is visible. Only the owner can refresh or release it.
# A lock whose heartbeat is older than DISTILL_LOCK_STALE_SECONDS (default 300) can be taken
# over. Takeovers, near-stale heartbeats and releases run under a short-lived second lock
# ({DISTILL_DIR}/.lock.takeover), re-check the lock line under it, and replace the lock with an
# atomic rename, so the lock file never goes missing while someone else could create it.
# .status keeps its existing human-readable forms for checkpoints.
# Same file format and semantics as bin/distill-lock.ps1 (parity: tests/lock/run-lock-tests.sh).
#
# Usage:
#   distill-lock.sh acquire   <owner> [--wait SECONDS]
#   distill-lock.sh heartbeat <owner> [step:N signals:M]
#   distill-lock.sh release   <owner>
#   distill-lock.sh status
# Exit codes: 0 ok, 1 held by another owner (after any --wait), 2 usage,
#             3 caller is not the owner (lock lost, stolen as stale, or never held),
#             4 I/O error (the lock or .status could not be written; treat the lock as lost).
set -u
set -f  # word-split lock lines without globbing

DIR="${DISTILL_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
LOCK="$DIR/.lock"
MUTEX="$DIR/.lock.takeover"
STATUS="$DIR/.status"
STALE="${DISTILL_LOCK_STALE_SECONDS:-300}"
POLL="${DISTILL_LOCK_POLL_SECONDS:-2}"

usage() { sed -n '/^# Usage:/,/^set -u/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; exit 2; }
fail() { echo "error: $1"; exit 4; }
now() { date -u +%s; }
iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
tmpname() { printf '%s.%s.%s.%s' "$LOCK" "$1" "$$" "$RANDOM$RANDOM"; }

# Prints "<owner> <epoch>" of the current lock, or nothing if there is none.
# An unreadable or malformed lock reads as owner "?" aged by its mtime, so it goes stale.
read_lock() {
    local line mtime
    [ -e "$LOCK" ] || return 0
    line=$(head -n 1 "$LOCK" 2>/dev/null)
    set -- $line
    case "${2:-}" in
        ''|*[!0-9]*) mtime=$(date -r "$LOCK" +%s 2>/dev/null) || return 0; printf '? %s\n' "$mtime" ;;
        *) printf '%s %s\n' "$1" "$2" ;;
    esac
}

write_status() {
    printf '%s %s\n' "$1" "$(iso)" > "$STATUS.tmp.$$" && mv -f "$STATUS.tmp.$$" "$STATUS" && return 0
    rm -f "$STATUS.tmp.$$"; return 1
}

# Returns 0 created, 1 the lock exists, 4 the temp file could not be written.
try_create() {
    local tmp; tmp=$(tmpname new)
    printf '%s %s %s\n' "$1" "$(now)" "$(iso)" > "$tmp" || { rm -f "$tmp"; return 4; }
    if ln "$tmp" "$LOCK" 2>/dev/null; then rm -f "$tmp"; return 0; fi
    rm -f "$tmp"; return 1
}

# The takeover mutex guards every change to an existing lock. It is held for milliseconds;
# one left by a crashed process is cleared after 30 seconds.
# Returns 0 held, 1 still contended after 10 seconds, 4 the temp file could not be written.
# The wait is wall-clock (a loop count runs long where forks are slow, such as Git Bash) and
# stays well under the 30 second cutoff, so a live holder is never cleared.
mutex_lock() {
    local tmp m deadline
    tmp=$(tmpname mx); echo "$$" > "$tmp" || { rm -f "$tmp"; return 4; }
    deadline=$(( $(now) + 10 ))
    while [ "$(now)" -lt "$deadline" ]; do
        if ln "$tmp" "$MUTEX" 2>/dev/null; then rm -f "$tmp"; return 0; fi
        m=$(date -r "$MUTEX" +%s 2>/dev/null) && [ $(( $(now) - m )) -ge 30 ] && rm -f "$MUTEX"
        sleep 0.05
    done
    rm -f "$tmp"; return 1
}
mutex_unlock() { rm -f "$MUTEX"; }

# Under the mutex: if the lock still reads <expected> ("<owner> <epoch>"), atomically replace
# it with a fresh line for <owner>. Returns 0 replaced, 1 the lock changed or the mutex stayed
# contended, 4 a write failed.
replace_if() {
    local expected="$1" owner="$2" tmp rc=1
    mutex_lock || return $?
    if [ "$(read_lock)" = "$expected" ]; then
        tmp=$(tmpname swap)
        if printf '%s %s %s\n' "$owner" "$(now)" "$(iso)" > "$tmp" && mv -f "$tmp" "$LOCK"; then rc=0; else rc=4; fi
        rm -f "$tmp"
    fi
    mutex_unlock; return $rc
}

# Under the mutex: remove the lock if <owner> holds it. Used when a fresh acquire cannot
# record itself, so a half-acquired lock never blocks the store.
drop_if_owner() {
    mutex_lock || return $?
    [ "$(read_lock | cut -d' ' -f1)" = "$1" ] && rm -f "$LOCK"
    mutex_unlock
}

# The lock was just taken: record it in .status, or give it back and fail with exit 4.
acquired() {
    if write_status "running"; then echo "$2"; return 0; fi
    drop_if_owner "$1"; fail "lock taken but .status could not be written; lock released"
}

is_stale() { [ $(( $(now) - $1 )) -ge "$STALE" ]; }
# Past half the stale window a waiter may be close to a takeover, so the owner refreshes
# through replace_if and never blindly overwrites.
near_stale() { [ $(( ($(now) - $1) * 2 )) -ge "$STALE" ]; }

check_owner() {
    case "$1" in
        ''|*[!A-Za-z0-9._:-]*) echo "distill-lock: owner must match [A-Za-z0-9._:-]+" >&2; exit 2 ;;
    esac
}

cmd_acquire() {
    local owner="$1" wait=0 deadline cur cur_owner="" cur_epoch="" rc out
    shift
    if [ $# -gt 0 ]; then
        [ "$1" = "--wait" ] && [ $# -eq 2 ] || usage
        wait="$2"; case "$wait" in ''|*[!0-9]*) usage ;; esac
    fi
    deadline=$(( $(now) + wait ))
    while :; do
        cur=$(read_lock)
        if [ -z "$cur" ]; then
            try_create "$owner"; rc=$?
            [ $rc -eq 0 ] && { acquired "$owner" "acquired"; return; }
            [ $rc -eq 4 ] && fail "cannot write in $DIR"
        else
            set -- $cur; cur_owner=$1; cur_epoch=$2
            if [ "$cur_owner" = "$owner" ]; then
                out=$(cmd_heartbeat "$owner"); rc=$?
                [ $rc -eq 0 ] && { echo "acquired (already held)"; return 0; }
                [ $rc -eq 4 ] && { echo "$out"; return 4; }
            elif is_stale "$cur_epoch"; then
                replace_if "$cur" "$owner"; rc=$?
                [ $rc -eq 0 ] && { acquired "$owner" "acquired (took over stale lock from $cur_owner)"; return; }
                [ $rc -eq 4 ] && fail "cannot write in $DIR"
            fi
        fi
        if [ "$(now)" -ge "$deadline" ]; then
            cur=$(read_lock)
            [ -n "$cur" ] && set -- $cur && echo "held $1 $(( $(now) - $2 ))s" || echo "held (contended)"
            return 1
        fi
        sleep "$POLL"
    done
}

cmd_heartbeat() {
    local owner="$1" cur tmp rc
    shift
    cur=$(read_lock)
    if [ -z "$cur" ]; then echo "lost: lock not held"; return 3; fi
    set -- $cur "$@"
    if [ "$1" != "$owner" ]; then echo "lost: held by $1"; return 3; fi
    if near_stale "$2"; then
        # A waiter may be taking this lock over right now. Refresh through the same
        # mutex-and-check path so we never overwrite a new owner's lock.
        replace_if "$cur" "$owner"; rc=$?
        [ $rc -eq 4 ] && fail "cannot refresh the lock"
        [ $rc -ne 0 ] && { echo "lost: stale lock taken over"; return 3; }
    else
        tmp=$(tmpname beat)
        printf '%s %s %s\n' "$owner" "$(now)" "$(iso)" > "$tmp" && mv -f "$tmp" "$LOCK" \
            || { rm -f "$tmp"; fail "cannot refresh the lock"; }
    fi
    shift 2
    if [ $# -gt 0 ]; then write_status "running $*" || fail "lock refreshed but the checkpoint could not be written"; fi
    echo "ok"; return 0
}

cmd_release() {
    local owner="$1" cur rc
    cur=$(read_lock)
    if [ -z "$cur" ]; then echo "not held"; return 3; fi
    set -- $cur
    if [ "$1" != "$owner" ]; then echo "not owner: held by $1"; return 3; fi
    mutex_lock; rc=$?
    [ $rc -eq 4 ] && fail "cannot write in $DIR"
    [ $rc -ne 0 ] && { echo "not owner: lock contended during release"; return 3; }
    if [ "$(read_lock)" != "$cur" ]; then mutex_unlock; echo "not owner: lock changed during release"; return 3; fi
    rm -f "$LOCK" 2>/dev/null || { mutex_unlock; fail "cannot remove the lock"; }
    mutex_unlock
    write_status "idle" || fail "lock released but .status could not be written"
    echo "released"; return 0
}

cmd_status() {
    local cur
    cur=$(read_lock)
    if [ -z "$cur" ]; then echo "free"; return 0; fi
    set -- $cur
    if is_stale "$2"; then echo "stale $1 $(( $(now) - $2 ))s"; else echo "held $1 $(( $(now) - $2 ))s"; fi
}

[ $# -ge 1 ] || usage
case "$1" in
    acquire)   [ $# -ge 2 ] || usage; check_owner "$2"; shift; cmd_acquire "$@" ;;
    heartbeat) [ $# -ge 2 ] || usage; check_owner "$2"; shift; cmd_heartbeat "$@" ;;
    release)   [ $# -eq 2 ] || usage; check_owner "$2"; cmd_release "$2" ;;
    status)    cmd_status ;;
    *)         usage ;;
esac
