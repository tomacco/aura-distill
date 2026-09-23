#!/usr/bin/env python3
"""E1 — offline SPINE routing eval: local routers vs the eval set (topics-eval.json).

Routers
  lexical   BM25 over the SPINE bullet text (zero-model CONTROL arm; pure python)
  laya-yn   Laya (local, MPS): one yes/no choice PER SPINE entry, all 65 in ONE forward pass,
            rank entries by P(yes)
  laya-hier Laya: choice over sections, then choice over that section's entries (title labels)
  laya-rerank BM25 (the E1 winner) shortlists K entries, Laya runs ONE choice over just those.
            This is laya.shortlist's own coarse-to-fine pattern with BM25 in place of an embedding
            model: a 65-option choice cannot work, because choice options share ONE 192-token
            head budget (laya/common.py build_sequence), leaving ~3 tokens per label at n=65.

Usage
  python3 tools/route_local.py lexical
  .venv/bin/python tools/route_local.py laya-yn      (from ~/repos/laya-lab venv)
  python3 tools/route_local.py report runs/<dir>
Writes runs/<stamp>-e1-<router>/{results.jsonl,summary.json}.
"""
from __future__ import annotations
import argparse, datetime as dt, json, math, os, re, resource, sys, time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run as H  # spine_entries, REPO, SPINE

EVAL = json.loads((H.REPO / "topics-eval.json").read_text())["topics"]
SECTION_RE = re.compile(r"^## (.+)$")


def entries_with_sections():
    """spine_entries() plus the '## Section' each bullet sits under."""
    ents = H.spine_entries()
    sec, out, i = None, [], 0
    for line in H.SPINE.read_text().splitlines():
        m = SECTION_RE.match(line)
        if m:
            sec = m.group(1).split("(")[0].strip()
        if line.startswith("- [") and i < len(ents) and re.findall(r"\[([^\]]+)\]\(([^)]+\.md)\)", line):
            e = dict(ents[i]); e["section"] = sec
            e["title"] = re.match(r"\[([^\]]+)\]", line[2:]).group(1)
            out.append(e); i += 1
    return out


def tok(s: str):
    return re.findall(r"[a-z0-9]+", s.lower())


# ----------------------------------------------------------------------------- routers
class Lexical:
    name = "lexical"
    def __init__(self, ents):
        self.ents = ents
        self.docs = [tok(e["title"] + " " + e["rubric"] + " " + e["key"].replace("/", " ").replace("-", " ")) for e in ents]
        self.N = len(self.docs); self.avg = sum(map(len, self.docs)) / self.N
        df = {}
        for d in self.docs:
            for w in set(d): df[w] = df.get(w, 0) + 1
        self.idf = {w: math.log(1 + (self.N - n + 0.5) / (n + 0.5)) for w, n in df.items()}
    def rank(self, query: str):
        q = tok(query); k1, b = 1.5, 0.75
        scores = []
        for i, d in enumerate(self.docs):
            tf = {}
            for w in d: tf[w] = tf.get(w, 0) + 1
            s = 0.0
            for w in q:
                if w in tf:
                    f = tf[w]; s += self.idf[w] * f * (k1 + 1) / (f + k1 * (1 - b + b * len(d) / self.avg))
            scores.append((s, i))
        scores.sort(reverse=True)
        return [(self.ents[i]["key"], round(s, 3)) for s, i in scores]


class LayaYN:
    name = "laya-yn"
    def __init__(self, ents, device=None):
        os.environ.setdefault("USE_TF", "0")
        from laya import Router
        t0 = time.monotonic()
        self.router = Router(preload=True, device=device)
        self.load_s = round(time.monotonic() - t0, 1)
        self.ents = ents
        self.questions = {
            e["key"]: {"type": "choice",
                        "instructions": f"Knowledge file: {e['title']} — {e['rubric'][:300]}. Should this file be loaded before handling the user's request?",
                        "criteria": {"yes": "the file covers the task, tool, project or machine the request is about",
                                     "no": "the file is about something else"}}
            for e in ents}
    def rank(self, query: str):
        out = self.router.predict({"request": query}, self.questions, model="english")
        p = {k: v["probabilities"].get("yes", 0.0) for k, v in out["answers"].items()}
        return sorted(((k, round(v, 4)) for k, v in p.items()), key=lambda x: -x[1])


class LayaHier:
    name = "laya-hier"
    def __init__(self, ents, device=None):
        os.environ.setdefault("USE_TF", "0")
        from laya import Router
        t0 = time.monotonic()
        self.router = Router(preload=True, device=device)
        self.load_s = round(time.monotonic() - t0, 1)
        self.ents = ents
        self.sections = {}
        for e in ents: self.sections.setdefault(e["section"], []).append(e)
    def rank(self, query: str):
        st = {"request": query}
        q1 = {"section": {"type": "choice", "instructions": "Which section of the knowledge index covers the request?",
                          "criteria": {s: ", ".join(e["title"] for e in es)[:150] for s, es in self.sections.items()}}}
        o1 = self.router.predict(st, q1, model="english")["answers"]["section"]["probabilities"]
        ranked = []
        for sec, ps in sorted(o1.items(), key=lambda x: -x[1]):
            es = self.sections[sec]
            crit = {e["key"]: e["title"][:60] for e in es}
            try:
                o2 = self.router.predict(st, {"file": {"type": "choice", "instructions": "Which knowledge file should be loaded for the request?", "criteria": crit}}, model="english")["answers"]["file"]["probabilities"]
            except ValueError as ex:  # options exceed head_max_len -> split in halves
                o2 = {}
                keys = list(crit)
                for half in (keys[: len(keys) // 2], keys[len(keys) // 2:]):
                    o = self.router.predict(st, {"file": {"type": "choice", "instructions": "Which knowledge file should be loaded for the request?", "criteria": {k: crit[k] for k in half}}}, model="english")["answers"]["file"]["probabilities"]
                    o2.update({k: v * 0.5 for k, v in o.items()})
            ranked += [(k, round(ps * pf, 4)) for k, pf in o2.items()]
        return sorted(ranked, key=lambda x: -x[1])


class LayaRerank:
    """BM25 shortlist -> Laya choice over K. K is capped by the head budget, not by taste:
    192 tokens across K labels, so K=10 leaves ~19 tokens per label, K=20 leaves ~9."""
    name = "laya-rerank"
    K = 10

    def __init__(self, ents, device=None):
        os.environ.setdefault("USE_TF", "0")
        import variants as V
        from laya import Router
        t0 = time.monotonic()
        self.router = Router(preload=True, device=device)
        self.load_s = round(time.monotonic() - t0, 1)
        self.ents = ents
        self.pre = V.RRF(V.build("bm25-full", ents), V.build("bm25-bodyfull", ents))

    def rank(self, query: str):
        shortlist = [k for k, _ in self.pre.rank(query)[: self.K]]
        bykey = {e["key"]: e for e in self.ents}
        crit = {k: bykey[k]["title"][:60] for k in shortlist}
        out = self.router.predict({"request": query},
                                  {"file": {"type": "choice",
                                            "instructions": "Which knowledge file should be loaded before answering `request`?",
                                            "criteria": crit}}, model="english")
        p = out["answers"]["file"]["probabilities"]
        reranked = sorted(((k, round(v, 4)) for k, v in p.items()), key=lambda x: -x[1])
        tail = [(k, 0.0) for k, _ in self.pre.rank(query)[self.K:]]   # keep recall@N measurable past K
        return reranked + tail


ROUTERS = {c.name: c for c in (Lexical, LayaYN, LayaHier, LayaRerank)}


# ----------------------------------------------------------------------------- eval
def score(ranked, ents, topic):
    """Ranking quality for one topic. `top1_score` is kept so a run can be checked for the E2b
    question: does this router's own score separate its hits from its misses?"""
    bykey = {e["key"]: e for e in ents}
    ok = set(topic["expected"]); extra = set(topic["acceptable_extra"])
    def hit(k): return bool(ok & set(bykey[k]["paths"]))
    rank = next((i + 1 for i, (k, _) in enumerate(ranked) if hit(k)), None)
    return {"rank": rank, "hit1": rank == 1, "hit3": rank is not None and rank <= 3,
            "rr": (1 / rank) if rank else 0.0,
            "top1_acceptable": rank == 1 or bool(extra & set(bykey[ranked[0][0]]["paths"])),
            "top1": ranked[0][0], "top3": [k for k, _ in ranked[:3]], "top1_score": ranked[0][1]}


def cmd_run(a):
    ents = entries_with_sections()
    r = ROUTERS[a.router](ents) if a.router == "lexical" else ROUTERS[a.router](ents, a.device)
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out = H.REPO / "runs" / f"{stamp}-e1-{a.router}"; out.mkdir(parents=True)
    rows = []
    # warm-up (not scored): first MPS call compiles kernels
    if a.router != "lexical": r.rank("warm up")
    for t in EVAL:
        lat = []
        for _ in range(a.reps):
            t0 = time.monotonic(); ranked = r.rank(t["query"]); lat.append(time.monotonic() - t0)
        row = {"id": t["id"], "tier": t["tier"], "latency_ms": round(1000 * min(lat), 1), "latency_ms_all": [round(1000 * x, 1) for x in lat], **score(ranked, ents, t)}
        rows.append(row); print(json.dumps(row), flush=True)
    (out / "results.jsonl").write_text("\n".join(json.dumps(x) for x in rows) + "\n")
    summ = summarize(rows)
    summ["abstention"] = abstention(rows)
    summ.update({"router": a.router, "n_entries": len(ents), "load_s": getattr(r, "load_s", 0),
                 "max_rss_mb": round(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 2**20, 0),
                 "device": a.device, "stamp": stamp})
    (out / "summary.json").write_text(json.dumps(summ, indent=2))
    print(json.dumps(summ, indent=2)); print("->", out)


def abstention(rows):
    """E2b: can this router's own top-1 score tell a hit from a miss? Reported for EVERY arm,
    because a router that cannot abstain cannot be trusted to replace the full index read."""
    h = sorted(r["top1_score"] for r in rows if r["hit1"])
    m = sorted(r["top1_score"] for r in rows if not r["hit1"])
    if not h or not m:
        return {"note": "all hits or all misses; nothing to separate"}
    return {"hit_min": h[0], "hit_median": h[len(h)//2], "miss_max": m[-1], "miss_median": m[len(m)//2],
            "separable": m[-1] < h[0]}


def summarize(rows):
    def agg(rs):
        n = len(rs)
        if not n: return {}
        return {"n": n, "hit@1": round(sum(r["hit1"] for r in rs) / n, 3), "hit@3": round(sum(r["hit3"] for r in rs) / n, 3),
                "top1_acceptable": round(sum(r["top1_acceptable"] for r in rs) / n, 3),
                "mrr": round(sum(r["rr"] for r in rs) / n, 3),
                "latency_ms_median": sorted(r["latency_ms"] for r in rs)[n // 2]}
    return {"all": agg(rows), "easy": agg([r for r in rows if r["tier"] == "easy"]), "hard": agg([r for r in rows if r["tier"] == "hard"])}


def cmd_report(a):
    rows = [json.loads(l) for l in (Path(a.run) / "results.jsonl").read_text().splitlines()]
    print(json.dumps(summarize(rows), indent=2))
    for r in rows:
        if not r["hit1"]: print(f"MISS {r['id']} rank={r['rank']} top3={r['top3']}")


def main():
    p = argparse.ArgumentParser(); s = p.add_subparsers(dest="cmd", required=True)
    for name in ROUTERS:
        q = s.add_parser(name); q.add_argument("--reps", type=int, default=3); q.add_argument("--device", default=None); q.set_defaults(fn=cmd_run, router=name)
    q = s.add_parser("report"); q.add_argument("run"); q.set_defaults(fn=cmd_report)
    a = p.parse_args(); a.fn(a)

if __name__ == "__main__":
    main()
