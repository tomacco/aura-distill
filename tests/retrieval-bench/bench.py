#!/usr/bin/env python3
"""Retrieval benchmark harness (#62), implementing tests/retrieval-bench/PROTOCOL.md (#77).

  bench.py run    --split pilot|scored --arms F11,F12 --scales S,L --reps N [--model sonnet]
                  [--jobs 3] [--seed 1] [--out DIR] [--max-cost-usd 15] [--max-runs 200]
                  [--cases id,id] [--ref-1.1 origin/main] [--ref-1.2 HEAD]
  bench.py report DIR [--json]

Each run is one fresh headless Claude Code session in a temp working directory, loading only the
runtime of one edition (its rules/distill.md and managed block, taken from a git ref) against a
synthetic store. Every stream event is stamped on arrival with this process's monotonic clock and
written raw to DIR/runs/<run>.jsonl. Nothing reads or writes a real knowledge store: the session
never loads user settings, has no MCP servers, and on macOS runs inside sandbox-exec with the real
stores and profile instruction files denied. Without sandbox-exec (any other OS) the harness
refuses to run unless --unsandboxed is given, because the sessions skip permission prompts.
"""
import argparse, concurrent.futures as cf, hashlib, json, math, os, platform, random, re, shutil
import statistics as st, subprocess, sys, tempfile, threading, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
SCALES = {"S": 0, "M": 25, "L": 55}
ARMS = {
    # name: edition, store fixture, surface, extra instruction
    "F11": ("1.1", "store-before", "claude", ""),
    "F12": ("1.2", "store-after", "claude", ""),
    "F11-codex": ("1.1", "store-before", "codex", ""),
    "F12-codex": ("1.2", "store-after", "codex", ""),
    # diagnostic only (PROTOCOL.md, Arms): reproduces the 2026-08-18 serialized reads
    "F11-serial": ("1.1", "store-before", "claude",
                   "Make at most one tool call per assistant turn."),
    # the service edition (#84/#87) does not exist yet; its cells are recorded as null
    "SVC": ("service", None, None, ""),
}
HOME = Path.home()
DENY = [HOME / p for p in (".aura-distill", ".claude/distill", ".claude/rules", ".claude/CLAUDE.md",
                           ".claude/projects", ".claude/memory", ".claude/todos", ".claude/commands",
                           ".claude/skills", ".claude/agents", ".claude/plugins", ".codex", ".gemini")]
if os.environ.get("AURA_DISTILL_HOME"):
    DENY.append(Path(os.environ["AURA_DISTILL_HOME"]).expanduser())
UNSET = ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SESSION_ID", "CLAUDE_CODE_CHILD_SESSION",
         "CLAUDE_CODE_MESSAGING_SOCKET", "CLAUDE_CODE_MESSAGING_TOKEN", "AURA_DISTILL_HOME"]


def sha(b):
    return hashlib.sha256(b if isinstance(b, bytes) else b.encode()).hexdigest()


def tree_hash(d):
    h = hashlib.sha256()
    for p in sorted(Path(d).rglob("*")):
        if p.is_file():
            h.update(str(p.relative_to(d)).encode() + b"\0" + p.read_bytes() + b"\0")
    return h.hexdigest()


def git(*a):
    return subprocess.run(["git", "-C", str(REPO), *a], capture_output=True, text=True, check=True).stdout


def managed_block(install_sh, store, client):
    """The integration block a client really gets, from that ref's own install.sh function."""
    fn = re.search(r"^integration_block\(\) \{.*?^\}", install_sh, re.S | re.M).group(0)
    script = (f"DISTILL_DIR='{store}'; MANAGED_START='<!-- aura-distill:start -->'; "
              f"MANAGED_END='<!-- aura-distill:end -->'\n{fn}\nintegration_block {client}\n")
    return subprocess.run(["bash", "-c", script], capture_output=True, text=True, check=True).stdout


def setup_cell(root, arm, scale, refs, seed):
    """Build one arm x scale: store, installed runtime, injected instructions. Returns its manifest."""
    edition, fixture, surface, extra = ARMS[arm]
    cell = root / "cells" / f"{arm}-{scale}"
    store, work = cell / "store", cell / "work"
    work.mkdir(parents=True)
    subprocess.run([sys.executable, str(HERE / "gen_corpus.py"), str(REPO / "tests/files-only" / fixture),
                    str(store), "--edition", edition, "--files", str(SCALES[scale]), "--seed", str(seed)], check=True)
    corpus = tree_hash(store)
    ref = refs[edition]
    commit = git("rev-parse", ref).strip()
    show = lambda p: git("show", f"{commit}:{p}")
    for f in ("distill-monitor.md", "distill-process.md"):
        (store / f).write_text(show(f).replace("{DISTILL_DIR}", str(store)))
    (store / ".status").write_text("idle 2026-09-30T00:00:00Z\n")
    runtime = sha("".join((store / f).read_text() for f in ("distill-monitor.md", "distill-process.md")))
    block = managed_block(show("install.sh"), store, surface)
    rules = show("rules/distill.md").replace("{DISTILL_DIR}", str(store))
    sysprompt = ""
    if surface == "claude":
        injected = block + "\n" + rules
        (work / "CLAUDE.md").write_text(injected)
        sources = "project"
    else:
        injected = sysprompt = block
        sources = "local"
    if extra:
        sysprompt = (sysprompt + "\n" + extra).strip()
    return {"arm": arm, "scale": scale, "edition": edition, "surface": surface, "ref": ref, "commit": commit,
            "fixture": fixture, "filler_files": SCALES[scale], "seed": seed, "corpus_sha256": corpus,
            "runtime_files_sha256": runtime, "installed_store_sha256": tree_hash(store),
            "store_files": sum(1 for p in store.rglob("*.md")), "spine_bytes": (store / "SPINE.md").stat().st_size,
            "injected_sha256": sha(injected), "injected_bytes": len(injected.encode()),
            "append_system_prompt": sysprompt, "setting_sources": sources,
            "store": str(store), "work": str(work), "extra_instruction": extra}


def sandbox_prefix(root):
    if not shutil.which("sandbox-exec"):
        return []
    deny = "".join(f'(deny file-read* file-write* (subpath "{d}"))' for d in DENY)
    return ["sandbox-exec", "-p", f"(version 1)(allow default){deny}"]


def run_claude(prompt, cwd, model, sources, sysprompt, trace_path, timeout, sandbox, add_dir=None):
    """One headless session; every stdout line is stamped with ms since spawn (monotonic)."""
    cmd = [*sandbox, "claude", "-p", prompt, "--model", model, "--setting-sources", sources,
           "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}', "--no-session-persistence",
           "--dangerously-skip-permissions", "--disallowedTools", "WebFetch", "WebSearch",
           "--output-format", "stream-json", "--verbose"]
    if add_dir:
        cmd += ["--add-dir", add_dir]
    if sysprompt:
        cmd += ["--append-system-prompt", sysprompt]
    env = {k: v for k, v in os.environ.items() if k not in UNSET}
    env["ENABLE_CLAUDEAI_MCP_SERVERS"] = "false"
    t0 = time.monotonic_ns()
    errf = open(str(trace_path) + ".err", "w+")
    p = subprocess.Popen(cmd, cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                         stderr=errf, text=True)
    timer = threading.Timer(timeout, p.kill); timer.start()
    with open(trace_path, "w") as out:
        for line in p.stdout:
            t = (time.monotonic_ns() - t0) / 1e6
            try:
                ev = json.loads(line)
            except ValueError:
                ev = {"type": "_unparsed", "raw": line[:2000]}
            out.write(json.dumps({"t_ms": round(t, 1), "ev": ev}) + "\n")
    rc = p.wait(); timer.cancel()
    errf.seek(0); err = errf.read(); errf.close()
    end = (time.monotonic_ns() - t0) / 1e6
    with open(trace_path, "a") as out:
        out.write(json.dumps({"t_ms": round(end, 1), "ev": {"type": "_exit", "rc": rc, "stderr": err[-2000:]}}) + "\n")
    return rc


def metrics(trace_path, store):
    """Timing boundaries and counts from one raw trace (PROTOCOL.md, Timing boundaries)."""
    m = {"t_init_ms": None, "t_first_store_read_ms": None, "t_know_ms": None, "t_done_ms": None,
         "turns": 0, "tool_calls": 0, "store_reads": [], "max_parallel_tools": 0, "store_tool_wall_ms": 0.0,
         "store_bytes_read": 0, "answer": "", "result_subtype": None, "duration_ms": None, "duration_api_ms": None,
         "num_turns": None, "usage": None, "cost_usd": None, "rate_limit_5h": None, "rc": None, "error": None}
    uses, per_msg, msgs = {}, {}, []
    for line in open(trace_path):
        r = json.loads(line); t, ev = r["t_ms"], r["ev"]
        ty = ev.get("type")
        if ty == "system" and ev.get("subtype") == "init" and m["t_init_ms"] is None:
            m["t_init_ms"] = t; m["cli_version"] = ev.get("claude_code_version"); m["model_id"] = ev.get("model")
        elif ty == "assistant":
            msg = ev.get("message", {}); mid = msg.get("id")
            if mid not in per_msg:
                per_msg[mid] = 0; msgs.append(mid)
            for c in msg.get("content", []):
                if c.get("type") == "tool_use":
                    per_msg[mid] += 1
                    uses[c["id"]] = (t, c.get("name"), c.get("input", {}))
        elif ty == "user":
            for c in ev.get("message", {}).get("content", []) if isinstance(ev.get("message", {}).get("content"), list) else []:
                if c.get("type") != "tool_result" or c.get("tool_use_id") not in uses:
                    continue
                t0, name, inp = uses[c["tool_use_id"]]
                blob = json.dumps(inp)
                if store in blob:
                    m["store_tool_wall_ms"] += t - t0
                    if m["t_first_store_read_ms"] is None:
                        m["t_first_store_read_ms"] = t
                    m["t_know_ms"] = t
                    content = c.get("content")
                    m["store_bytes_read"] += len(json.dumps(content)) if content is not None else 0
                    if name == "Read":
                        m["store_reads"].append(inp.get("file_path", "").replace(store + "/", ""))
                    else:
                        what = (inp.get("pattern") or inp.get("command") or "").replace(store + "/", "").replace(store, "<store>")
                        m["store_reads"].append(f"{name}:{what[:80]}")
        elif ty == "rate_limit_event":
            w = ev.get("rate_limit_info", {}).get("unifiedWindows", {}).get("five_hour", {})
            m["rate_limit_5h"] = w.get("utilization", m["rate_limit_5h"])
        elif ty == "result":
            m["t_done_ms"] = t; m["result_subtype"] = ev.get("subtype"); m["answer"] = ev.get("result") or ""
            for k in ("duration_ms", "duration_api_ms", "num_turns"):
                m[k] = ev.get(k)
            m["usage"] = ev.get("usage"); m["cost_usd"] = ev.get("total_cost_usd")
        elif ty == "_exit":
            m["rc"] = ev.get("rc")
            if ev.get("rc"):
                m["error"] = (ev.get("stderr") or "")[-300:]
    m["turns"] = len(msgs); m["tool_calls"] = len(uses)
    m["max_parallel_tools"] = max(per_msg.values(), default=0)
    u = m["usage"] or {}
    m["input_tokens_total"] = sum(u.get(k) or 0 for k in ("input_tokens", "cache_creation_input_tokens",
                                                          "cache_read_input_tokens")) if u else None
    return m


def grade(case, answer):
    flat = re.sub(r"\s+", " ", answer or "")
    missing = [r for r in case["required"] if not re.search(r, flat, re.I)]
    harmful = [r for r in case.get("harmful", []) if re.search(r, flat, re.I)]
    return {"required_missing": missing, "harmful_hits": harmful, "regex_pass": not missing and not harmful}


JUDGE = """You grade one answer from an assistant against a rubric. You do not know which system produced it.
Question the user asked:
<question>{q}</question>
Answer given:
<answer>{a}</answer>
Rubric: {rubric}
Do not use any tools. Reply with exactly one line: PASS or FAIL, then a colon and at most 20 words of reason."""


def judge(case, answer, model, root, sandbox, name):
    d = Path(tempfile.mkdtemp(dir=root / "judge"))
    tp = root / "judge" / f"{name}.jsonl"
    run_claude(JUDGE.format(q=case["q"], a=answer, rubric=case["judge"]), d, model, "local", "", tp, 300, sandbox)
    jm = metrics(tp, "\0"); out = jm["answer"].strip()
    return {"judge_model": model, "judge_raw": out[:200], "judge_pass": out.upper().startswith("PASS"),
            "judge_cost_usd": jm["cost_usd"] or 0}


def probe_injection(cell, model, root, sandbox):
    """Verify the instructions actually reached the session (PROTOCOL.md, Equalization)."""
    tp = root / "probes" / f"{cell['arm']}-{cell['scale']}.jsonl"
    q = ("Do not use any tools. Which file do your instructions say to read before doing any work? "
         "Reply with the absolute path only.")
    run_claude(q, cell["work"], model, cell["setting_sources"], cell["append_system_prompt"], tp, 300, sandbox)
    pm = metrics(tp, "\0"); ans = pm["answer"].strip()
    return {"probe_model": model, "answer": ans[:300], "ok": (cell["store"] + "/SPINE.md") in ans,
            "cost_usd": pm["cost_usd"] or 0}


def wait_for_idle(limit, poll, deadline, say=print):
    """Benchmarks yield to other work: block while the 1-minute load is above limit.
    Returns seconds waited, or None when the deadline passed first."""
    t0 = time.monotonic(); told = False
    while os.getloadavg()[0] > limit:
        if time.monotonic() >= deadline:
            return None
        if not told:
            say(f"host load {os.getloadavg()[0]:.1f} > {limit}: waiting for the machine to go idle", flush=True)
            told = True
        time.sleep(poll)
    return round(time.monotonic() - t0, 1)


def plan(cases, arms, scales, reps, rnd):
    """Interleaved, randomized order: each block = one rep x scale x case, arms shuffled inside it."""
    order = []
    for rep in range(reps):
        for scale in rnd.sample(scales, len(scales)):
            for case in rnd.sample(cases, len(cases)):
                for arm in rnd.sample(arms, len(arms)):
                    order.append((rep, scale, case["id"], arm))
    return order


def cmd_run(a):
    data = json.loads((HERE / "scenarios.json").read_text())
    cases = [c for c in data["cases"] if c["split"] == a.split]
    if a.cases:
        keep = set(a.cases.split(",")); cases = [c for c in cases if c["id"] in keep]
    if a.split == "scored" and not (HERE / "FROZEN").exists():
        sys.exit("scored cases run only after the protocol is frozen (PROTOCOL.md, Freeze)")
    if not shutil.which("claude"):
        sys.exit("claude CLI not found")
    if not shutil.which("sandbox-exec") and not a.unsandboxed:
        sys.exit("sandbox-exec not found: sessions would run without isolation; pass --unsandboxed to accept that")
    limit = a.max_load if a.max_load is not None else (os.cpu_count() or 1)
    deadline = time.monotonic() + a.max_wait_hours * 3600
    if not a.ignore_load and wait_for_idle(limit, a.poll_seconds, deadline) is None:
        sys.exit(f"host load stayed above {limit} for {a.max_wait_hours} h; nothing was run")
    if a.max_cost_usd is None:
        a.max_cost_usd = 40.0 if a.split == "scored" else 15.0
    if a.max_runs is None:
        a.max_runs = 520 if a.split == "scored" else 200
    arms = a.arms.split(","); scales = a.scales.split(",")
    root = Path(a.out or tempfile.mkdtemp(prefix="aura-bench-", dir=os.environ.get("TMPDIR", "/tmp"))).resolve()
    for d in ("cells", "runs", "judge", "probes"):
        (root / d).mkdir(parents=True, exist_ok=True)
    print(f"out: {root}", flush=True)
    refs = {"1.1": a.ref_11, "1.2": a.ref_12}
    sandbox = sandbox_prefix(root)
    cells, null_cells = {}, []
    for arm in arms:
        for scale in scales:
            if ARMS[arm][0] == "service":
                null_cells.append({"arm": arm, "scale": scale, "status": "not implemented (#84/#87)"}); continue
            c = setup_cell(root, arm, scale, refs, a.seed)
            c["probe"] = probe_injection(c, a.probe_model, root, sandbox)
            print(f"cell {arm}-{scale}: {c['store_files']} files, SPINE {c['spine_bytes']} B, injection "
                  f"{'ok' if c['probe']['ok'] else 'NOT VERIFIED: ' + c['probe']['answer'][:80]}", flush=True)
            cells[(arm, scale)] = c
    rnd = random.Random(a.seed)
    full = [o for o in plan(cases, arms, scales, a.reps, rnd) if (o[3], o[1]) in cells]
    order = full[: a.max_runs]
    truncated = f"run cap {a.max_runs} truncated the plan of {len(full)} runs" if len(full) > len(order) else None
    by_id = {c["id"]: c for c in cases}
    manifest = {
        "protocol": "tests/retrieval-bench/PROTOCOL.md", "protocol_sha256": sha((HERE / "PROTOCOL.md").read_bytes()),
        "scenarios_sha256": sha((HERE / "scenarios.json").read_bytes()), "split": a.split,
        "harness_commit": git("rev-parse", "HEAD").strip(), "harness_dirty": bool(git("status", "--porcelain", "--", "tests/retrieval-bench").strip()),
        "frozen": (HERE / "FROZEN").exists(), "model": a.model, "judge_model": a.judge_model, "jobs": a.jobs,
        "seed": a.seed, "reps": a.reps, "budget": {"max_cost_usd": a.max_cost_usd, "max_runs": a.max_runs,
                                                   "stop_rate_limit_5h": a.stop_rate_limit},
        "host": {"cpu_count": os.cpu_count(), "load_1m_at_start": round(os.getloadavg()[0], 2),
                 "load_rule": f"wait while 1-minute load > {limit}, before the first run and before each run",
                 "ignore_load": a.ignore_load,
                 "platform": platform.platform(), "python": platform.python_version(), "sandbox": bool(sandbox),
                 "claude_cli": subprocess.run(["claude", "--version"], capture_output=True, text=True).stdout.strip()},
        "cache_state": "recorded per run from usage; not controlled", "cells": [
            {k: v for k, v in c.items()} for c in cells.values()], "null_cells": null_cells,
        "order": [list(o) for o in order], "started_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    (root / "manifest.json").write_text(json.dumps(manifest, indent=1))
    probe_cost = sum(c["probe"]["cost_usd"] for c in cells.values())
    lock = threading.Lock(); spent = {"cost": probe_cost, "stop": None, "n": 0, "err": 0}
    results = open(root / "results.jsonl", "a")

    def one(i, o):
        rep, scale, cid, arm = o
        with lock:
            if spent["stop"]:
                return
        cell, case = cells[(arm, scale)], by_id[cid]
        waited = 0.0
        if not a.ignore_load:
            waited = wait_for_idle(limit, a.poll_seconds, deadline)
            if waited is None:
                with lock:
                    spent["stop"] = spent["stop"] or f"host load stayed above {limit} past the {a.max_wait_hours} h wait"
                return
        load_start = os.getloadavg()[0]
        name = f"{i:04d}-{arm}-{scale}-{cid}-r{rep}"
        tp = root / "runs" / f"{name}.jsonl"
        run_claude(case["q"], cell["work"], a.model, cell["setting_sources"], cell["append_system_prompt"], tp,
                   a.timeout, sandbox, add_dir=cell["store"])
        m = metrics(tp, cell["store"]); g = grade(case, m["answer"])
        j = judge(case, m["answer"], a.judge_model, root, sandbox, name) if case.get("judge") else {}
        ok = g["regex_pass"] and j.get("judge_pass", True) and m["result_subtype"] == "success"
        rec = {"i": i, "run": name, "arm": arm, "scale": scale, "case": cid, "category": case["category"],
               "rep": rep, "load_1m_start": round(load_start, 2), "waited_for_idle_s": waited, **{k: v for k, v in m.items() if k != "answer"}, "answer": m["answer"], **g, **j, "pass": ok}
        with lock:
            results.write(json.dumps(rec) + "\n"); results.flush()
            spent["n"] += 1; spent["cost"] += (m["cost_usd"] or 0) + j.get("judge_cost_usd", 0)
            spent["err"] += m["result_subtype"] != "success"
            if spent["cost"] >= a.max_cost_usd:
                spent["stop"] = f"cost cap {a.max_cost_usd} USD reached"
            elif (m["rate_limit_5h"] or 0) >= a.stop_rate_limit:
                spent["stop"] = f"5-hour rate-limit utilization {m['rate_limit_5h']} >= {a.stop_rate_limit}"
            elif spent["n"] >= 10 and spent["err"] / spent["n"] > 0.2:
                spent["stop"] = "more than 20% of runs ended without success"
            print(f"[{spent['n']}/{len(order)}] {name}: {'PASS' if ok else 'FAIL'} "
                  f"done={m['t_done_ms']}ms know={m['t_know_ms']}ms reads={len(m['store_reads'])} "
                  f"cost={m['cost_usd']}", flush=True)

    with cf.ThreadPoolExecutor(max_workers=a.jobs) as ex:
        list(ex.map(lambda x: one(*x), enumerate(order)))
    manifest["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    manifest["stopped"] = spent["stop"] or truncated; manifest["runs_done"] = spent["n"]; manifest["cost_usd_reported"] = round(spent["cost"], 4)
    manifest["cost_note"] = "runs + judge + injection probes, as reported by the CLI"
    (root / "manifest.json").write_text(json.dumps(manifest, indent=1))
    print(f"done: {spent['n']} runs, reported cost {spent['cost']:.2f} USD, stop: {spent['stop']}")
    print(f"report: {sys.argv[0]} report {root}")


# ---------- report ----------

def med(xs):
    xs = sorted(xs)
    return xs[len(xs) // 2] if len(xs) % 2 else (xs[len(xs) // 2 - 1] + xs[len(xs) // 2]) / 2 if xs else None


def censored_median(rs):
    """Time to completed correct task: a failed run counts as never finishing (+inf)."""
    return med([r["t_done_ms"] if r["pass"] and r["t_done_ms"] else math.inf for r in rs]) if rs else None


def comparable(cells_b, cells_a):
    """Cases whose censored median is finite in BOTH arms. A case censored in either arm is not
    comparable for latency and never moves the ratio; quality rules 2 and 3 still cover it."""
    return sorted(c for c in cells_a if c in cells_b and not math.isinf(censored_median(cells_a[c]))
                  and not math.isinf(censored_median(cells_b[c])))


def geo_ratio(cells_b, cells_a, cases, rnd=None):
    """Geometric mean over the given cases of median(B)/median(A); with rnd, one bootstrap resample
    within cells. A resample whose median becomes censored drops that case from that resample."""
    logs = []
    for cid in cases:
        a, b = cells_a[cid], cells_b[cid]
        if rnd:
            a = [rnd.choice(a) for _ in a]; b = [rnd.choice(b) for _ in b]
        ma, mb = censored_median(a), censored_median(b)
        if math.isinf(ma) or math.isinf(mb):
            continue
        logs.append(math.log(mb / ma))
    return math.exp(sum(logs) / len(logs)) if logs else None


def cmd_report(a):
    root = Path(a.dir)
    man = json.loads((root / "manifest.json").read_text())
    rs = [json.loads(l) for l in open(root / "results.jsonl")]
    data = json.loads((HERE / "scenarios.json").read_text())
    protected = {c["id"] for c in data["cases"] if c["category"] == "rare-directive"}
    # grading is deterministic, so the report re-grades stored answers with the current cases;
    # judge verdicts are kept as recorded
    by_id = {c["id"]: c for c in data["cases"]}
    extra = {}
    if (root / "rejudged.jsonl").exists():
        for l in open(root / "rejudged.jsonl"):
            x = json.loads(l); extra[x["run"]] = x
    rs = [r for r in rs if r["case"] in by_id]
    for r in rs:
        r.update(extra.get(r["run"], {}))
        r.update(grade(by_id[r["case"]], r["answer"]))
        r["pass"] = r["regex_pass"] and r.get("judge_pass", True) and r["result_subtype"] == "success"
    graded_with = sha((HERE / "scenarios.json").read_bytes())
    if graded_with != man["scenarios_sha256"]:
        print(f"Note: re-graded with scenarios {graded_with[:12]}; the runs used {man['scenarios_sha256'][:12]}.\n")
    out = {"manifest": {k: man.get(k) for k in ("split", "model", "frozen", "harness_commit", "harness_dirty", "stopped",
                                                 "runs_done", "cost_usd_reported")}, "cells": [], "comparisons": []}
    groups = {}
    for r in rs:
        groups.setdefault((r["arm"], r["scale"], r["case"]), []).append(r)
    print(f"# Retrieval benchmark report ({man['split']}, model {man['model']}, frozen={man['frozen']})\n")
    print("| arm | scale | case | n | pass | t_done median (min-max) s | t_know median s | turns | store reads | input tok (median) | log-sd t_done |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    logsd = {}
    for (arm, scale, cid), g in sorted(groups.items()):
        td = [r["t_done_ms"] / 1000 for r in g if r["t_done_ms"]]
        tk = [r["t_know_ms"] / 1000 for r in g if r["t_know_ms"]]
        sd = st.stdev([math.log(x) for x in td]) if len(td) > 1 else None
        logsd[(arm, scale, cid)] = sd
        row = {"arm": arm, "scale": scale, "case": cid, "n": len(g), "pass": sum(r["pass"] for r in g),
               "t_done_median_s": med(td), "t_know_median_s": med(tk), "turns_median": med([r["turns"] for r in g]),
               "store_reads_median": med([len(r["store_reads"]) for r in g]),
               "input_tokens_median": med([r["input_tokens_total"] or 0 for r in g]), "log_sd_t_done": sd}
        out["cells"].append(row)
        f = lambda x: "-" if x is None else f"{x:.1f}"
        print(f"| {arm} | {scale} | {cid} | {len(g)} | {row['pass']}/{len(g)} | {f(med(td))} ({f(min(td) if td else None)}-{f(max(td) if td else None)}) "
              f"| {f(row['t_know_median_s'])} | {row['turns_median']} | {row['store_reads_median']} | {int(row['input_tokens_median'])} | {'-' if sd is None else f'{sd:.3f}'} |")
    sds = [x for x in logsd.values() if x is not None]
    pooled = math.sqrt(sum(x * x for x in sds) / len(sds)) if sds else None
    out["pooled_log_sd"] = pooled
    for arm in sorted({r["arm"] for r in rs}):
        loads = [r["load_1m_start"] for r in rs if r["arm"] == arm and r.get("load_1m_start") is not None]
        if loads:
            print(f"\nHost load at run start, {arm}: median {med(loads):.1f}, max {max(loads):.1f}", end="")
    print(f"\n\nPooled log-sd of t_done across cells: {'-' if pooled is None else f'{pooled:.3f}'}")
    # decision rule (PROTOCOL.md, Decision rules): B = redesigned edition, A = incumbent
    for b_arm, a_arm in (("F12", "F11"), ("F12-codex", "F11-codex")):
        for scale in sorted({r["scale"] for r in rs}):
            A = {cid: g for (arm, sc, cid), g in groups.items() if arm == a_arm and sc == scale}
            B = {cid: g for (arm, sc, cid), g in groups.items() if arm == b_arm and sc == scale}
            if not A or not B:
                continue
            cases = comparable(B, A)
            excluded = sorted(set(A) & set(B) - set(cases))
            ratio = geo_ratio(B, A, cases)
            rnd = random.Random(7)
            boots = sorted(x for x in (geo_ratio(B, A, cases, rnd) for _ in range(2000)) if x is not None)
            lo, hi = (boots[int(0.05 * len(boots))], boots[int(0.95 * len(boots)) - 1]) if boots else (None, None)
            pa = sum(r["pass"] for g in A.values() for r in g) / sum(len(g) for g in A.values())
            pb = sum(r["pass"] for g in B.values() for r in g) / sum(len(g) for g in B.values())
            flips = [cid for cid in A if cid in B and sum(r["pass"] for r in A[cid]) * 2 > len(A[cid])
                     and sum(r["pass"] for r in B[cid]) * 2 <= len(B[cid])]
            prot_fail = [r["run"] for cid in protected & set(B) for r in B[cid] if not r["pass"]]
            noninf = pb >= pa - 0.05 and not flips and not prot_fail
            if ratio is None or 2 * len(cases) < len(set(A) & set(B)):
                speed = "not enough comparable cases (fewer than half)"
            elif hi is not None and ratio <= 0.85 and hi < 1.0:
                speed = "faster (practical gain)"
            elif ratio > 1.10 and lo is not None and lo > 1.0:
                speed = "slower (regression)"
            else:
                speed = "no practical difference shown"
            c = {"b": b_arm, "a": a_arm, "scale": scale, "geo_ratio_t_done": ratio, "ci90": [lo, hi],
                 "latency_cases": cases, "not_comparable": excluded,
                 "pass_rate_a": pa, "pass_rate_b": pb, "majority_flips": flips, "protected_failures": prot_fail,
                 "non_inferior": noninf, "speed_verdict": speed}
            out["comparisons"].append(c)
            fmt = lambda x: "-" if x is None else ("inf" if math.isinf(x) else f"{x:.3f}")
            print(f"\n## {b_arm} vs {a_arm}, scale {scale}\n- time to correct completion, geometric-mean ratio of medians: "
                  f"{fmt(ratio)} (90% bootstrap {fmt(lo)}-{fmt(hi)}) over {len(cases)} cases -> {speed}; "
                  f"not comparable (a censored median in either arm): {excluded or 'none'}\n- pass rate {pa:.0%} -> {pb:.0%}; "
                  f"majority flips: {flips or 'none'}; protected-rule failures in {b_arm}: {prot_fail or 'none'} -> "
                  f"{'non-inferior' if noninf else 'NOT non-inferior'}")
    if man["split"] == "pilot" and pooled:
        k = len({r["case"] for r in rs}); d = math.log(1 / 0.85)
        n = max(3, min(10, math.ceil(2 * (1.645 + 0.842) ** 2 * pooled ** 2 / (k * d * d))))
        print(f"\nSample-size rule (PROTOCOL.md): n per cell = clamp(3, 10, ceil(2*(1.645+0.842)^2*s^2/(k*ln(1/0.85)^2))) "
              f"with s={pooled:.3f}, k={k} pilot cases -> n={n}. Recompute with k = number of scored cases.")
        out["sample_size_pilot_k"] = n
    if a.json:
        (root / "report.json").write_text(json.dumps(out, indent=1, default=str))


def cmd_rejudge(a):
    """Judge stored answers whose case gained a rubric after the run; written to rejudged.jsonl."""
    root = Path(a.dir)
    by_id = {c["id"]: c for c in json.loads((HERE / "scenarios.json").read_text())["cases"]}
    done = set()
    if (root / "rejudged.jsonl").exists():
        done = {json.loads(l)["run"] for l in open(root / "rejudged.jsonl")}
    todo = [r for r in map(json.loads, open(root / "results.jsonl"))
            if by_id.get(r["case"], {}).get("judge") and "judge_pass" not in r and r["run"] not in done]
    sandbox = sandbox_prefix(root)
    if not sandbox and not a.unsandboxed:
        sys.exit("sandbox-exec not found; pass --unsandboxed to accept that")
    out = open(root / "rejudged.jsonl", "a"); lock = threading.Lock()

    def one(r):
        j = judge(by_id[r["case"]], r["answer"], a.judge_model, root, sandbox, "rejudge-" + r["run"])
        with lock:
            out.write(json.dumps({"run": r["run"], **j}) + "\n"); out.flush()
            print(f"{r['run']}: {'PASS' if j['judge_pass'] else 'FAIL'} {j['judge_raw'][:80]}", flush=True)
    with cf.ThreadPoolExecutor(max_workers=a.jobs) as ex:
        list(ex.map(one, todo))
    print(f"rejudged {len(todo)} answers")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("--split", choices=["pilot", "scored"], required=True)
    r.add_argument("--arms", default="F11,F12"); r.add_argument("--scales", default="S,L")
    r.add_argument("--reps", type=int, default=3); r.add_argument("--cases")
    r.add_argument("--model", default="sonnet"); r.add_argument("--judge-model", default="opus")
    r.add_argument("--probe-model", default="haiku")
    r.add_argument("--jobs", type=int, default=3); r.add_argument("--seed", type=int, default=1)
    r.add_argument("--timeout", type=int, default=600); r.add_argument("--out")
    r.add_argument("--max-cost-usd", type=float, help="default 15 (pilot) or 40 (scored)")
    r.add_argument("--max-runs", type=int, help="default 200 (pilot) or 520 (scored)")
    r.add_argument("--unsandboxed", action="store_true", help="run without sandbox-exec (no isolation)")
    r.add_argument("--ignore-load", action="store_true", help="do not wait for an idle host (such a run is not scored)")
    r.add_argument("--max-load", type=float, help="1-minute load to wait below (default: core count)")
    r.add_argument("--poll-seconds", type=int, default=60); r.add_argument("--max-wait-hours", type=float, default=12)
    r.add_argument("--stop-rate-limit", type=float, default=0.8)
    r.add_argument("--ref-1.1", dest="ref_11", default="origin/main"); r.add_argument("--ref-1.2", dest="ref_12", default="HEAD")
    p = sub.add_parser("report"); p.add_argument("dir"); p.add_argument("--json", action="store_true")
    j = sub.add_parser("rejudge"); j.add_argument("dir"); j.add_argument("--judge-model", default="opus")
    j.add_argument("--jobs", type=int, default=3); j.add_argument("--unsandboxed", action="store_true")
    a = ap.parse_args()
    {"run": cmd_run, "report": cmd_report, "rejudge": cmd_rejudge}[a.cmd](a)


if __name__ == "__main__":
    main()
