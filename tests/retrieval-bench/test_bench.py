#!/usr/bin/env python3
"""Deterministic checks for the retrieval benchmark harness. No model calls, no network.

Each check reproduces a failure a PR #122 review found, so the decision rules and the freeze cannot
regress silently. Run: python3 tests/retrieval-bench/test_bench.py
"""
import argparse, contextlib, io, json, os, shutil, subprocess, sys, tempfile, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import bench  # noqa: E402

FAILS = []


def check(name, cond):
    print(("  ok   " if cond else "  FAIL ") + name)
    if not cond:
        FAILS.append(name)


def cases():
    return {c["id"]: c for c in json.loads((HERE / "scenarios.json").read_text())["cases"]}


def row(arm, scale, case, rep, t_ms, answer, judge=None):
    r = {"run": f"{arm}-{scale}-{case}-r{rep}", "arm": arm, "scale": scale, "case": case, "rep": rep,
         "t_done_ms": t_ms, "t_know_ms": t_ms / 2, "turns": 3, "store_reads": [], "input_tokens_total": 1,
         "result_subtype": "success", "answer": answer, "load_1m_start": 1.0}
    if judge is not None:
        r["judge_pass"] = judge
    return r


GOOD = {  # answers that satisfy every required regex, per case
    "s-done": "Show evidence: command output or a test run.", "s-paging": "2% for 5 minutes.",
    "s-smoke": "make smoke ENV=staging", "s-alias": "Capped at 10 minutes.",
    "s-ambiguous": "5 consecutive failures, half-open after 60 s.", "s-conflict": "30 minutes, updated 2026-07-20.",
    "s-fanout": "Add a contract test; staging soak 30 min.", "s-persona": "No: use a generic persona, never a real colleague's name.",
    "s-idempotent": "No, it must be byte-identical.", "s-warehouse": "02:00 UTC; fewer than 95% of rows.",
    "s-status": "Paused: the vendor contract moved.", "s-when": "2026-08-20.", "s-miss": "No record about Zephyr.",
    "p-rare": "No. 10-year retention, tombstone only.", "p-exact": "deployctl rollback; roll back first.",
}


def report(rows, manifest):
    d = Path(tempfile.mkdtemp())
    (d / "manifest.json").write_text(json.dumps(manifest))
    (d / "results.jsonl").write_text("".join(json.dumps(r) + "\n" for r in rows))
    with contextlib.redirect_stdout(io.StringIO()) as out:
        bench.cmd_report(argparse.Namespace(dir=str(d), json=True))
    return json.loads((d / "report.json").read_text()), out.getvalue()


def scored_manifest(**over):
    h = bench.current_hashes()
    m = {"split": "scored", "model": "x", "frozen": {**h, "n": "3", "date": "2026-10-03"}, **h,
         "host": {"cpu_count": 8, "ignore_load": False}, "stopped": None}
    m.update(over)
    return m


def full_scored(t_a=10000, t_b=10000):
    c = cases(); rows = []
    for arm, t in (("F11", t_a), ("F12", t_b)):
        for cid in (k for k, v in c.items() if v["split"] == "scored"):
            for rep in range(3):
                rows.append(row(arm, "S", cid, rep, t, GOOD[cid], True if c[cid].get("judge") else None))
    return rows


print("decision rules")
c = cases()
# Review 1: a case censored in one arm must not make the candidate "faster"
rows = []
for cid in ("p-rare", "p-exact"):
    for rep in range(3):
        rows.append(row("F11", "S", cid, rep, 10000, "nothing" if cid == "p-rare" else GOOD[cid], True))
        rows.append(row("F12", "S", cid, rep, 15000, GOOD[cid], True))
rep_, _ = report(rows, {"split": "pilot", "model": "x", "frozen": None, **bench.current_hashes()})
cmp_ = rep_["comparisons"][0]
check("one-arm censored case is excluded and listed", cmp_["not_comparable"] == ["p-rare"])
check("candidate slower elsewhere is not reported faster", not cmp_["speed_verdict"].startswith("faster"))

print("grading")
g = lambda cid, a, j: bench.run_passes(c[cid], {**bench.grade(c[cid], a), "result_subtype": "success", "judge_pass": j})
check("review 1: a waiver fails (judge FAIL)", not g("p-rare", "Sure, go ahead and delete them. The old 10-year retention and tombstone approach is outdated.", False))
check("review 2: 'Okay, ... no' refusal passes when the judge says PASS", g("p-rare", "Okay, short version: no. Do not delete; 10-year retention, tombstone only.", True))
check("judged case without a verdict fails", not g("p-rare", "No. 10-year retention, tombstone.", None))
check("unjudged case: regex decides", g("s-paging", "2% for 5 minutes.", None))
check("verdict parser accepts **PASS**", bench.re.match(r"\W*PASS\b", "**PASS**: fine", bench.re.I) is not None)

print("report eligibility (scored)")
rep_, _ = report(full_scored(10000, 7000), scored_manifest())
check("a complete run of the frozen design gets a verdict", "withheld" not in rep_ and rep_["comparisons"][0]["speed_verdict"].startswith("faster"))
# GPT-6 review: stopped scored run, one run per arm, --ignore-load
one = [row("F11", "S", "s-smoke", 0, 10000, GOOD["s-smoke"]), row("F12", "S", "s-smoke", 0, 1000, GOOD["s-smoke"])]
rep_, _ = report(one, scored_manifest(stopped="cost cap", host={"cpu_count": 8, "ignore_load": True}))
check("stopped / ignore-load scored run is withheld", "withheld" in rep_ and not rep_["comparisons"])
rep_, _ = report(one, scored_manifest())
check("incomplete cells are withheld", "withheld" in rep_ and "n = 3" in rep_["withheld"])
rep_, _ = report(full_scored(), scored_manifest(frozen={"n": "99"}))
check("malformed freeze record is withheld", "withheld" in rep_ and "not valid" in rep_["withheld"])
bad = scored_manifest(); bad["frozen"]["scenarios_sha256"] = "0" * 64
rep_, _ = report(full_scored(), bad)
check("hash drift is withheld", "withheld" in rep_ and "scenarios_sha256" in rep_["withheld"])

print("freeze enforcement (run --split scored refuses before any setup)")
tmp = Path(tempfile.mkdtemp())
for f in ("PROTOCOL.md", "scenarios.json", "gen_corpus.py"):
    shutil.copy(HERE / f, tmp / f)
bench.HERE = tmp


def run_refuses(frozen_text, **kw):
    f = tmp / "FROZEN"
    f.unlink(missing_ok=True)
    if frozen_text is not None:
        f.write_text(frozen_text)
    a = argparse.Namespace(split="scored", cases=None, reps=None, out=str(tmp / "out"), **kw)
    try:
        bench.cmd_run(a)
    except SystemExit as e:
        return str(e)
    except Exception as e:  # anything past the gate is a failure of the gate
        return f"PASSED THE GATE: {e!r}"
    return "PASSED THE GATE"


h = bench.current_hashes()
good = f"protocol_sha256: {h['protocol_sha256']}\nscenarios_sha256: {h['scenarios_sha256']}\nn: 3\ndate: 2026-10-03\n"
check("no FROZEN: refused", "frozen" in run_refuses(None))
check("malformed FROZEN (n 99): refused", "outside 3..10" in run_refuses(good.replace("n: 3", "n: 99")))
check("malformed FROZEN (no hash): refused", "sha256" in run_refuses("n: 3\n"))
check("hash drift: refused", "differ from FROZEN" in run_refuses(good.replace(h["scenarios_sha256"], "0" * 64)))
f = tmp / "FROZEN"; f.write_text(good)
try:
    bench.cmd_run(argparse.Namespace(split="scored", cases=None, reps=99, out=str(tmp / "out")))
    msg = "PASSED THE GATE"
except SystemExit as e:
    msg = str(e)
check("--reps with a valid FROZEN: refused", "takes n from FROZEN" in msg)
check("nothing was set up", not (tmp / "out").exists())
bench.HERE = HERE

print("idle-host wait")
seq = iter([40, 40, 2]); real = bench.os.getloadavg
bench.os.getloadavg = lambda: (next(seq, 2), 0, 0)
check("waits while busy, then releases", bench.wait_for_idle(15, 0.001, time.monotonic() + 5, say=lambda *a, **k: None) is not None)
bench.os.getloadavg = lambda: (40, 0, 0)
check("gives up at the deadline", bench.wait_for_idle(15, 0.001, time.monotonic() + 0.02, say=lambda *a, **k: None) is None)
bench.os.getloadavg = real

print("corpus")
t = Path(tempfile.mkdtemp())
for i in (1, 2):
    subprocess.run([sys.executable, str(HERE / "gen_corpus.py"), str(HERE.parent / "files-only/store-before"),
                    str(t / f"c{i}"), "--edition", "1.1", "--files", "55"], check=True)
check("same inputs give the same bytes", bench.tree_hash(t / "c1") == bench.tree_hash(t / "c2"))

print(f"\n{'FAILED: ' + ', '.join(FAILS) if FAILS else 'all checks passed'}")
sys.exit(1 if FAILS else 0)
