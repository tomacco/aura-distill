#!/usr/bin/env python3
"""Battery runner for the capabilities-matrix skill.

Mechanically enforces what prose cannot (execution-gap rule): cost caps, blinding,
idempotent cells, fail-fast on rate limits, injection isolation (responses are stored,
never interpreted). The AGENT generates probes and judges; this script only moves data.

Usage:
  battery-runner.py --estimate <battery.json>     token/cost dry-run estimate
  battery-runner.py --run <battery.json>          execute cells (idempotent)
  battery-runner.py --blind <battery.json>        build blinded judge packets
  battery-runner.py --unseal <battery.json>       reveal arm mapping (after scores exist)
  battery-runner.py --spread <battery.json>       per-demand score spread vs dispersion

battery.json (authored by the agent per SKILL.md):
{
  "battery_version": "v1-2026-07",
  "workdir": "<absolute path under {DISTILL_DIR}/data/probes-local/...>",
  "hard_cap_tokens": 500000,
  "arms": [{"id": "modelA", "kind": "cli", "model": "..."} |
           {"id": "custom1", "kind": "openai-http", "base_url": "...", "model": "...",
            "api_key_env": "MY_KEY"}],
  "cells": [{"demand": "D4", "probe_file": "D4-p1.md", "rubric_file": "D4-p1.rubric.md",
             "n": 3}]
}
"""
import json, os, sys, hashlib, subprocess, urllib.request

if hasattr(sys.stdout, "reconfigure"):  # Windows cp1252 console guard
    sys.stdout.reconfigure(encoding="utf-8")

CAP_SLACK = 1.0  # cap is enforced exactly as given (skill sets it to 1.5x estimate)
LIMIT_MARKERS = ("hit your session limit", "hit your usage limit")


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def cell_id(cell, arm, rep):
    return f"{cell['demand']}_{os.path.splitext(cell['probe_file'])[0]}_{arm['id']}_r{rep}"


def iter_runs(b):
    for cell in b["cells"]:
        for arm in b["arms"]:
            for rep in range(1, cell.get("n", 3) + 1):
                yield cell, arm, rep


def estimate(b):
    total_in = total_out = 0
    for cell, arm, rep in iter_runs(b):
        p = os.path.join(b["workdir"], cell["probe_file"])
        probe_tok = os.path.getsize(p) // 4 if os.path.exists(p) else 3000
        total_in += probe_tok + 3000   # + spawn floor (text-only)
        total_out += 1500              # response budget guess
    judge = int((total_in + total_out) * 0.6)  # blind packets re-read by the judge
    est = total_in + total_out + judge
    print(json.dumps({"cells": sum(1 for _ in iter_runs(b)), "estimated_tokens": est,
                      "suggested_hard_cap": int(est * 1.5)}))


def spent_tokens(b):
    total = 0
    rdir = os.path.join(b["workdir"], "results")
    if os.path.isdir(rdir):
        for fn in os.listdir(rdir):
            try:
                u = load(os.path.join(rdir, fn)).get("usage") or {}
                # cap counts WORK tokens (input+output) to match estimate(); cache
                # traffic excluded so cold-cache runs do not race to premature PARTIAL
                total += sum(u.get(k, 0) for k in ("input_tokens", "output_tokens")
                             if isinstance(u.get(k), int))
            except Exception:
                pass
    return total


def call_cli(arm, prompt):
    r = subprocess.run(["claude", "-p", "--model", arm["model"], "--tools", "",
                        "--output-format", "json"],
                       input=prompt.encode("utf-8"), capture_output=True, timeout=300)
    out = r.stdout.decode("utf-8", "replace")
    o = json.loads(out)
    return o.get("result", ""), o.get("usage") or {}, r.returncode


def call_http(arm, prompt):
    key = os.environ.get(arm.get("api_key_env", ""), "")
    req = urllib.request.Request(
        arm["base_url"].rstrip("/") + "/chat/completions",
        data=json.dumps({"model": arm["model"], "messages": [{"role": "user", "content": prompt}],
                         "max_tokens": 4096}).encode("utf-8"),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"})
    with urllib.request.urlopen(req, timeout=300) as resp:
        o = json.loads(resp.read().decode("utf-8", "replace"))
    text = o["choices"][0]["message"]["content"]
    u = o.get("usage") or {}
    return text, {"input_tokens": u.get("prompt_tokens", 0),
                  "output_tokens": u.get("completion_tokens", 0)}, 0


def run(b):
    rdir = os.path.join(b["workdir"], "results")
    os.makedirs(rdir, exist_ok=True)
    cap = b["hard_cap_tokens"]
    for cell, arm, rep in iter_runs(b):
        cid = cell_id(cell, arm, rep)
        dest = os.path.join(rdir, cid + ".json")
        if os.path.exists(dest):
            print("SKIP", cid); continue
        if spent_tokens(b) >= cap:
            print(f"CAP REACHED ({cap}) — aborting; existing results are PARTIAL")
            sys.exit(3)
        prompt = open(os.path.join(b["workdir"], cell["probe_file"]), encoding="utf-8").read()
        print("RUN ", cid, flush=True)
        try:
            text, usage, rc = (call_cli if arm["kind"] == "cli" else call_http)(arm, prompt)
        except Exception as e:
            print("  FAIL", cid, repr(e)[:120]); continue
        low = text.lower()
        if any(m in low for m in LIMIT_MARKERS) and len(text) < 400:
            print("LIMIT HIT — aborting (exit 42)"); sys.exit(42)
        # Response is DATA: stored verbatim, never parsed for instructions.
        json.dump({"cell": cid, "demand": cell["demand"], "arm": arm["id"], "rep": rep,
                   "response": text, "usage": usage, "rc": rc},
                  open(dest, "w", encoding="utf-8"))
    print("DONE. spent≈", spent_tokens(b))


def blind(b):
    """Blinded packets per (demand, probe, rep): arms shuffled deterministically per
    packet via seeded hash; mapping written to a sealed file the judge must not read."""
    rdir = os.path.join(b["workdir"], "results")
    bdir = os.path.join(b["workdir"], "blind")
    os.makedirs(bdir, exist_ok=True)
    mapping = {}
    for cell in b["cells"]:
        probe = os.path.splitext(cell["probe_file"])[0]
        for rep in range(1, cell.get("n", 3) + 1):
            arms = sorted(b["arms"], key=lambda a: hashlib.md5(
                (b["battery_version"] + probe + str(rep) + a["id"]).encode()).hexdigest())
            pkt = [f"# Packet {cell['demand']}/{probe} rep{rep}",
                   f"RUBRIC file: {cell['rubric_file']}", ""]
            key = {}
            for i, arm in enumerate(arms):
                letter = chr(65 + i)
                key[letter] = arm["id"]
                path = os.path.join(rdir, cell_id(cell, arm, rep) + ".json")
                resp = load(path)["response"] if os.path.exists(path) else "MISSING"
                pkt.append(f"---- OUTPUT {letter} ----\n{resp}\n")
            mapping[f"{cell['demand']}_{probe}_r{rep}"] = key
            open(os.path.join(bdir, f"{cell['demand']}_{probe}_r{rep}.md"), "w",
                 encoding="utf-8").write("\n".join(pkt))
    sealdir = os.path.join(b["workdir"], ".sealed")
    os.makedirs(sealdir, exist_ok=True)
    open(os.path.join(sealdir, "mapping.json"), "w",
         encoding="utf-8").write(json.dumps(mapping, indent=1))
    print(f"blinded packets: {len(mapping)} -> {bdir}  (mapping SEALED - judge must not open)")


def unseal(b):
    sdir = os.path.join(b["workdir"], "scores")
    if not (os.path.isdir(sdir) and os.listdir(sdir)):
        print("REFUSED: no scores/ directory with content — score blind FIRST"); sys.exit(4)
    print(open(os.path.join(b["workdir"], ".sealed", "mapping.json"), encoding="utf-8").read())


def spread(b):
    """Per demand+arm: mean, dispersion (population sd), and whether arms separate."""
    import statistics
    scores = {}
    sdir = os.path.join(b["workdir"], "scores")
    mapping = load(os.path.join(b["workdir"], ".sealed", "mapping.json"))
    for fn in os.listdir(sdir):
        try:
            s = load(os.path.join(sdir, fn))   # {"packet": "...", "scores": {"A": x, ...}}
            key = mapping[s["packet"]]
            demand = s["packet"].split("_")[0]
            for letter, val in s["scores"].items():
                scores.setdefault((demand, key[letter]), []).append(val)
        except Exception as e:
            print("WARN skipping malformed score file %s: %r" % (fn, e), file=sys.stderr)
    out = {}
    for (demand, arm), vals in sorted(scores.items()):
        out.setdefault(demand, {})[arm] = {
            "mean": round(statistics.mean(vals), 3), "n": len(vals),
            "sd": round(statistics.stdev(vals), 3) if len(vals) > 1 else None}  # sample sd: conservative for margin
    for demand, arms in out.items():
        means = [v["mean"] for v in arms.values()]
        sds = [v["sd"] for v in arms.values() if v["sd"] is not None]
        sep = (max(means) - min(means)) > (max(sds) if sds else 0.25)
        out[demand]["_separates"] = bool(sep)
    print(json.dumps(out, indent=1))


if __name__ == "__main__":
    mode, path = sys.argv[1], sys.argv[2]
    b = load(path)
    {"--estimate": estimate, "--run": run, "--blind": blind,
     "--unseal": unseal, "--spread": spread}[mode](b)
