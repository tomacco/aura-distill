#!/usr/bin/env python3
"""E3 — extract real USER turns (text only) from the Claude Code transcripts on this Mac.
Output: e3/turns.jsonl {sid, idx, ts, text}. Excludes tool results, hook injections, slash-command
expansions and the current session's own jev cells. PII stays local: this file is gitignored."""
import glob, json, os, re, sys
from pathlib import Path
rows = []
for f in sorted(glob.glob(os.path.expanduser("~/.claude/projects/*/*.jsonl"))):
    if "jev-cells" in f: continue
    sid = os.path.basename(f)[:8]; i = 0
    for line in open(f):
        try: d = json.loads(line)
        except: continue
        if d.get("type") != "user": continue
        c = d.get("message", {}).get("content")
        if isinstance(c, list):
            if any(isinstance(x, dict) and x.get("type") == "tool_result" for x in c): continue
            c = " ".join(x.get("text", "") for x in c if isinstance(x, dict) and x.get("type") == "text")
        if not isinstance(c, str): continue
        t = re.sub(r"<pasted_content[^>]*>.*?</pasted_content[^>]*>", "[pasted]", c, flags=re.S)
        t = re.sub(r"<[a-z_\-]+[^>]*>.*?</[a-z_\-]+>", "", t, flags=re.S).strip()
        if not t or t.startswith("<") or t.startswith("# ") or len(t) < 3: continue
        rows.append({"sid": sid, "idx": i, "ts": d.get("timestamp"), "text": t[:1500]}); i += 1
Path("e3").mkdir(exist_ok=True)
Path("e3/turns.jsonl").write_text("\n".join(json.dumps(r, ensure_ascii=False) for r in rows) + "\n")
print(len(rows), "user turns from", len({r['sid'] for r in rows}), "sessions")
