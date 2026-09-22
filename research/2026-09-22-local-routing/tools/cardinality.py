"""E8 — how many categories can a decision model actually handle, and does semantics matter?

Three questions, one model load:

A) K-SWEEP. Candidate sets of size K that ALWAYS contain the ground truth, distractors drawn
   deterministically and NESTED (the K=5 set is a subset of the K=10 set), so the only thing changing
   is how many options share the 192-token head budget. Answers "how many categories?" with a curve
   instead of a number.

B) CASCADE. Whether K groups -> K' members recovers the accuracy a flat K*K' choice loses. Measured
   per level, so the end-to-end projection is a product of two measured numbers, not a guess.

C) SEMANTICS vs KEYWORDS. The same K-sweep with three label styles:
     prose     the SPINE line as written (semantics + keywords)
     keywords  only the highest-IDF terms from that line, no prose
     path      just the file path (near-zero semantics, some keywords)
   If keywords match prose, semantics are not doing the work and labels can be written as term lists,
   which is far cheaper per token — the binding constraint here.
"""
import os, sys, json, math, random, statistics, time
sys.path.insert(0, "tools"); os.environ.setdefault("USE_TF", "0")
import route_local as R, run as H
from pathlib import Path
from laya import Router

H.RUBRIC_CHARS = 100000
SEED = 20260922
KS = [2, 3, 5, 8, 10, 15, 20, 30, 45, 65]
ents = R.entries_with_sections()
bykey = {e["key"]: e for e in ents}

# ---- label styles -----------------------------------------------------------------
docs = [R.tok(e["title"] + " " + e["rubric"]) for e in ents]
df = {}
for d in docs:
    for w in set(d): df[w] = df.get(w, 0) + 1
idf = {w: math.log(1 + (len(docs) - c + 0.5) / (c + 0.5)) for w, c in df.items()}

def keywords(e, n=12):
    seen, out = set(), []
    for w in R.tok(e["title"] + " " + e["rubric"]):
        if w in seen or len(w) < 3: continue
        seen.add(w); out.append(w)
    out.sort(key=lambda w: -idf.get(w, 0))
    return " ".join(out[:n])

STYLE = {"prose": lambda e: f"{e['title']} — {e['rubric']}",
         "keywords": lambda e: keywords(e),
         "path": lambda e: " ".join(e["paths"]).replace("/", " ").replace("-", " ").replace(".md", "")}

# ---- candidate sets: nested distractors -------------------------------------------
rng = random.Random(SEED)
POOL = {}
for t in R.EVAL:
    gt = next((e for e in ents if set(t["expected"]) & set(e["paths"])), None)
    if gt is None: continue
    others = [e for e in ents if e["key"] != gt["key"]]
    rng.shuffle(others)
    POOL[t["id"]] = (t, gt, others)

router = Router(preload=True, device="mps")

def ask(query, cands, style):
    crit = {e["key"]: STYLE[style](e) for e in cands}
    o = router.predict({"request": query},
                       {"f": {"type": "choice",
                              "instructions": "Which knowledge file should be loaded before answering `request`?",
                              "criteria": crit}}, model="english")["answers"]["f"]
    return o["choice"], o["probabilities"]

def sweep(style):
    rows = []
    for K in KS:
        hit = 0; n = 0
        for tid, (t, gt, others) in POOL.items():
            cands = [gt] + others[: K - 1]
            random.Random(SEED + K).shuffle(cands)       # position must not encode the answer
            try:
                choice, _ = ask(t["query"], cands, style)
            except ValueError:
                continue                                  # options exceed the head budget outright
            hit += bool(set(bykey[choice]["paths"]) & (set(t["expected"]) | set(t["acceptable_extra"])))
            n += 1
        per_label = min(48, max(4, (192 - 16) // K))
        rows.append({"K": K, "n": n, "acc": round(hit / n, 3) if n else None,
                     "chance": round(1 / K, 3), "lift": round(hit / n - 1 / K, 3) if n else None,
                     "tokens_per_label": per_label})
        print(f"  {style:9s} K={K:>2} acc={rows[-1]['acc']} (chance {rows[-1]['chance']}) "
              f"lift={rows[-1]['lift']} tok/label={per_label}", flush=True)
    return rows

out = {}
for style in ("prose", "keywords", "path"):
    print(f"[{style}]", flush=True)
    out[style] = sweep(style)

d = Path(f"runs/{time.strftime('%Y%m%dT%H%M%SZ', time.gmtime())}-e8-cardinality")
d.mkdir(parents=True, exist_ok=True)
(d / "summary.json").write_text(json.dumps(out, indent=2))
print("->", d)
