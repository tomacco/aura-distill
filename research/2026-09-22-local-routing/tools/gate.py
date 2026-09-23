#!/usr/bin/env python3
"""E6 — the fair test of Laya: a two-option relevance GATE, not a 65-way ranking.

E3 concluded that Laya loses to BM25 at routing. That conclusion is weak on its own, because ranking
65 files from a short request is a high-cardinality retrieval problem — BM25's home turf and not what
a 421M classifier is built for. This is the same model on the shape it IS built for: few options,
rich state, one judgment call.

    state    = the request + the candidate file's own content
    question = "does this file answer this request?"  (yes / no)

That is the one question BM25 provably cannot answer (E2b: no zero-model signal separates its hits
from its misses), so a win here would be a real complement, not a replacement.

Item construction — deliberately BALANCED, because the honest version of this test needs a negative
class and BM25's own misses are only 4/30:
  positive  (request, its ground-truth file)                 -> expect yes
  negative  (request, a deterministically-chosen wrong file) -> expect no
  realistic (request, BM25's top-1) for every topic          -> expect yes iff BM25 was right
The first two are scored as balanced accuracy; the third is what a deployed gate would actually see.

Laya's max_len is 512 tokens total, of which the head takes ~192, so only ~700 chars of file content
reach the model. That is a property of the model, not of this harness, and it is reported.
"""
from __future__ import annotations
import argparse, json, os, random, statistics, sys, time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run as H, route_local as R, variants as V

H.RUBRIC_CHARS = 100000
D = Path.home()/".claude"/"distill"
STATE_CHARS = 1400          # ~614 tokens; Laya truncates to its own budget, we do not pre-decide it


def file_head(paths, n=STATE_CHARS):
    for p in paths:
        f = D/p
        if f.exists():
            return f.read_text(errors="replace")[:n]
    return ""


def build_items(ents, seed=20260922):
    rng = random.Random(seed)
    bykey = {e["key"]: e for e in ents}
    pre = V.RRF(V.build("bm25-full", ents), V.build("bm25-bodyfull", ents))
    items = []
    for t in R.EVAL:
        gt = next((e for e in ents if set(t["expected"]) & set(e["paths"])), None)
        if gt is None:
            continue
        wrong = rng.choice([e for e in ents if e["key"] != gt["key"]
                            and not (set(t["expected"]) | set(t["acceptable_extra"])) & set(e["paths"])])
        top1 = bykey[pre.rank(t["query"])[0][0]]
        bm25_right = bool((set(t["expected"]) | set(t["acceptable_extra"])) & set(top1["paths"]))
        items += [
            {"kind": "positive", "id": t["id"], "tier": t["tier"], "q": t["query"], "cand": gt, "truth": True},
            {"kind": "negative", "id": t["id"], "tier": t["tier"], "q": t["query"], "cand": wrong, "truth": False},
            {"kind": "realistic", "id": t["id"], "tier": t["tier"], "q": t["query"], "cand": top1, "truth": bm25_right},
        ]
    return items


def run(device=None, reps=1):
    os.environ.setdefault("USE_TF", "0")
    from laya import Router
    ents = R.entries_with_sections()
    items = build_items(ents)
    t0 = time.monotonic(); router = Router(preload=True, device=device); load_s = round(time.monotonic()-t0, 1)
    q = {"answers": {"type": "choice",
                     "instructions": "Does the knowledge file shown in `file` contain the information needed to handle `request`?",
                     "criteria": {"yes": "the file covers the task, tool, project or machine the request is about",
                                  "no": "the file is about something else"}}}
    rows = []
    router.predict({"request": "warm up", "file": "warm up"}, q, model="english")     # not scored
    for it in items:
        state = {"request": it["q"], "file": f"{it['cand']['title']}\n{file_head(it['cand']['paths'])}"}
        lat = []
        for _ in range(reps):
            a = time.monotonic()
            out = router.predict(state, q, model="english")["answers"]["answers"]
            lat.append(time.monotonic()-a)
        p_yes = out["probabilities"].get("yes", 0.0)
        rows.append({**{k: it[k] for k in ("kind", "id", "tier", "truth")},
                     "cand": it["cand"]["key"], "p_yes": round(p_yes, 4),
                     "choice": out["choice"], "conf": round(out.get("confidence", 0), 4),
                     "latency_ms": round(1000*min(lat), 1)})
    return rows, load_s, len(ents)


def report(rows):
    def acc(rs): return round(sum((r["choice"] == "yes") == r["truth"] for r in rs)/len(rs), 3) if rs else None
    pos = [r for r in rows if r["kind"] == "positive"]
    neg = [r for r in rows if r["kind"] == "negative"]
    rea = [r for r in rows if r["kind"] == "realistic"]
    out = {"n": len(rows), "load_s": None,
           "positive_recall": acc(pos), "negative_specificity": acc(neg),
           "balanced_accuracy": round((acc(pos)+acc(neg))/2, 3),
           "realistic_accuracy": acc(rea),
           "latency_ms_median": statistics.median(r["latency_ms"] for r in rows)}
    # the decisive question: does p_yes separate truth from falsehood?
    yes_p = sorted(r["p_yes"] for r in rows if r["truth"])
    no_p = sorted(r["p_yes"] for r in rows if not r["truth"])
    out["p_yes_true_median"] = statistics.median(yes_p)
    out["p_yes_false_median"] = statistics.median(no_p)
    out["separable"] = max(no_p) < min(yes_p)
    best = max(((sum(p >= th for p in yes_p)/len(yes_p) + sum(p < th for p in no_p)/len(no_p))/2, th)
               for th in [i/100 for i in range(1, 100)])
    out["best_threshold"] = {"balanced_accuracy": round(best[0], 3), "threshold": best[1]}
    rea_true = [r["p_yes"] for r in rea if r["truth"]]; rea_false = [r["p_yes"] for r in rea if not r["truth"]]
    out["realistic_gate"] = {"n_bm25_right": len(rea_true), "n_bm25_wrong": len(rea_false),
                             "p_yes_when_bm25_right_median": round(statistics.median(rea_true), 4) if rea_true else None,
                             "p_yes_when_bm25_wrong": sorted(round(x, 4) for x in rea_false)}
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--device", default=None); ap.add_argument("--reps", type=int, default=1)
    a = ap.parse_args()
    rows, load_s, n_ents = run(a.device, a.reps)
    summ = report(rows); summ["load_s"] = load_s; summ["n_entries"] = n_ents
    summ["state_chars"] = STATE_CHARS
    import resource
    summ["max_rss_mb"] = round(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss/2**20)
    dest = H.REPO/"runs"/f"{time.strftime('%Y%m%dT%H%M%SZ', time.gmtime())}-e6-laya-gate"
    dest.mkdir(parents=True, exist_ok=True)
    (dest/"results.jsonl").write_text("\n".join(json.dumps(r) for r in rows)+"\n")
    (dest/"summary.json").write_text(json.dumps(summ, indent=2))
    print(json.dumps(summ, indent=2)); print("->", dest)


if __name__ == "__main__":
    main()
