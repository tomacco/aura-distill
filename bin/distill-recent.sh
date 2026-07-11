#!/usr/bin/env bash
# distill-recent -- aura-distill Time Index ("When" axis), derived view.
#
# Aggregates ~/.claude/history.jsonl (already written by Claude Code -- no new
# write path) into sessions, grouped on a human mental timeline. Bucket
# boundaries follow the temporal-memory literature (telescoping, Weber-Fechner
# compression, 5+2 weekday cycle, prototype heaping at 7/14/30/60/90 days) --
# see research/2026-07-11-time-index/mental-timelines.md.
#
# Usage: distill-recent.sh [--home DIR] [--now-ms EPOCH_MS] [--per-bucket N]
#   --home       Claude config dir (default: $CLAUDE_CONFIG_DIR or ~/.claude)
#   --now-ms     Freeze "now" for tests (also env DISTILL_NOW_MS)
#   --per-bucket Max sessions listed per bucket (default 8; overflow is counted,
#                never silently dropped)
#
# Exit codes: 0 ok, 2 history.jsonl not found, 3 no usable python.
# Windows PowerShell users: use distill-recent.ps1 (same output, native).
set -euo pipefail

PY=""
for c in python3 python; do
    # -c probe filters out the Windows Store python stub, which fails here
    if command -v "$c" >/dev/null 2>&1 && "$c" -c "import sys" >/dev/null 2>&1; then
        PY="$c"; break
    fi
done
if [ -z "$PY" ]; then
    echo "distill-recent: no working python3/python on PATH (on Windows use bin/distill-recent.ps1)" >&2
    exit 3
fi

exec "$PY" - "$@" <<'PYEOF'
import json, os, sys, argparse, time
from datetime import datetime, timedelta

# Locale-independent names: output must be byte-identical to distill-recent.ps1
WD = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
MONTH_FULL = ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE", "JULY",
              "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"]

def fmt_dt(d):
    return f"{WD[d.weekday()]} {d.day:02d} {MON[d.month - 1]} {d:%H:%M}"

def monday(d):
    return d.date() - timedelta(days=d.weekday())

def clean(s):
    s = "".join(ch if ch >= " " else " " for ch in s)
    return " ".join(s.split())

def snippet(prompts, limit=100):
    pick = next((p for p in prompts if len(p) > 25), next((p for p in prompts if p), ""))
    return pick[:limit] + "..." if len(pick) > limit else pick

def bucket_key(end, now):
    """Return (sort_rank, label). Boundaries: day-precision 0-1d, week-precision
    to ~3wk (5+2 weekday cycle), month-precision to ~6mo, then calendar months."""
    days = (now.date() - end.date()).days
    if days <= 0:
        return (0, "TODAY")
    if days == 1:
        return (1, "YESTERDAY")
    wk = (monday(now) - monday(end)).days // 7
    if wk == 0:
        return (2, "EARLIER THIS WEEK")
    if wk == 1:
        return (3, "LAST WEEK")
    if wk <= 3:
        return (4, "A FEW WEEKS AGO (2-3 wk)")
    if wk <= 7:
        return (5, "ABOUT A MONTH AGO (4-7 wk)")
    if days <= 104:
        return (6, "A COUPLE OF MONTHS AGO (2-3 mo)")
    if days <= 182:
        return (7, "A FEW MONTHS AGO (3-6 mo)")
    # beyond ~6 months only period-level precision survives: calendar months
    rank = 8 + (now.year * 12 + now.month) - (end.year * 12 + end.month)
    return (rank, f"{MONTH_FULL[end.month - 1]} {end.year}")

def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    ap = argparse.ArgumentParser(prog="distill-recent")
    ap.add_argument("--home", default=None)
    ap.add_argument("--now-ms", type=int, default=None)
    ap.add_argument("--per-bucket", type=int, default=8)
    args = ap.parse_args()

    home = args.home or os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")
    hist = os.path.join(home, "history.jsonl")
    if not os.path.isfile(hist):
        print(f"distill-recent: {hist} not found -- is this the right Claude config dir? (--home DIR)", file=sys.stderr)
        sys.exit(2)

    now_ms = args.now_ms or int(os.environ.get("DISTILL_NOW_MS") or 0) or int(time.time() * 1000)
    now = datetime.fromtimestamp(now_ms / 1000)

    sessions = {}
    with open(hist, encoding="utf-8", errors="replace") as f:
        for line in f:
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            sid, ts = d.get("sessionId"), d.get("timestamp")
            if not sid or not isinstance(ts, (int, float)):
                continue
            t = datetime.fromtimestamp(ts / 1000)
            s = sessions.setdefault(sid, {"start": t, "end": t, "project": d.get("project") or "", "prompts": []})
            s["start"] = min(s["start"], t)
            s["end"] = max(s["end"], t)
            s["prompts"].append(clean(d.get("display") or ""))

    home_leaf = os.path.basename(os.path.normpath(os.path.expanduser("~")))
    buckets = {}
    for sid, s in sessions.items():
        buckets.setdefault(bucket_key(s["end"], now), []).append((s["end"], sid, s))

    print(f"DISTILL TIME INDEX -- {len(sessions)} sessions (newest first)")
    print(f"NOW: {fmt_dt(now)}")
    for key in sorted(buckets):
        entries = sorted(buckets[key], key=lambda e: (e[0], e[1]), reverse=True)
        print(f"\n== {key[1]} ==")
        for end, sid, s in entries[: args.per_bucket]:
            leaf = os.path.basename(os.path.normpath(s["project"])) if s["project"] else ""
            proj = "" if (not leaf or leaf == home_leaf) else f"[{leaf}] "
            print(f"  {fmt_dt(end)} · {len(s['prompts']):>3} msgs · {sid[:8]} · {proj}{snippet(s['prompts'])}")
        extra = len(entries) - args.per_bucket
        if extra > 0:
            print(f"  ... +{extra} more sessions in this bucket")
    print(f"\nTranscript: {home}{os.sep}projects{os.sep}<project-dir>{os.sep}<session-id>.jsonl -- resume: claude --resume <session-id>")

main()
PYEOF
