#!/usr/bin/env bash
# distill-recent-agy -- aura-distill Time Index ("When" axis) for Antigravity (agy) sessions.
#
# Scans Antigravity brain transcripts
# (~/.gemini/antigravity-cli/brain/<conversation-id>/.system_generated/logs/transcript.jsonl)
# and buckets sessions on human mental timelines matching distill-recent conventions.
# Output is byte-identical to bin/distill-recent-agy.ps1 (parity enforced by
# tests/antigravity/run-parity-test.sh).
#
# Usage: distill-recent-agy.sh [BRAIN_DIR] [--brain-dir DIR] [--now-ms EPOCH_MS] [--per-bucket N]
# Exit codes: 0 ok (including no transcripts), 2 brain dir not found,
#             3 no usable python.
set -euo pipefail

PY=""
for c in python3 python; do
    # -c probe filters out the Windows Store python stub, which fails here
    if command -v "$c" >/dev/null 2>&1 && "$c" -c "import sys" >/dev/null 2>&1; then
        PY="$c"; break
    fi
done
if [ -z "$PY" ]; then
    echo "distill-recent-agy: no working python3/python on PATH (on Windows use bin/distill-recent-agy.ps1)" >&2
    exit 3
fi

exec "$PY" - "$@" <<'PYEOF'
import json, os, re, sys, argparse
from datetime import datetime, timedelta

# Locale-independent names: output must be byte-identical to distill-recent-agy.ps1
WD = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
MONTH_FULL = ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE", "JULY",
              "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"]

def fmt_dt(d):
    return f"{WD[d.weekday()]} {d.day:02d} {MON[d.month - 1]} {d:%H:%M}"

def monday(d):
    return d.date() - timedelta(days=d.weekday())

def clean(s):
    # Strip XML tags like <USER_REQUEST>, <ADDITIONAL_METADATA>, etc.
    s = re.sub(r"<[^>]+>", " ", s)
    s = re.sub(r"[\x00-\x1f]", " ", s)
    return " ".join(p for p in re.split(r"\s+", s) if p)

def bucket_key(end, now):
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
    rank = 8 + (now.year * 12 + now.month) - (end.year * 12 + end.month)
    return (rank, f"{MONTH_FULL[end.month - 1]} {end.year}")

def parse_ts(v):
    """created_at is written by Antigravity, not us: non-string, non-ISO, or
    out-of-range values skip the FIELD, never the record (twin contract)."""
    if not isinstance(v, str) or not v:
        return None
    t = v.strip()
    if t.endswith(("Z", "z")):
        t = t[:-1] + "+00:00"
    try:
        d = datetime.fromisoformat(t)
        if d.tzinfo is not None:
            d = d.astimezone().replace(tzinfo=None)
    except (ValueError, OverflowError, OSError):
        return None
    return d

def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    ap = argparse.ArgumentParser(prog="distill-recent-agy")
    ap.add_argument("brain_dir_pos", nargs="?", default=None)
    ap.add_argument("--brain-dir", default=None)
    ap.add_argument("--now-ms", type=int, default=None)
    ap.add_argument("--per-bucket", type=int, default=8)
    args = ap.parse_args()

    brain = args.brain_dir or args.brain_dir_pos or os.path.join(
        os.path.expanduser("~"), ".gemini", "antigravity-cli", "brain")
    if not os.path.isdir(brain):
        print(f"Antigravity brain directory not found at {brain}", file=sys.stderr)
        sys.exit(2)

    now = datetime.fromtimestamp(args.now_ms / 1000) if args.now_ms else datetime.now()

    sessions = []
    for name in sorted(os.listdir(brain)):
        d = os.path.join(brain, name)
        if not os.path.isdir(d):
            continue
        trans = os.path.join(d, ".system_generated", "logs", "transcript.jsonl")
        if not os.path.isfile(trans):
            continue

        # Fallback timeline when no step carries a parseable created_at
        try:
            mt = datetime.fromtimestamp(os.path.getmtime(d))
        except (OverflowError, OSError, ValueError):
            mt = now
        first_dt, last_dt, saw_ts = mt, mt, False
        first_prompt, last_assistant, turns = "", "", 0

        try:
            with open(trans, encoding="utf-8", errors="replace") as f:
                lines = f.readlines()
        except OSError:
            continue
        for line in lines:
            line = line.strip()
            if not line:
                continue
            # Malformed line or valid-JSON non-object (null, 42, "str", [..]):
            # skip the record, never crash -- this file is owned by Antigravity
            try:
                step = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(step, dict):
                continue
            turns += 1
            dt = parse_ts(step.get("created_at"))
            if dt is not None:
                if not saw_ts:
                    first_dt, saw_ts = dt, True
                last_dt = dt
            typ = step.get("type")
            content = step.get("content")
            if typ == "USER_INPUT" and not first_prompt and isinstance(content, str) and content:
                first_prompt = clean(content)
            if typ == "PLANNER_RESPONSE" and isinstance(content, str) and content:
                last_assistant = clean(content)

        if not first_prompt:
            first_prompt = "(No user input recorded)"
        if len(first_prompt) > 85:
            first_prompt = first_prompt[:85] + "..."
        if len(last_assistant) > 90:
            last_assistant = last_assistant[:90] + "..."

        sessions.append({"id": name, "start": first_dt, "end": last_dt,
                         "prompt": first_prompt, "left": last_assistant, "turns": turns})

    if not sessions:
        print("No Antigravity transcripts found.")
        sys.exit(0)

    # Sort descending by end time, id as deterministic tie-break (twin parity)
    sessions.sort(key=lambda s: (s["end"], s["id"]), reverse=True)

    groups, order = {}, []
    for s in sessions:
        label = bucket_key(s["end"], now)[1]
        if label not in groups:
            groups[label] = []
            order.append(label)
        if len(groups[label]) < args.per_bucket:
            groups[label].append(s)

    print("=== Antigravity Session Time Index ===")
    print()
    for label in order:
        print(f"## {label}")
        for s in groups[label]:
            sid = s["id"][:8] if len(s["id"]) > 8 else s["id"]
            print(f"- [{sid}] {fmt_dt(s['end'])} · {s['prompt']}")
            if s["left"]:
                print(f"    left off: {s['left']}")
        print()

main()
PYEOF
