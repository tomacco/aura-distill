"""Daily passive metering collector (subscription-metering research line).
Appends per-day token composition + limit events to CSV. Idempotent per day.
Local only. Run by scheduled task AuraDistill-MeteringCollector."""
import json, glob, os, sys, csv, re
from collections import defaultdict
from datetime import datetime, timedelta, timezone

PROJ = os.path.expanduser("~/.claude/projects")
OUT_DIR = os.path.dirname(os.path.abspath(__file__))
CSV_PATH = os.path.join(OUT_DIR, "metering-daily.csv")
LIMITS_PATH = os.path.join(OUT_DIR, "limit-events.log")

LIMIT_RX = re.compile(r"hit your (session|usage) limit[^.\n]*", re.I)

# yesterday (full day) unless --today
target = (datetime.now() - timedelta(days=1)).strftime("%Y-%m-%d")
if "--today" in sys.argv: target = datetime.now().strftime("%Y-%m-%d")

day = defaultdict(float)
seen_msg = set()
limits = []
for path in glob.glob(os.path.join(PROJ, "*", "*.jsonl")):
    # skip files not touched near the target date (cheap filter)
    if datetime.fromtimestamp(os.path.getmtime(path)).strftime("%Y-%m-%d") < target:
        continue
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if target not in line[:400] and '"timestamp"' in line[:400]:
                # fast path: timestamp early in record and not target day
                pass
            try: o = json.loads(line)
            except Exception: continue
            ts = (o.get("timestamp") or "")[:10]
            if ts != target: continue
            if o.get("type") == "assistant":
                msg = o.get("message") or {}
                mid = msg.get("id") or o.get("uuid")
                if mid in seen_msg: continue
                seen_msg.add(mid)
                if msg.get("model") == "<synthetic>": continue
                u = msg.get("usage") or {}
                cc = u.get("cache_creation") or {}
                day["fresh_in"] += u.get("input_tokens", 0)
                day["cache_read"] += u.get("cache_read_input_tokens", 0)
                day["cache_write"] += cc.get("ephemeral_1h_input_tokens", 0) + cc.get("ephemeral_5m_input_tokens", 0) or u.get("cache_creation_input_tokens", 0)
                day["output"] += u.get("output_tokens", 0)
                day["requests"] += 1
                day["m_" + (msg.get("model") or "?").replace(",", "_")] += u.get("output_tokens", 0)
            elif o.get("type") == "user":
                content = (o.get("message") or {}).get("content")
                txt = content if isinstance(content, str) else json.dumps(content)[:2000] if content else ""
                m = LIMIT_RX.search(txt or "")
                if m:
                    limits.append(f"{o.get('timestamp','?')}  {m.group(0)[:120]}")

# idempotency: skip if day already recorded
rows = []
if os.path.exists(CSV_PATH):
    rows = list(csv.reader(open(CSV_PATH, encoding="utf-8")))
    if any(r and r[0] == target for r in rows[1:]):
        print(f"{target} already recorded"); sys.exit(0)

new = not rows
with open(CSV_PATH, "a", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    if new: w.writerow(["date", "requests", "fresh_in", "cache_read", "cache_write", "output", "model_output_json"])
    models = {k[2:]: int(v) for k, v in day.items() if k.startswith("m_")}
    w.writerow([target, int(day["requests"]), int(day["fresh_in"]), int(day["cache_read"]),
                int(day["cache_write"]), int(day["output"]), json.dumps(models)])
if limits:
    with open(LIMITS_PATH, "a", encoding="utf-8") as f:
        for l in limits: f.write(l + "\n")
print(f"{target}: reqs={int(day['requests'])} cr={int(day['cache_read'])} out={int(day['output'])} limits={len(limits)}")
