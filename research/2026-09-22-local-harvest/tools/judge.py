#!/usr/bin/env python3
"""Semantic judge for harvest outputs.

Method (two stages, judge = a Claude model, candidates are BLIND — the judge never sees
which model produced what):

  1. `extract`  — decompose the REFERENCE harvest into atomic claims (one fact/signal per
                  claim, tagged with its section A–E). Run once.
  2. `score`    — for one CANDIDATE harvest:
        recall:    for every reference claim, is it PRESENT / PARTIAL / ABSENT in the candidate?
        grounding: decompose the candidate into its own atomic claims and, using the
                   TRANSCRIPT as ground truth, mark each GROUNDED / DISTORTED / FABRICATED.
        spec:      are the five sections present in order; do D) decisions carry an origin?

  Scores reported per candidate:
        recall      = (present + 0.5*partial) / n_reference_claims
        grounding   = grounded / n_candidate_claims
        fabrication = fabricated / n_candidate_claims
  The Opus-vs-Opus rerun sets the ceiling: its recall is what "100% of Opus" means,
  because even the same model does not reproduce its own harvest exactly.

usage: judge.py extract <reference-label>
       judge.py score  <reference-label> <candidate-label> [--judge-model opus]
"""
import json, subprocess, sys, os

import os
ROOT = os.environ.get("EXP") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUNS, JUDGE = os.path.join(ROOT, "runs"), os.path.join(ROOT, "judge")


def claude(system, user, schema, model="opus"):
    cmd = ["claude", "-p", "--model", model, "--tools", "", "--setting-sources", "",
           "--no-session-persistence", "--system-prompt", system, "--output-format", "json",
           "--max-turns", "1", "--json-schema", json.dumps(schema)]
    r = subprocess.run(cmd, input=user, capture_output=True, text=True, check=True)
    d = json.loads(r.stdout)
    so = d.get("structured_output")
    if so is None:
        so = json.loads(d["result"])
    return so, {"cost_usd": d.get("total_cost_usd"), "usage": d.get("usage")}


EXTRACT_SCHEMA = {
    "type": "object",
    "properties": {"claims": {"type": "array", "items": {"type": "object", "properties": {
        "id": {"type": "integer"}, "section": {"type": "string", "enum": ["A", "B", "C", "D", "E"]},
        "claim": {"type": "string"}}, "required": ["id", "section", "claim"]}}},
    "required": ["claims"]}

SCORE_SCHEMA = {
    "type": "object",
    "properties": {
        "recall": {"type": "array", "items": {"type": "object", "properties": {
            "id": {"type": "integer"},
            "status": {"type": "string", "enum": ["PRESENT", "PARTIAL", "ABSENT"]},
            "note": {"type": "string"}}, "required": ["id", "status"]}},
        "candidate_claims": {"type": "array", "items": {"type": "object", "properties": {
            "claim": {"type": "string"},
            "status": {"type": "string", "enum": ["GROUNDED", "DISTORTED", "FABRICATED"]},
            "note": {"type": "string"}}, "required": ["claim", "status"]}},
        "spec": {"type": "object", "properties": {
            "sections_present_in_order": {"type": "boolean"},
            "decisions_have_origin": {"type": "boolean"},
            "commentary_outside_sections": {"type": "boolean"}},
            "required": ["sections_present_in_order", "decisions_have_origin", "commentary_outside_sections"]},
        "qualitative": {"type": "string"}},
    "required": ["recall", "candidate_claims", "spec", "qualitative"]}


def extract(ref):
    system = ("You decompose a structured session summary into ATOMIC claims. One claim = one "
              "verifiable fact, signal, observation or decision. Keep each claim self-contained "
              "(no pronouns referring to other claims). Tag it with the section letter it came "
              "from (A failures, B corrections, C user behavior, D decision origins, E metadata). "
              "Do not merge distinct items; do not add anything not in the summary.")
    text = open(f"{RUNS}/{ref}.md").read()
    so, meta = claude(system, f"<summary>\n{text}\n</summary>\n\nExtract the atomic claims.", EXTRACT_SCHEMA)
    json.dump({"claims": so["claims"], "judge_meta": meta}, open(f"{JUDGE}/{ref}.claims.json", "w"), indent=1)
    print(f"{len(so['claims'])} claims extracted from {ref}; cost ${meta['cost_usd']:.3f}")


def score(ref, cand, model):
    cf = json.load(open(f"{JUDGE}/{ref}.claims.json"))
    if "claims" not in cf:
        sys.exit(f"{JUDGE}/{ref}.claims.json holds no claim texts "
                 f"({cf.get('note', 'redacted')}).\nRun: judge.py extract {ref}")
    claims = cf["claims"]
    transcript = open(f"{RUNS}/transcript.txt").read()
    candidate = open(f"{RUNS}/{cand}.md").read()
    system = ("You are a strict, blind evaluator of session-summary quality. You are given: the "
              "original TRANSCRIPT (ground truth), a list of REFERENCE CLAIMS extracted from a "
              "high-quality summary, and one CANDIDATE summary produced by an unknown system.\n"
              "Task 1 (recall): for EVERY reference claim id, decide whether the candidate states "
              "the same fact (PRESENT), states it only partially or vaguely (PARTIAL), or does not "
              "contain it (ABSENT). Judge meaning, not wording.\n"
              "Task 2 (grounding): decompose the CANDIDATE into its own atomic claims (every "
              "concrete fact, signal, observation or decision it asserts) and check each against "
              "the TRANSCRIPT: GROUNDED (supported), DISTORTED (based on something real but "
              "materially wrong — wrong actor, wrong cause, wrong number, over-claimed), or "
              "FABRICATED (no basis in the transcript).\n"
              "Task 3 (spec): does the candidate have the five sections A–E in order; do items in "
              "section D carry an origin classification (evidence/directive/convention/constraint); "
              "is there commentary outside the sections?\n"
              "Finally give a 2–4 sentence qualitative verdict on where the candidate is weaker or "
              "stronger than the reference claims. Be exacting: PRESENT requires the specific fact, "
              "not the general topic.")
    user = (f"<transcript>\n{transcript}\n</transcript>\n\n<reference_claims>\n"
            + "\n".join(f"[{c['id']}] ({c['section']}) {c['claim']}" for c in claims)
            + f"\n</reference_claims>\n\n<candidate>\n{candidate}\n</candidate>\n\nEvaluate now.")
    so, meta = claude(system, user, SCORE_SCHEMA, model)
    n = len(claims)
    st = [r["status"] for r in so["recall"]]
    cc = [c["status"] for c in so["candidate_claims"]]
    summary = {
        "candidate": cand, "reference": ref, "judge_model": model,
        "n_ref_claims": n, "present": st.count("PRESENT"), "partial": st.count("PARTIAL"), "absent": st.count("ABSENT"),
        "recall": round((st.count("PRESENT") + 0.5 * st.count("PARTIAL")) / n, 3),
        "n_cand_claims": len(cc), "grounded": cc.count("GROUNDED"), "distorted": cc.count("DISTORTED"), "fabricated": cc.count("FABRICATED"),
        "grounding": round(cc.count("GROUNDED") / max(1, len(cc)), 3),
        "fabrication": round(cc.count("FABRICATED") / max(1, len(cc)), 3),
        "spec": so["spec"], "qualitative": so["qualitative"], "judge_cost_usd": meta["cost_usd"],
    }
    json.dump({"summary": summary, "detail": so}, open(f"{JUDGE}/{cand}.score.json", "w"), indent=1)
    print(json.dumps(summary, indent=1))


if __name__ == "__main__":
    os.makedirs(JUDGE, exist_ok=True)
    if sys.argv[1] == "extract":
        extract(sys.argv[2])
    elif sys.argv[1] == "score":
        m = "opus"
        if "--judge-model" in sys.argv:
            m = sys.argv[sys.argv.index("--judge-model") + 1]
        score(sys.argv[2], sys.argv[3], m)
