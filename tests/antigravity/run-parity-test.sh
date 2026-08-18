#!/usr/bin/env bash
# Antigravity Time Index test: semantic assertions on distill-recent-agy.sh
# output, plus byte-parity between the bash and PowerShell implementations
# when a PowerShell host is available (pattern: tests/timeline/run-parity-test.sh).
#
# NOW is frozen at 2026-08-18T12:00:00Z (Tuesday). Fixture timestamps sit at
# 10:00-10:30 UTC, so bucket membership is stable for any host timezone in
# UTC-9..UTC+11. Assertions avoid HH:MM (timezone-dependent).
#
# Never touches a real Antigravity profile: --brain-dir points at a temp fixture.
set -euo pipefail
cd "$(dirname "$0")"

NOW_MS=1787054400000
SH=../../bin/distill-recent-agy.sh
PS1=../../bin/distill-recent-agy.ps1
PASS=0; FAIL=0

check() { # check <desc> <cmd...>
    local desc=$1; shift
    if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok: $desc"
    else FAIL=$((FAIL+1)); echo "  FAIL: $desc"; fi
}

FIX=$(mktemp -d)
trap 'rm -rf "$FIX"' EXIT

mk() { mkdir -p "$FIX/$1/.system_generated/logs"; }

# 1. Happy path: XML-tag stripping, left-off truncation at 90, first prompt wins
mk sess-happy-alpha-0001
{
    printf '%s\n' '{"step_index":0,"type":"USER_INPUT","created_at":"2026-08-18T10:00:00Z","content":"<USER_REQUEST>\nRefactor the caching engine\n</USER_REQUEST>"}'
    printf '%s\n' '{"step_index":1,"type":"PLANNER_RESPONSE","created_at":"2026-08-18T10:05:00Z","content":"Caching engine refactored: invalidation unified, hit rate instrumented, and twelve regression tests added across both storage backends."}'
    printf '%s\n' '{"step_index":2,"type":"USER_INPUT","created_at":"2026-08-18T10:06:00Z","content":"thanks"}'
} > "$FIX/sess-happy-alpha-0001/.system_generated/logs/transcript.jsonl"

# 2. Yesterday: prompt truncation at 85
mk sess-yesterday-b2
{
    printf '%s\n' '{"step_index":0,"type":"USER_INPUT","created_at":"2026-08-17T10:00:00Z","content":"migrate the payments api to the new gateway and update all retry policies for the async workers and refresh the docs"}'
    printf '%s\n' '{"step_index":1,"type":"PLANNER_RESPONSE","created_at":"2026-08-17T10:10:00Z","content":"Migration plan drafted."}'
} > "$FIX/sess-yesterday-b2/.system_generated/logs/transcript.jsonl"

# 3. Last week + hostile lines: malformed JSON, valid-JSON non-objects,
#    missing created_at (field skipped, record KEPT), out-of-range and
#    garbage timestamps (field skipped, content kept), non-string content
mk sess-lastweek-c3
{
    printf '%s\n' '{broken'
    printf '%s\n' '42'
    printf '%s\n' 'null'
    printf '%s\n' '"scalar"'
    printf '%s\n' '[1,2]'
    printf '%s\n' '{"step_index":5,"type":"USER_INPUT","content":"find the flaky retry test"}'
    printf '%s\n' '{"step_index":6,"type":"TOOL_CALL","created_at":"not-a-date","content":55}'
    printf '%s\n' '{"step_index":7,"type":"PLANNER_RESPONSE","created_at":"2026-08-13T10:30:00Z","content":"Root cause found in the retry harness."}'
    printf '%s\n' '{"step_index":8,"type":"PLANNER_RESPONSE","created_at":"9999-12-31T23:59:59Z","content":"Range guard survived; timestamp skipped, content kept."}'
} > "$FIX/sess-lastweek-c3/.system_generated/logs/transcript.jsonl"

# 4. Short session id (<8 chars) + calendar-month bucket
mk s7
printf '%s\n' '{"step_index":0,"type":"USER_INPUT","created_at":"2026-01-15T10:00:00Z","content":"q1 architecture review for the ingestion pipeline"}' \
    > "$FIX/s7/.system_generated/logs/transcript.jsonl"

# 5. No created_at anywhere -> dir-mtime fallback (mtime >= frozen NOW -> TODAY),
#    no USER_INPUT -> placeholder prompt
mk sess-nots-e5
printf '%s\n' '{"step_index":0,"type":"PLANNER_RESPONSE","content":"Ended without timestamps."}' \
    > "$FIX/sess-nots-e5/.system_generated/logs/transcript.jsonl"

# 6. Session dir without a transcript -> ignored
mk sess-empty-dir

out=$(bash "$SH" --brain-dir "$FIX" --now-ms "$NOW_MS")

# Bucket headers present, in exactly this order
expected_order='## TODAY
## YESTERDAY
## LAST WEEK
## JANUARY 2026'
check "bucket headers in rank order" test "$(printf '%s\n' "$out" | grep '^## ')" = "$expected_order"

section() { printf '%s\n' "$out" | awk -v h="## $1" '$0==h{f=1;next} /^## /{f=0} f'; }

# Session id comes from the session dir, not .system_generated (regression)
check "session id from session dir"      grep -q '\[sess-hap\]' <<<"$out"
check "no .system_generated leakage"     test "$(grep -c 'system_g' <<<"$out")" = 0
check "short id shown, no crash"         grep -q '\[s7\] .* q1 architecture review' <<<"$out"

# Cleaning + truncation
check "XML tags stripped from prompt"    grep -q 'Refactor the caching engine' <<<"$(section 'TODAY')"
check "no raw XML tag in output"         test "$(grep -c 'USER_REQUEST' <<<"$out")" = 0
check "first prompt wins over later one" test "$(grep -c '\[sess-hap\].*thanks' <<<"$out")" = 0
lo_line=$(grep 'left off: Caching engine refactored' <<<"$out")
check "left off truncated to 90 + ..."   test "${#lo_line}" = 107
case "$lo_line" in *...) lo_ell=0 ;; *) lo_ell=1 ;; esac
check "truncated left off ends with ..." test "$lo_ell" = 0
yd_line=$(section 'YESTERDAY' | grep 'migrate the payments api')
case "$yd_line" in *...) yd_ell=0 ;; *) yd_ell=1 ;; esac
check "long prompt truncated with ..."   test "$yd_ell" = 0

# Hostile-line discipline (the twin contract)
check "ts-less USER_INPUT record kept"   grep -q 'find the flaky retry test' <<<"$(section 'LAST WEEK')"
check "out-of-range ts: content kept"    grep -q 'left off: Range guard survived' <<<"$(section 'LAST WEEK')"
check "out-of-range ts: bucket by valid ts" test "$(section 'LAST WEEK' | grep -c '^- ')" = 1
check "mtime fallback lands in TODAY"    grep -q '(No user input recorded)' <<<"$(section 'TODAY')"
check "TODAY has exactly 2 sessions"     test "$(section 'TODAY' | grep -c '^- ')" = 2
check "empty session dir ignored"        test "$(grep -c 'sess-emp' <<<"$out")" = 0

# Newest-first inside a bucket (mtime session is newer than the frozen NOW)
check "newest first within bucket"       test "$(section 'TODAY' | head -1 | grep -c 'No user input recorded')" = 1

# Per-bucket cap
out2=$(bash "$SH" --brain-dir "$FIX" --now-ms "$NOW_MS" --per-bucket 1)
today2=$(printf '%s\n' "$out2" | awk '$0=="## TODAY"{f=1;next} /^## /{f=0} f')
check "per-bucket cap enforced"          test "$(printf '%s\n' "$today2" | grep -c '^- ')" = 1

# Positional BRAIN_DIR still accepted (compat with the flag-less call form)
out3=$(bash "$SH" "$FIX" --now-ms "$NOW_MS")
check "positional brain dir accepted"    grep -q '\[sess-hap\]' <<<"$out3"

# Missing brain dir -> stderr + exit 2
rc=0; bash "$SH" --brain-dir "$FIX/does-not-exist" --now-ms "$NOW_MS" >/dev/null 2>&1 || rc=$?
check "missing brain dir exits 2"        test "$rc" = 2

# Brain dir with no transcripts -> friendly message, exit 0
tmp2=$(mktemp -d)
rc=0; out4=$(bash "$SH" --brain-dir "$tmp2" --now-ms "$NOW_MS") || rc=$?
rmdir "$tmp2"
check "no transcripts exits 0"           test "$rc" = 0
check "no transcripts message"           grep -q 'No Antigravity transcripts found.' <<<"$out4"

# Byte parity with the PowerShell implementation (skipped if no PS host)
PS_BIN=""
command -v pwsh >/dev/null 2>&1 && PS_BIN=pwsh
[ -z "$PS_BIN" ] && command -v powershell.exe >/dev/null 2>&1 && PS_BIN=powershell.exe
if [ -n "$PS_BIN" ]; then
    ps_out=$("$PS_BIN" -NoProfile -ExecutionPolicy Bypass -File "$PS1" -BrainDir "$FIX" -NowMs "$NOW_MS")
    if diff --strip-trailing-cr <(printf '%s\n' "$out") <(printf '%s\n' "$ps_out") >/dev/null 2>&1; then
        PASS=$((PASS+1)); echo "  ok: bash/PowerShell byte parity ($PS_BIN)"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: bash/PowerShell outputs differ ($PS_BIN):"
        diff --strip-trailing-cr <(printf '%s\n' "$out") <(printf '%s\n' "$ps_out") | head -20 || true
    fi
    ps_out2=$("$PS_BIN" -NoProfile -ExecutionPolicy Bypass -File "$PS1" -BrainDir "$FIX" -NowMs "$NOW_MS" -PerBucket 1)
    if diff --strip-trailing-cr <(printf '%s\n' "$out2") <(printf '%s\n' "$ps_out2") >/dev/null 2>&1; then
        PASS=$((PASS+1)); echo "  ok: per-bucket byte parity ($PS_BIN)"
    else
        FAIL=$((FAIL+1)); echo "  FAIL: per-bucket outputs differ ($PS_BIN):"
        diff --strip-trailing-cr <(printf '%s\n' "$out2") <(printf '%s\n' "$ps_out2") | head -20 || true
    fi
else
    echo "  skip: no PowerShell host found (parity not checked)"
fi

echo
echo "antigravity time-index tests: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
