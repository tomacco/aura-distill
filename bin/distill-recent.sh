#!/usr/bin/env bash
# distill-recent -- aura-distill Time Index ("When" axis), derived view.
#
# Aggregates ~/.claude/history.jsonl (already written by Claude Code -- no new
# write path) into sessions, grouped on a human mental timeline. Bucket
# boundaries follow the temporal-memory literature (telescoping, Weber-Fechner
# compression, 5+2 weekday cycle, prototype heaping at 7/14/30/60/90 days) --
# see research/2026-07-11-time-index/mental-timelines.md.
#
# Each listed session also gets a "left off:" line (last assistant text from
# its transcript tail -- the status axis of a continue-where-we-left-off
# query), and the header gets a "LAST /distill:" staleness line (SPINE
# last_updated vs sessions since). Both derived, best-effort, read-only.
#
# Usage: distill-recent.sh [--home DIR] [--now-ms EPOCH_MS] [--per-bucket N]
#   --home       Claude config dir (default: $CLAUDE_CONFIG_DIR or ~/.claude)
#   --now-ms     Freeze "now" for tests (also env DISTILL_NOW_MS)
#   --per-bucket Max sessions listed per bucket (default 8; overflow is counted,
#                never silently dropped)
#
# Exit codes: 0 ok, 2 history.jsonl not found, 3 no usable python,
#             4 history.jsonl present but no line matched the expected schema
#               (upstream format may have changed -- fall back to transcripts).
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
import json, os, re, sys, argparse, time
from datetime import datetime, timedelta

# Tail window for "left off:" extraction. Big enough to skip past trailing
# tool-result records (100KB+ observed) and still find the last assistant text.
TAIL_BYTES = 262144

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

def left_off(home, sid, project):
    """Last assistant text of the session transcript -- how the session ENDED
    (the status half of a "continue where we left off" query; the snippet only
    shows how it STARTED). Same transcript-dir munging as Claude Code:
    every non-alphanumeric cwd char becomes '-'."""
    if not project:
        return ""
    path = os.path.join(home, "projects", re.sub(r"[^A-Za-z0-9]", "-", project), sid + ".jsonl")
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as f:
            if size > TAIL_BYTES:
                f.seek(size - TAIL_BYTES)
            data = f.read()
    except OSError:
        return ""  # transcript rotated/cleaned up -- the field is best-effort
    lines = data.decode("utf-8", errors="replace").split("\n")
    if size > TAIL_BYTES:
        lines = lines[1:]  # first line of a mid-file window is cut mid-record
    for line in reversed(lines):
        # cheap pre-filter before JSON-parsing potentially huge tool-result lines
        if '"type":"assistant"' not in line:
            continue
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(d, dict) or d.get("type") != "assistant":
            continue
        msg = d.get("message")
        c = msg.get("content") if isinstance(msg, dict) else None
        if isinstance(c, str):
            t = clean(c)
        elif isinstance(c, list):
            t = clean(" ".join(x.get("text") or "" for x in c
                               if isinstance(x, dict) and x.get("type") == "text"))
        else:
            continue
        if t:  # tool-use-only records fall through to the previous text
            return t[:150] + "..." if len(t) > 150 else t
    return ""

def last_distill_date(home):
    """last_updated stamp from the SPINE -- /distill rewrites it on every run,
    so it doubles as a capture-lag marker for the staleness header."""
    try:
        with open(os.path.join(home, "distill", "SPINE.md"), encoding="utf-8", errors="replace") as f:
            m = re.search(r"last_updated:\s*(\d{4}-\d{2}-\d{2})", f.read())
    except OSError:
        return None
    return m.group(1) if m else None

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
    lines_seen = 0
    with open(hist, encoding="utf-8", errors="replace") as f:
        for line in f:
            if not line.strip():
                continue
            lines_seen += 1
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            # valid JSON that isn't an object (null, 42, "str", [..]) must be
            # skipped, not crash: this file is owned by Claude Code, not us
            if not isinstance(d, dict):
                continue
            sid, ts = d.get("sessionId"), d.get("timestamp")
            if not sid or isinstance(ts, bool) or not isinstance(ts, (int, float)):
                continue
            t = datetime.fromtimestamp(ts / 1000)
            s = sessions.setdefault(sid, {"start": t, "end": t, "project": d.get("project") or "", "prompts": []})
            s["start"] = min(s["start"], t)
            s["end"] = max(s["end"], t)
            s["prompts"].append(clean(d.get("display") or ""))

    if lines_seen and not sessions:
        # Loud failure beats silently-wrong: an empty index here means the
        # upstream schema changed, not that the user has no history.
        print(f"distill-recent: parsed {lines_seen} lines but recognized 0 sessions -- "
              "history.jsonl format may have changed (expected objects with "
              "display/timestamp/project/sessionId). Fall back to raw transcripts.", file=sys.stderr)
        sys.exit(4)

    home_leaf = os.path.basename(os.path.normpath(os.path.expanduser("~")))
    buckets = {}
    for sid, s in sessions.items():
        buckets.setdefault(bucket_key(s["end"], now), []).append((s["end"], sid, s))

    print(f"DISTILL TIME INDEX -- {len(sessions)} sessions (newest first)")
    print(f"NOW: {fmt_dt(now)}")
    ld = last_distill_date(home)
    if ld:
        # strictly-after: same-day-as-distill sessions are ambiguous, undercount
        # rather than cry wolf
        d0 = datetime.strptime(ld, "%Y-%m-%d").date()
        n = sum(1 for s in sessions.values() if s["end"].date() > d0)
        print(f"LAST /distill: {ld} -- {n} undistilled {'session' if n == 1 else 'sessions'} since")
    for key in sorted(buckets):
        entries = sorted(buckets[key], key=lambda e: (e[0], e[1]), reverse=True)
        print(f"\n== {key[1]} ==")
        for end, sid, s in entries[: args.per_bucket]:
            leaf = os.path.basename(os.path.normpath(s["project"])) if s["project"] else ""
            proj = "" if (not leaf or leaf == home_leaf) else f"[{leaf}] "
            print(f"  {fmt_dt(end)} · {len(s['prompts']):>3} msgs · {sid[:8]} · {proj}{snippet(s['prompts'])}")
            lo = left_off(home, sid, s["project"])
            if lo:
                print(f"      left off: {lo}")
        extra = len(entries) - args.per_bucket
        if extra > 0:
            print(f"  ... +{extra} more sessions in this bucket")
    print(f"\nTranscript: {home}{os.sep}projects{os.sep}<project-dir>{os.sep}<session-id>.jsonl -- resume: claude --resume <session-id>")

main()
PYEOF
