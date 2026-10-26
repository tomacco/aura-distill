#!/bin/bash
# Asserts the outcome of the stale-session test (#140).
# Usage: check.sh <store> <report-file> [run-date YYYY-MM-DD, default today UTC]
set -uo pipefail

STORE="${1:?usage: check.sh <store> <report-file> [run-date]}"
REPORT="${2:?usage: check.sh <store> <report-file> [run-date]}"
RUN_DATE="${3:-$(date -u +%Y-%m-%d)}"
CARD="$STORE/craft/engineering.md"
case "$RUN_DATE" in 2026-10-01|2026-10-10|2026-10-12) echo "check.sh: run date $RUN_DATE is a fixture date; pass another as the third argument" >&2; exit 2 ;; esac
fail=0
check() { local name="$1"; shift; if "$@"; then echo "PASS  $name"; else echo "FAIL  $name"; fail=1; fi; }

check "newer branch rule survives unchanged" grep -qF -- "- [UPDATED 2026-10-10] Name branches \`feat/<ticket>-<slug>\`." "$CARD"
check "branch rule is not deprecated or corrected" bash -c '! awk "/^## Branches/{f=1;next} /^## /{f=0} f" "$0" | grep -qE "\[(DEPRECATED|CORRECTED)\]"' "$CARD"
check "stale initials-prefix signal is not encoded as current" bash -c '! awk "/^## Branches/{f=1;next} /^## /{f=0} f" "$0" | grep -qiE "^- .*(initials|no ticket|ig/)"' "$CARD"
check "newer formatting correction is applied" bash -c 'awk "/^## Formatting/{f=1;next} /^## /{f=0} f" "$0" | grep -qi "spaces"' "$CARD"
check "formatting change is dated by said_at (2026-10-12)" bash -c 'awk "/^## Formatting/{f=1;next} /^## /{f=0} f" "$0" | grep -q "2026-10-12"' "$CARD"
check "run date ($RUN_DATE) is not written into the card" bash -c '! grep -q "$1" "$0"' "$CARD" "$RUN_DATE"
check "report lists stale signals held back" grep -qi "stale signals held back" "$REPORT"
check "report names the 2026-10-05 signal" grep -q "2026-10-05" "$REPORT"

exit $fail
