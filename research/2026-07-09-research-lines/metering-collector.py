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

# --- E-B retrieval-compliance (per-session, contamination-safe: counts actual
# Read tool_use calls on distill paths, never text mentions) ---
import re as _re
DISTILL_READ_RX = _re.compile(r"[/\\][.]claude[/\\]distill[/\\]")
SPINE_RX = _re.compile(r"[/\\][.]claude[/\\]distill[/\\]SPINE[.]md")
compliance = {}  # sid -> {first_ts, spine_read, kb_reads}
for path in glob.glob(os.path.join(PROJ, "*", "*.jsonl")):
    if datetime.fromtimestamp(os.path.getmtime(path)).strftime("%Y-%m-%d") < target:
        continue
    sid = os.path.basename(path)[:-6][:8]
    proj = os.path.basename(os.path.dirname(path))
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            try: o = json.loads(line)
            except Exception: continue
            ts = (o.get("timestamp") or "")[:10]
            if ts != target: continue
            c = compliance.setdefault(sid, {"proj": proj, "spine_read": False,
                                            "kb_reads": 0, "reqs": 0, "user_prompts": 0})
            if o.get("type") == "user" and not o.get("isMeta"):
                mc = (o.get("message") or {}).get("content")
                if isinstance(mc, str) and mc.strip():
                    c["user_prompts"] += 1
                elif isinstance(mc, list) and any(isinstance(b, dict) and b.get("type") == "text" and b.get("text", "").strip() for b in mc):
                    c["user_prompts"] += 1
            if o.get("type") != "assistant": continue
            c["reqs"] += 1
            for b in (o.get("message") or {}).get("content") or []:
                if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") == "Read":
                    fp = str((b.get("input") or {}).get("file_path", ""))
                    if SPINE_RX.search(fp): c["spine_read"] = True
                    elif DISTILL_READ_RX.search(fp): c["kb_reads"] += 1
COMP_PATH = os.path.join(OUT_DIR, "compliance-daily.csv")
comp_new = not os.path.exists(COMP_PATH)
with open(COMP_PATH, "a", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    if comp_new: w.writerow(["date", "session8", "project", "requests", "user_prompts",
                             "spine_read", "kb_file_reads"])
    # analysis note: headless experiment cells show user_prompts<=1 and tiny request
    # counts — filter on user_prompts>=2 for real-session compliance rates
    for sid, c in sorted(compliance.items()):
        w.writerow([target, sid, c["proj"], c["reqs"], c["user_prompts"],
                    int(c["spine_read"]), c["kb_reads"]])

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
