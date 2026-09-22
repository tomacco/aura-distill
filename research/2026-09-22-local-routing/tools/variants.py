#!/usr/bin/env python3
"""E1b — zero-model router variants. All CPU, <20 MB RSS, no network.

Arms
  bm25-full    BM25 over the whole SPINE bullet (title + description)
  bm25-title   BM25 over the title + file path only (what a 'diet' SPINE would keep)
  bm25-body    BM25 over the FILE BODY (first 2k chars of each knowledge file) — tests whether the
               index text or the content is the better retrieval surface
  bm25-bodyfull the WHOLE knowledge file, not the first 2k
  bm25-hybrid  max(bm25-full, bm25-body) per entry
  rrf-*        reciprocal-rank fusion (k=60) of two or three of the above

All six arms are declared here and reported together; the winner is NOT re-tuned afterwards. With
30 queries a 1-topic difference is 3.3 points, so treat gaps under ~10 points as noise.
Reports hit@1/@3, MRR, recall@N curve and the expected-token cost of an N-shortlist.
"""
import json, statistics, sys, time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import run as H, route_local as R

H.RUBRIC_CHARS = 100000
CPT, SPINE_T = 3.5, 21247
D = Path.home()/".claude"/"distill"


def build(kind, ents):
    docs = []
    for e in ents:
        path_words = e["key"].replace("/", " ").replace("-", " ").replace(".md", "")
        if kind == "bm25-full":   docs.append(e["title"]+" "+e["rubric"]+" "+path_words)
        elif kind == "bm25-title": docs.append(e["title"]+" "+path_words)
        elif kind == "bm25-body":
            body = " ".join((D/p).read_text()[:2000] for p in e["paths"] if (D/p).exists())
            docs.append(e["title"]+" "+path_words+" "+body)
        elif kind == "bm25-bodyfull":
            body = " ".join((D/p).read_text() for p in e["paths"] if (D/p).exists())
            docs.append(e["title"]+" "+path_words+" "+body)
    lx = R.Lexical.__new__(R.Lexical)
    lx.ents = ents
    lx.docs = [R.tok(d) for d in docs]
    lx.N = len(lx.docs); lx.avg = sum(map(len, lx.docs))/lx.N
    df = {}
    for d in lx.docs:
        for w in set(d): df[w] = df.get(w, 0)+1
    import math
    lx.idf = {w: math.log(1+(lx.N-n+0.5)/(n+0.5)) for w, n in df.items()}
    return lx


class RRF:
    """Reciprocal-rank fusion: score = sum 1/(k + rank). Rank-based, so it does not need the
    component scores to be on the same scale (which is exactly where max-normalisation failed)."""
    def __init__(self, *rs, k=60): self.rs, self.k, self.ents = rs, k, rs[0].ents
    def rank(self, q):
        sc = {}
        for r in self.rs:
            for i, (key, _) in enumerate(r.rank(q)): sc[key] = sc.get(key, 0) + 1/(self.k+i+1)
        return sorted(sc.items(), key=lambda x: -x[1])


class Hybrid:
    def __init__(self, a, b): self.a, self.b, self.ents = a, b, a.ents
    def rank(self, q):
        ra, rb = dict(self.a.rank(q)), dict(self.b.rank(q))
        ma, mb = max(ra.values()) or 1, max(rb.values()) or 1
        s = {k: max(ra.get(k,0)/ma, rb.get(k,0)/mb) for k in ra}
        return sorted(s.items(), key=lambda x: -x[1])


def evaluate(name, router, ents):
    rows = []
    for t in R.EVAL:
        t0 = time.monotonic(); ranked = router.rank(t["query"]); ms = 1000*(time.monotonic()-t0)
        rows.append({"id": t["id"], "tier": t["tier"], "latency_ms": round(ms,2), **R.score(ranked, ents, t)})
    s = R.summarize(rows)
    bl = [len(e["rubric"])/CPT for e in ents]; mean_b = statistics.mean(bl)
    curve = {}
    for N in (1,3,5,8,10,15):
        rec = sum(1 for r in rows if r["rank"] and r["rank"] <= N)/len(rows)
        cost = N*(mean_b+15)+40
        curve[N] = {"recall": round(rec,3), "exp_tokens": round(cost+(1-rec)*(SPINE_T+cost)),
                    "saving_pct": round(100*(1-(cost+(1-rec)*(SPINE_T+cost))/SPINE_T),1)}
    return {"arm": name, **s, "shortlist": curve,
            "misses": [{"id": r["id"], "rank": r["rank"], "top1": r["top1"]} for r in rows if not r["hit1"]]}, rows


def main():
    ents = R.entries_with_sections()
    routers = {k: build(k, ents) for k in ("bm25-full","bm25-title","bm25-body","bm25-bodyfull")}
    routers["bm25-hybrid"] = Hybrid(routers["bm25-full"], routers["bm25-body"])
    routers["rrf-full+body2k"] = RRF(routers["bm25-full"], routers["bm25-body"])
    routers["rrf-full+bodyfull"] = RRF(routers["bm25-full"], routers["bm25-bodyfull"])
    routers["rrf-all3"] = RRF(routers["bm25-full"], routers["bm25-body"], routers["bm25-bodyfull"])
    out = {}
    allrows = {}
    for k, r in routers.items():
        out[k], allrows[k] = evaluate(k, r, ents)
        a = out[k]
        print(f"{k:12s} hit@1 {a['all']['hit@1']:.2f} (easy {a['easy']['hit@1']:.2f} / hard {a['hard']['hit@1']:.2f})  "
              f"hit@3 {a['all']['hit@3']:.2f}  mrr {a['all']['mrr']:.3f}  "
              f"best-N {min(a['shortlist'], key=lambda n: a['shortlist'][n]['exp_tokens'])} "
              f"-> {max(v['saving_pct'] for v in a['shortlist'].values()):.0f}% saving")
    dest = H.REPO/"runs"/f"{time.strftime('%Y%m%dT%H%M%SZ', time.gmtime())}-e1b-zero-model"
    dest.mkdir(parents=True, exist_ok=True)
    (dest/"summary.json").write_text(json.dumps(out, indent=2))
    (dest/"results.jsonl").write_text("\n".join(json.dumps({"arm":k,**r}) for k,rs in allrows.items() for r in rs)+"\n")
    print("->", dest)

if __name__ == "__main__": main()
