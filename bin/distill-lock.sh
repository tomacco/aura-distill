#!/usr/bin/env bash
# distill-lock -- owner-checked mutual exclusion for distillation runs that share one store.
#
# The lock is the file {DISTILL_DIR}/.lock holding one line: "<owner> <epoch-seconds> <iso-utc>".
# It is created with link(2), which fails if the name exists, so exactly one caller wins and
# the line is complete the moment it is visible. Only the owner can refresh or release it.
# A lock whose heartbeat is older than DISTILL_LOCK_STALE_SECONDS (default 300) can be taken
# over. Takeovers, heartbeats and releases run under a mutex: an OS advisory lock (flock(2),
# taken through perl) on the persistent file {DISTILL_DIR}/.lock.takeover. Under it they re-check
# the lock line and replace the lock with an atomic rename, so the lock file never goes missing
# while someone else could create it. The OS drops the mutex when its holder exits or crashes,
# so there is no stale mutex to clean up. On Windows (Git Bash, MSYS, Cygwin) this script hands
# over to bin/distill-lock.ps1, so one lock primitive guards a store there.
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

case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*)
        ps_bin=$(command -v pwsh || command -v powershell.exe || command -v powershell) \
            || { echo "error: distill-lock needs PowerShell on Windows"; exit 4; }
        ps1="$(dirname "$0")/distill-lock.ps1"
        command -v cygpath >/dev/null 2>&1 && ps1=$(cygpath -w "$ps1")
        [ -n "${DISTILL_DIR:-}" ] && command -v cygpath >/dev/null 2>&1 && DISTILL_DIR=$(cygpath -w "$DISTILL_DIR") && export DISTILL_DIR
        exec "$ps_bin" -NoProfile -ExecutionPolicy Bypass -File "$ps1" "$@" ;;
esac

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

# Runs `this-script __locked <op> <args>` while holding the takeover mutex. perl takes an
# exclusive flock(2) on the persistent mutex file (waiting at most 10 seconds), clears
# close-on-exec on it, and execs the op, so the process doing the work holds the lock and
# the OS releases it when that process exits, however it exits. The file is never deleted.
# Returns the op's code, 1 if the mutex stayed contended, 4 if it could not be opened.
with_mutex() {
    command -v perl >/dev/null 2>&1 || { echo "error: distill-lock needs perl" >&2; return 4; }
    perl -e '
        use Fcntl qw(:flock F_SETFD);
        my ($m, @cmd) = @ARGV;
        open(my $f, ">>", $m) or exit 4;
        my $end = time + 10;
        until (flock($f, LOCK_EX | LOCK_NB)) { exit 1 if time >= $end; select(undef, undef, undef, 0.05); }
        fcntl($f, F_SETFD, 0) or exit 4;
        exec { $cmd[0] } @cmd or exit 4;
    ' "$MUTEX" bash "$0" __locked "$@"
}

# Ops that run only under the mutex (via with_mutex). Each re-reads the lock line first.
# replace <expected-owner> <expected-epoch> <owner>: 0 replaced, 1 the lock changed, 4 write failed.
op_replace() {
    local tmp
    [ "$(read_lock)" = "$1 $2" ] || return 1
    tmp=$(tmpname swap)
    if printf '%s %s %s\n' "$3" "$(now)" "$(iso)" > "$tmp" && mv -f "$tmp" "$LOCK"; then return 0; fi
    rm -f "$tmp"; return 4
}
# remove <expected-owner> <expected-epoch>: 0 removed, 1 the lock changed, 4 remove failed.
op_remove() {
    [ "$(read_lock)" = "$1 $2" ] || return 1
    rm -f "$LOCK" 2>/dev/null || return 4
    [ ! -e "$LOCK" ] || return 4
}

# If the lock still reads <expected> ("<owner> <epoch>"), atomically replace it with a fresh
# line for <owner>. Returns 0 replaced, 1 the lock changed or the mutex stayed contended,
# 4 a write failed.
replace_if() { set -- $1 "$2"; with_mutex replace "$1" "$2" "$3"; }

# Remove the lock if <owner> holds it. Used when a fresh acquire cannot record itself, so a
# half-acquired lock never blocks the store.
drop_if_owner() {
    local cur; cur=$(read_lock)
    set -- $cur "$1"
    [ "${1:-}" = "$3" ] && with_mutex remove "$1" "$2"
}

# The lock was just taken: record it in .status, or give it back and fail with exit 4.
acquired() {
    if write_status "running"; then echo "$2"; return 0; fi
    drop_if_owner "$1"; fail "lock taken but .status could not be written; lock released"
}

is_stale() { [ $(( $(now) - $1 )) -ge "$STALE" ]; }

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
    # Every refresh goes through the mutex and re-checks the line, so a heartbeat delayed
    # past the stale cutoff can never overwrite an owner that took over in the meantime.
    replace_if "$cur" "$owner"; rc=$?
    [ $rc -eq 4 ] && fail "cannot refresh the lock"
    [ $rc -ne 0 ] && { echo "lost: lock taken over or contended"; return 3; }
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
    with_mutex remove "$1" "$2"; rc=$?
    [ $rc -eq 4 ] && fail "cannot remove the lock"
    [ $rc -ne 0 ] && { echo "not owner: lock changed or contended during release"; return 3; }
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
    __locked)  shift; op="$1"; shift
               case "$op" in replace) op_replace "$@" ;; remove) op_remove "$@" ;; *) exit 2 ;; esac
               exit $? ;;
    acquire)   [ $# -ge 2 ] || usage; check_owner "$2"; shift; cmd_acquire "$@" ;;
    heartbeat) [ $# -ge 2 ] || usage; check_owner "$2"; shift; cmd_heartbeat "$@" ;;
    release)   [ $# -eq 2 ] || usage; check_owner "$2"; cmd_release "$2" ;;
    status)    cmd_status ;;
    *)         usage ;;
esac
