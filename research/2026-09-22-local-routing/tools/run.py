#!/usr/bin/env python3
"""jev-distill-routing harness.

Measures how long a CLEAN Claude Code session takes to route a user query to the
right aura-distill knowledge file (read SPINE -> choose -> read file -> answer),
so the JEV (TypeSafe System One) routing arm can be compared against it.

Subcommands
  plan      print the exact cell command for a topic/arm, run nothing
  baseline  run N clean headless cells (arm A: agent reads SPINE and chooses)
  jev       run N cells with JEV pre-selecting the file (arm B)   [needs TYPESAFE_API_KEY]
  shortlist run N cells with a BM25 SHORTLIST injected instead of the SPINE (arm C, no model)
  report    tabulate a run directory

Every cell is a `claude -p` child with the REAL config dir (macOS keeps OAuth in the
Keychain, so a scratch CLAUDE_CONFIG_DIR cannot authenticate). Isolation is therefore
"clean CONTEXT" (fresh session, no MCP schemas, read-only tools), not "cannot see the
knowledge" — the whole point is that it CAN.
"""
from __future__ import annotations

import argparse
import datetime as dt
import glob
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent   # research/2026-09-22-local-routing/
HOME = Path.home()
DISTILL = HOME / ".claude" / "distill"          # canonical on this Mac (see README)
SPINE = DISTILL / "SPINE.md"
CELLS_ROOT = HOME / ".jev-cells"                 # cells live OUTSIDE every repo (ops/headless-clean-agents.md)
TOPICS = json.loads((REPO / "topics.json").read_text())

ANSWER_RULES = (
    "Answer in at most 120 words with the applicable knowledge only. "
    "End with a line `FILES: <comma-separated paths you read>`."
)

# Tools a cell may use. Reads only: the measurement is retrieval, not work.
ALLOWED = "Read,Glob,Grep"
RUBRIC_CHARS = 400            # per-option rubric cap (65 options × 400 chars ≈ 7k tokens)
DISALLOWED = "Bash,Write,Edit,MultiEdit,NotebookEdit,Agent,WebFetch,WebSearch,ToolSearch,Skill"


# ----------------------------------------------------------------------------- cells
def cell_cmd(arm: str, topic: str, model: str | None, max_budget: float, extra_settings: dict | None = None) -> list[str]:
    cmd = [
        "claude", "-p",
        "--output-format", "json",
        "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}',
        "--allowedTools", ALLOWED,
        "--disallowedTools", DISALLOWED,
        "--max-turns", "8",
        "--max-budget-usd", str(max_budget),
    ]
    if model:
        cmd += ["--model", model]
    if extra_settings:
        cmd += ["--settings", json.dumps(extra_settings)]
    return cmd


def baseline_prompt(topic: str) -> tuple[str, str]:
    """Arm A: the real workflow. The user-level CLAUDE.md + rules/distill.md already order
    'read SPINE.md, then the domain file' — we add only the answer format."""
    return TOPICS[topic]["query"], ANSWER_RULES


def jev_prompt(topic: str, chosen: list[str]) -> tuple[str, str, dict]:
    """Arm B: JEV already picked the file(s); inject them, forbid the SPINE read."""
    body = "\n\n".join(f"<knowledge path=\"{p}\">\n{(DISTILL / p).read_text()}\n</knowledge>" for p in chosen)
    system = (
        "The relevant knowledge for this request was pre-selected by a router and is "
        "included below. Do NOT read SPINE.md or search the knowledge base; use the "
        f"included files. {ANSWER_RULES}\n\n{body}"
    )
    deny = {"permissions": {"deny": [f"Read({SPINE})", f"Read({DISTILL}/**)", f"Grep({DISTILL}/**)", f"Glob({DISTILL}/**)"]}}
    return TOPICS[topic]["query"], system, deny


def shortlist_prompt(topic: str, n: int = 3) -> tuple[str, str, dict, list]:
    """Arm C: the zero-model router's top-N SPINE BULLETS are injected; the SPINE itself is denied.

    This is the end-to-end check on E1/E2, which were expected-value arithmetic. The agent still
    chooses and still reads the file it picks — only the 21,247-token index read is replaced by a
    few hundred tokens of shortlist. A cell that reads the RIGHT file proves the mechanism; the
    token columns in RESULT.json say what it actually saved.
    """
    import sys as _s
    _s.path.insert(0, str(REPO / "prototype"))
    from spine_router import Router
    hits = Router().top(TOPICS[topic]["query"], n)
    lines = "\n".join(f"- {', '.join(h['paths'])} — {h['line']}" for h in hits)
    system = (
        "A local index router pre-selected these candidate knowledge files for this request. "
        "Do NOT read SPINE.md — it is unavailable. Read whichever candidate fits (Read is allowed "
        "on the individual files), then answer. If none fits, say so.\n\n"
        f"{lines}\n\n{ANSWER_RULES}"
    )
    deny = {"permissions": {"deny": [f"Read({SPINE})"]}}
    return TOPICS[topic]["query"], system, deny, [h["paths"][0] for h in hits]


def cmd_shortlist(a):
    run_dir = new_run_dir("shortlist", a.topic)
    ledger = run_dir / "ledger.jsonl"
    q, system, deny, cands = shortlist_prompt(a.topic, a.n)
    print(f"shortlist({a.n}) = {cands}")
    (run_dir / "shortlist.json").write_text(json.dumps({"n": a.n, "candidates": cands}, indent=2))
    cmd = cell_cmd("shortlist", a.topic, a.model, a.max_budget, deny)
    for i in range(a.reps):
        name = f"cell-{i+1:02d}"
        print(f"[{name}] running…", flush=True)
        r = run_cell(run_dir, name, cmd, q, system, {"arm": "shortlist", "topic": a.topic, "rep": i + 1,
                                                     "model_flag": a.model, "shortlist": cands})
        row = summarize(r, a.topic); row["shortlist"] = cands
        ledger.open("a").write(json.dumps(row) + "\n")
        print(f"[{name}] {row}")
    cmd_report(argparse.Namespace(run=str(run_dir)))


def run_cell(run_dir: Path, name: str, cmd: list[str], prompt: str, system: str, meta: dict) -> dict:
    cell = CELLS_ROOT / run_dir.name / name
    cell.mkdir(parents=True, exist_ok=True)
    (cell / "PROMPT.txt").write_text(prompt)
    (cell / "SYSTEM.txt").write_text(system)
    full = cmd + ["--append-system-prompt-file", str(cell / "SYSTEM.txt")]

    env = dict(os.environ)
    env.pop("CLAUDECODE", None)                  # nested-session guard
    t0 = time.monotonic()
    proc = subprocess.run(full, input=prompt, capture_output=True, text=True, cwd=cell, env=env)
    wall = time.monotonic() - t0

    try:
        result = json.loads(proc.stdout)
    except json.JSONDecodeError:
        result = {"is_error": True, "result": None, "raw_stdout": proc.stdout[-4000:]}
    result["_stderr_tail"] = proc.stderr[-2000:]
    result["_exit"] = proc.returncode
    result["_wall_s"] = round(wall, 3)
    result["_meta"] = meta
    (cell / "RESULT.json").write_text(json.dumps(result, indent=2))

    transcript = find_transcript(result.get("session_id"))
    if transcript:
        shutil.copy(transcript, cell / "transcript.jsonl")
        result["_phases"] = phases_from_transcript(cell / "transcript.jsonl")

    out = run_dir / name
    shutil.copytree(cell, out, dirs_exist_ok=True)
    (out / "RESULT.json").write_text(json.dumps(result, indent=2))
    return result


def find_transcript(session_id: str | None) -> Path | None:
    if not session_id:
        return None
    hits = glob.glob(str(HOME / ".claude" / "projects" / "*" / f"{session_id}.jsonl"))
    return Path(hits[0]) if hits else None


# ----------------------------------------------------------------------------- transcript phases
def _ts(s: str) -> float:
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def phases_from_transcript(path: Path) -> dict:
    """Split the cell's wall time into: startup -> SPINE read -> CHOOSE -> file read -> answer.
    'choose' = time between the SPINE tool_result landing and the next Read call being emitted:
    that is the model deciding which knowledge to load — the thing JEV would replace."""
    events = []  # (t, kind, detail)
    usage_by_msg: dict[str, dict] = {}
    for line in path.read_text().splitlines():
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            continue
        if d.get("type") not in ("user", "assistant") or "timestamp" not in d:
            continue
        t = _ts(d["timestamp"])
        m = d.get("message") or {}
        if isinstance(m, dict) and m.get("usage") and m.get("id"):
            usage_by_msg[m["id"]] = m["usage"]
        c = m.get("content") if isinstance(m, dict) else None
        if isinstance(c, str):
            events.append((t, "user_text", c[:80]))
            continue
        for b in c or []:
            bt = b.get("type")
            if bt == "tool_use":
                fp = (b.get("input") or {}).get("file_path") or (b.get("input") or {}).get("pattern") or ""
                events.append((t, "tool_use", f"{b.get('name')} {fp}"))
            elif bt == "tool_result":
                events.append((t, "tool_result", str(b.get("content"))[:60]))
            elif bt == "text":
                events.append((t, "text", b.get("text", "")[:80]))

    if not events:
        return {}
    t0 = events[0][0]
    spine_call = next((e for e in events if e[1] == "tool_use" and "SPINE.md" in e[2]), None)
    spine_result = next((e for e in events if spine_call and e[1] == "tool_result" and e[0] >= spine_call[0]), None)
    reads = [e for e in events if e[1] == "tool_use" and e[2].startswith("Read ") and "SPINE.md" not in e[2]]
    first_file_call = next((e for e in reads if not spine_result or e[0] >= spine_result[0]), None)
    last_text = next((e for e in reversed(events) if e[1] == "text"), None)

    files_read = [e[2].split(" ", 1)[1] for e in reads]
    rel = [os.path.relpath(f, DISTILL) if f.startswith(str(DISTILL)) else f for f in files_read]

    tokens = {"input": 0, "cache_creation": 0, "cache_read": 0, "output": 0, "thinking": 0}
    for u in usage_by_msg.values():
        tokens["input"] += u.get("input_tokens", 0)
        tokens["cache_creation"] += u.get("cache_creation_input_tokens", 0)
        tokens["cache_read"] += u.get("cache_read_input_tokens", 0)
        tokens["output"] += u.get("output_tokens", 0)
        tokens["thinking"] += (u.get("output_tokens_details") or {}).get("thinking_tokens", 0)

    def span(a, b):
        return round(b[0] - a[0], 3) if a and b else None

    return {
        "startup_to_spine_call_s": span(events[0], spine_call),
        "spine_io_s": span(spine_call, spine_result),
        "choose_s": span(spine_result, first_file_call),
        "first_file_to_answer_s": span(first_file_call, last_text),
        "total_s": span(events[0], last_text),
        "spine_read": spine_call is not None,
        "files_read": rel,
        "api_calls": len(usage_by_msg),
        "tokens": tokens,
    }


# ----------------------------------------------------------------------------- JEV router (arm B)
def spine_entries() -> list[dict]:
    """One option per SPINE bullet: {'key', 'paths', 'rubric'}. Multi-file bullets stay ONE
    option (the SPINE author grouped them on purpose); the chosen option loads all its paths.
    Rubric is trimmed so 65 options fit well inside Jev's 32k-token state+question budget."""
    import re
    out = []
    for line in SPINE.read_text().splitlines():
        if not line.startswith("- ["):
            continue
        links = re.findall(r"\[([^\]]+)\]\(([^)]+\.md)\)", line)
        if not links:
            continue
        desc = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", line[2:])   # drop link syntax, keep titles
        out.append({"key": links[0][1], "paths": [p for _, p in links], "rubric": desc[:RUBRIC_CHARS]})
    return out


def jev_route(query: str, api_key: str, model: str = "jev-latest") -> dict:
    """One Choice over all SPINE entries. Returns {'chosen': [...], 'latency_s', 'raw'}.
    Docs: https://docs.typesafe.ai/api.md (Choice: <=255 options; we have ~65)."""
    import urllib.request

    entries = spine_entries()
    criteria = {e["key"]: e["rubric"] for e in entries}   # option = SPINE bullet, rubric = its line
    criteria["__none__"] = "No knowledge file in this index is relevant to the request."
    body = {
        "state": {"request": query},
        "model": model,
        "questions": {
            "file": {
                "type": "choice",
                "instructions": "Which knowledge file should be loaded before answering `request`? "
                                "Pick the file whose description covers the task the user is about to do.",
                "criteria": criteria,
            }
        },
    }
    req = urllib.request.Request(
        "https://api.typesafe.ai/v1/systemone",
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
    )
    t0 = time.monotonic()
    with urllib.request.urlopen(req, timeout=60) as r:
        raw = json.loads(r.read())
    latency = time.monotonic() - t0
    ans = raw.get("answers", {}).get("file", raw)
    chosen = ans.get("choice") or ans.get("selected")
    paths = next((e["paths"] for e in entries if e["key"] == chosen), [])
    return {"chosen": paths, "option": chosen, "latency_s": round(latency, 3), "raw": raw}


# ----------------------------------------------------------------------------- commands
def new_run_dir(arm: str, topic: str) -> Path:
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    d = REPO / "runs" / f"{stamp}-{arm}-{topic}"
    d.mkdir(parents=True)
    return d


def cmd_plan(a):
    q, system = baseline_prompt(a.topic)
    print("TOPIC:", a.topic)
    print("QUERY:", q)
    print("EXPECTED:", TOPICS[a.topic]["expected"], "acceptable extra:", TOPICS[a.topic]["acceptable_extra"])
    print("CELL CWD:", CELLS_ROOT / "<run>" / "<cell>")
    print("CMD:", " ".join(cell_cmd("baseline", a.topic, a.model, a.max_budget)), "--append-system-prompt-file SYSTEM.txt  < PROMPT.txt")
    print("SYSTEM APPEND:", system)
    print("SPINE entries visible to JEV:", len(spine_entries()))


def cmd_baseline(a):
    run_dir = new_run_dir("baseline", a.topic)
    q, system = baseline_prompt(a.topic)
    cmd = cell_cmd("baseline", a.topic, a.model, a.max_budget)
    ledger = run_dir / "ledger.jsonl"
    for i in range(a.reps):
        name = f"cell-{i+1:02d}"
        print(f"[{name}] running…", flush=True)
        r = run_cell(run_dir, name, cmd, q, system, {"arm": "baseline", "topic": a.topic, "rep": i + 1, "model_flag": a.model})
        row = summarize(r, a.topic)
        ledger.open("a").write(json.dumps(row) + "\n")
        print(f"[{name}] {row}")
    cmd_report(argparse.Namespace(run=str(run_dir)))


def cmd_jev(a):
    key = os.environ.get("TYPESAFE_API_KEY")
    if not key:
        sys.exit("TYPESAFE_API_KEY not set (console.typesafe.ai)")
    run_dir = new_run_dir("jev", a.topic)
    ledger = run_dir / "ledger.jsonl"
    for i in range(a.reps):
        name = f"cell-{i+1:02d}"
        route = jev_route(TOPICS[a.topic]["query"], key)
        (run_dir / f"{name}.route.json").write_text(json.dumps(route, indent=2))
        print(f"[{name}] JEV chose {route['chosen']} in {route['latency_s']}s", flush=True)
        q, system, deny = jev_prompt(a.topic, route["chosen"])
        cmd = cell_cmd("jev", a.topic, a.model, a.max_budget, deny)
        r = run_cell(run_dir, name, cmd, q, system, {"arm": "jev", "topic": a.topic, "rep": i + 1, "model_flag": a.model, "route": route["chosen"], "route_latency_s": route["latency_s"]})
        row = summarize(r, a.topic)
        row["route_latency_s"] = route["latency_s"]
        row["route_chosen"] = route["chosen"]
        ledger.open("a").write(json.dumps(row) + "\n")
        print(f"[{name}] {row}")
    cmd_report(argparse.Namespace(run=str(run_dir)))


def summarize(r: dict, topic: str) -> dict:
    ph = r.get("_phases") or {}
    files = ph.get("files_read", [])
    exp = set(TOPICS[topic]["expected"])
    ok_extra = set(TOPICS[topic]["acceptable_extra"])
    usage = r.get("usage") or {}
    return {
        "cell": (r.get("_meta") or {}).get("rep"),
        "status": "error" if r.get("is_error") else "ok",
        "wall_s": r.get("_wall_s"),
        "duration_ms": r.get("duration_ms"),
        "duration_api_ms": r.get("duration_api_ms"),
        "num_turns": r.get("num_turns"),
        "cost_usd": r.get("total_cost_usd"),
        "models": list((r.get("modelUsage") or {}).keys()),
        "spine_read": ph.get("spine_read"),
        "choose_s": ph.get("choose_s"),
        "files_read": files,
        "hit": exp.issubset(set(files)),
        "stray_files": sorted(set(files) - exp - ok_extra),
        "tokens": ph.get("tokens") or usage,
    }


def cmd_report(a):
    run_dir = Path(a.run)
    rows = [json.loads(l) for l in (run_dir / "ledger.jsonl").read_text().splitlines() if l.strip()]
    if not rows:
        print("no rows"); return
    print(f"\n== {run_dir.name}  ({len(rows)} cells)")
    hdr = f"{'cell':>4} {'status':>6} {'wall_s':>7} {'api_s':>6} {'choose_s':>8} {'turns':>5} {'cost':>7} {'hit':>4}  files_read"
    print(hdr)
    for r in rows:
        api = (r.get("duration_api_ms") or 0) / 1000
        print(f"{r['cell']:>4} {r['status']:>6} {r['wall_s'] or 0:>7.1f} {api:>6.1f} {str(r.get('choose_s')):>8} {str(r.get('num_turns')):>5} {str(r.get('cost_usd'))[:7]:>7} {'Y' if r['hit'] else 'n':>4}  {','.join(r['files_read'])}")
    ok = [r for r in rows if r["status"] == "ok"]
    if ok:
        med = lambda k: sorted(x[k] for x in ok if x.get(k) is not None)[len([x for x in ok if x.get(k) is not None]) // 2]
        print(f"median wall {med('wall_s')}s · median choose {med('choose_s') if any(x.get('choose_s') for x in ok) else 'n/a'}s · hit rate {sum(r['hit'] for r in ok)}/{len(ok)} · total ${sum(r.get('cost_usd') or 0 for r in ok):.3f}")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    for name, fn in (("plan", cmd_plan), ("baseline", cmd_baseline), ("jev", cmd_jev), ("shortlist", cmd_shortlist)):
        s = sub.add_parser(name)
        s.add_argument("--topic", default=next(iter(TOPICS)), choices=list(TOPICS))
        s.add_argument("--reps", type=int, default=3)
        s.add_argument("--model", default=None, help="claude --model; default = account default (what real sessions use)")
        s.add_argument("--max-budget", type=float, default=0.50, help="per-cell USD cap")
        s.add_argument("--n", type=int, default=3, help="shortlist size (arm C only)")
        s.set_defaults(fn=fn)
    s = sub.add_parser("report"); s.add_argument("run"); s.set_defaults(fn=cmd_report)
    a = p.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
