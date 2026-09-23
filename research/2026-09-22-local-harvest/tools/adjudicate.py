#!/usr/bin/env python3
"""Calibrated re-adjudication of the DISTORTED / FABRICATED boundary.

Why this exists: each candidate was scored in an independent `claude -p` call, so the
boundary between "based on something real but materially wrong" (DISTORTED) and "no basis
in the transcript" (FABRICATED) drifted between runs. An independent review found notes
reading "no such assumption appears in the transcript... invented" filed as DISTORTED for
one candidate and as FABRICATED for another.

Fix: pool EVERY non-GROUNDED claim from all candidates into ONE call, blind (no model
labels, shuffled, no indication of which candidate a claim came from), with a pinned rubric
and worked examples. One boundary, applied once, to all of them.

usage: adjudicate.py   -> writes judge/adjudication.json and patches every score file
"""
import glob, json, os, random, subprocess, sys

ROOT = os.environ.get("EXP") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUNS, JUDGE = os.path.join(ROOT, "runs"), os.path.join(ROOT, "judge")

RUBRIC = """You are re-adjudicating one specific boundary in a summary-evaluation task, over a
pooled set of claims drawn from SEVERAL different systems. You are not told which system
produced which claim, and the order is randomised. Apply ONE consistent standard to all of them.

Each claim was already judged "not fully grounded" against the transcript. Your only job is to
sort each into exactly one of two buckets, using the transcript as ground truth:

  DISTORTED  — the claim is anchored to something that genuinely happened in the transcript,
               but states it materially wrongly: wrong actor, wrong cause, wrong number,
               wrong direction, or over-claimed strength. There IS a real referent.
  FABRICATED — the claim asserts an event, belief, assumption, hypothesis, statement or
               reaction that has NO referent in the transcript at all. Nothing happened that
               this claim is a distorted version of. Inventing an assumption someone never
               held, a hypothesis never stated, or a reaction that never occurred is
               FABRICATED, not DISTORTED — even when the surrounding topic is real.

Worked examples, to pin the boundary:

  "The knowledge base rule is <path A>; the candidate presents <path B> as a KB fact."
      -> DISTORTED. The KB rule exists; the path is wrong.
  "The tool was called ~30 times" when the transcript shows ~37.
      -> DISTORTED. Real quantity, wrong number.
  "The assistant assumed editing the config would fix it" when the assistant never held or
  expressed that assumption anywhere in the transcript.
      -> FABRICATED. There is no real assumption being mis-stated; it was invented.
  "Before the benchmark the assistant's hypothesis was X" when no such prior hypothesis
  appears anywhere.
      -> FABRICATED. Invented mental state.
  "The user signalled acceptance via a follow-up" when the transcript contains no such
  follow-up.
      -> FABRICATED. Invented event.
  "The user reasons from principles: <principle>" where the principle was actually proposed
  by the assistant, not the user.
      -> DISTORTED. The principle is real in the transcript; the attribution is wrong.

Return a verdict for every claim id you are given. Be consistent: two claims with the same
shape must get the same label."""

SCHEMA = {"type": "object", "properties": {"verdicts": {"type": "array", "items": {"type": "object",
    "properties": {"id": {"type": "integer"},
                   "status": {"type": "string", "enum": ["DISTORTED", "FABRICATED"]},
                   "reason": {"type": "string"}},
    "required": ["id", "status", "reason"]}}}, "required": ["verdicts"]}

pool = []
for p in sorted(glob.glob(f"{JUDGE}/*.score.json")):
    label = os.path.basename(p).replace(".score.json", "")
    d = json.load(open(p))
    for i, c in enumerate(d["detail"]["candidate_claims"]):
        if c["status"] != "GROUNDED":
            pool.append({"label": label, "idx": i, "claim": c["claim"],
                         "note": c.get("note", ""), "old": c["status"]})

random.seed(97)
random.shuffle(pool)
for n, item in enumerate(pool, 1):
    item["id"] = n

transcript = open(f"{RUNS}/transcript.txt").read()
user = (f"<transcript>\n{transcript}\n</transcript>\n\n<claims>\n"
        + "\n\n".join(f"[{i['id']}] CLAIM: {i['claim']}\n      PRIOR NOTE: {i['note']}" for i in pool)
        + "\n</claims>\n\nAdjudicate every claim id.")

r = subprocess.run(["claude", "-p", "--model", "opus", "--tools", "", "--setting-sources", "",
                    "--no-session-persistence", "--system-prompt", RUBRIC, "--output-format", "json",
                    "--max-turns", "1", "--json-schema", json.dumps(SCHEMA)],
                   input=user, capture_output=True, text=True, check=True)
res = json.loads(r.stdout)
so = res.get("structured_output") or json.loads(res["result"])
v = {x["id"]: x for x in so["verdicts"]}
missing = [i["id"] for i in pool if i["id"] not in v]
if missing:
    sys.exit(f"FATAL: adjudicator skipped ids {missing}")

for item in pool:
    item["new"] = v[item["id"]]["status"]
    item["reason"] = v[item["id"]]["reason"]

json.dump({"cost_usd": res.get("total_cost_usd"), "n": len(pool),
           "changed": sum(1 for i in pool if i["new"] != i["old"]), "pool": pool},
          open(f"{JUDGE}/adjudication.json", "w"), indent=1)

# Patch the score files and recompute the ratios
for p in sorted(glob.glob(f"{JUDGE}/*.score.json")):
    label = os.path.basename(p).replace(".score.json", "")
    d = json.load(open(p))
    for item in pool:
        if item["label"] == label:
            cc = d["detail"]["candidate_claims"][item["idx"]]
            cc["status"] = item["new"]
            cc["adjudicated"] = True
            cc["reason"] = item["reason"]
    st = [c["status"] for c in d["detail"]["candidate_claims"]]
    s = d["summary"]
    s.update({"grounded": st.count("GROUNDED"), "distorted": st.count("DISTORTED"),
              "fabricated": st.count("FABRICATED"),
              "grounding": round(st.count("GROUNDED") / len(st), 3),
              "fabrication": round(st.count("FABRICATED") / len(st), 3),
              "adjudicated": True})
    json.dump(d, open(p, "w"), indent=1)
    print(f"{label:24} grounded {s['grounded']:2}  distorted {s['distorted']:2}  "
          f"fabricated {s['fabricated']:2}  ({s['fabrication']:.3f})")
print(f"\n{sum(1 for i in pool if i['new'] != i['old'])}/{len(pool)} labels changed; "
      f"cost ${res.get('total_cost_usd'):.3f}")
