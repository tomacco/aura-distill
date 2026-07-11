#!/usr/bin/env bash
# Time Index test: semantic assertions on distill-recent.sh output, plus
# byte-parity between the bash and PowerShell implementations when a
# PowerShell is available on this machine.
#
# NOW is frozen at 2026-07-11T12:00:00Z (Saturday). Fixture timestamps sit at
# 10:00-11:00 UTC mid-week, so bucket membership is stable for any host
# timezone in UTC-10..UTC+13. Assertions avoid HH:MM (timezone-dependent).
#
# Never touches a real Claude profile: --home points at the fixture dir.
set -euo pipefail
cd "$(dirname "$0")"

NOW_MS=1783771200000
SH=../../bin/distill-recent.sh
PS1=../../bin/distill-recent.ps1
FIX=fixture
PASS=0; FAIL=0

check() { # check <desc> <cmd...>
    local desc=$1; shift
    if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok: $desc"
    else FAIL=$((FAIL+1)); echo "  FAIL: $desc"; fi
}

out=$(bash "$SH" --home "$FIX" --now-ms "$NOW_MS")

# 1. Bucket headers present, in exactly this order
expected_order='== TODAY ==
== YESTERDAY ==
== EARLIER THIS WEEK ==
== LAST WEEK ==
== A FEW WEEKS AGO (2-3 wk) ==
== ABOUT A MONTH AGO (4-7 wk) ==
== A COUPLE OF MONTHS AGO (2-3 mo) ==
== A FEW MONTHS AGO (3-6 mo) ==
== NOVEMBER 2025 =='
check "bucket headers in research order" test "$(printf '%s\n' "$out" | grep '^== ')" = "$expected_order"

# 2. Session lands in the right bucket (section-scoped grep)
section() { printf '%s\n' "$out" | awk -v h="== $1 ==" '$0==h{f=1;next} /^== /{f=0} f'; }
check "today session in TODAY"                 grep -q 'payments-api retry logic' <<<"$(section 'TODAY')"
check "spanning session bucketed by END (yesterday)" grep -q 'audit-log migration' <<<"$(section 'YESTERDAY')"
check "wed session in EARLIER THIS WEEK"       grep -q 'incident postmortem' <<<"$(section 'EARLIER THIS WEEK')"
check "last week bucket"                       grep -q 'grafana dashboard' <<<"$(section 'LAST WEEK')"
check "2wk + 3wk share A FEW WEEKS AGO"        test "$(section 'A FEW WEEKS AGO (2-3 wk)' | grep -c 'fraud-scoring\|terraform')" = 2
check "4wk in ABOUT A MONTH AGO"               grep -q 'postgres partitioning' <<<"$(section 'ABOUT A MONTH AGO (4-7 wk)')"
check "67d in A COUPLE OF MONTHS AGO"          grep -q 'feature flag providers' <<<"$(section 'A COUPLE OF MONTHS AGO (2-3 mo)')"
check "115d in A FEW MONTHS AGO"               grep -q 'temporal workflows' <<<"$(section 'A FEW MONTHS AGO (3-6 mo)')"
check "old session under calendar month"       grep -q 'q1 architecture review' <<<"$(section 'NOVEMBER 2025')"

# 3. Snippet picks first substantive prompt (skips "yes", "ok go")
check "snippet skips trivial openers" grep -q 'aaaa1111 · \[payments-api\] refactor the payments-api' <<<"$out"

# 4. Newest-first inside a bucket (span session ended 11:00Z > 10:00Z)
check "newest first within bucket" test "$(section 'YESTERDAY' | head -1 | grep -c 'audit-log')" = 1

# 5. Overflow is counted, never silently dropped
out2=$(bash "$SH" --home "$FIX" --now-ms "$NOW_MS" --per-bucket 1)
check "+N more line on overflow" grep -q '+1 more sessions in this bucket' <<<"$out2"

# 6. Malformed + sessionId-less lines skipped: total is 11 sessions
check "malformed lines skipped, 11 sessions" grep -q 'DISTILL TIME INDEX -- 11 sessions' <<<"$out"

# 7. Missing history.jsonl -> exit 2
tmp=$(mktemp -d)
rc=0; bash "$SH" --home "$tmp" --now-ms "$NOW_MS" >/dev/null 2>&1 || rc=$?
rmdir "$tmp"
check "missing history exits 2" test "$rc" = 2

# 8. Byte parity with the PowerShell implementation (skipped if no PS host)
PS_BIN=""
command -v pwsh >/dev/null 2>&1 && PS_BIN=pwsh
[ -z "$PS_BIN" ] && command -v powershell.exe >/dev/null 2>&1 && PS_BIN=powershell.exe
if [ -n "$PS_BIN" ]; then
    ps_out=$("$PS_BIN" -NoProfile -ExecutionPolicy Bypass -File "$PS1" -ClaudeHome "$FIX" -NowMs "$NOW_MS")
    if diff --strip-trailing-cr <(printf '%s\n' "$out") <(printf '%s\n' "$ps_out") >/dev/null 2>&1; then
        PASS=$((PASS+1)); echo "  ok: bash/PowerShell byte parity ($PS_BIN)"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: bash/PowerShell outputs differ ($PS_BIN):"
        diff --strip-trailing-cr <(printf '%s\n' "$out") <(printf '%s\n' "$ps_out") | head -20 || true
    fi
else
    echo "  skip: no PowerShell host found (parity not checked)"
fi

echo
echo "timeline tests: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
