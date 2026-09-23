"""E7 — does SPINE QUALITY limit the decision model, or does the file content?

Direct test of the claim "with the current state of the SPINE files we barely see improvement from a
decision model". Same E6 gate, same 90 balanced items, same prompt — only the candidate DESCRIPTION
changes:

  spine-line    the SPINE bullet for the candidate (what the index says about the file)
  file-head     the first 1400 chars of the file (mostly YAML front-matter)  [E6a/E6b state]
  best-passage  the BM25-best 500-char window of the file                    [E6c state]

If spine-line performs like best-passage, the index text is fine and the model is the limit.
If spine-line performs like file-head, the SPINE lines are the weak link and rewriting them is the
lever. Either answer settles the claim.
"""
import os, sys, json, statistics
sys.path.insert(0,'tools'); os.environ.setdefault("USE_TF","0")
import gate, route_local as R
from pathlib import Path
from laya import Router
D=Path.home()/".claude"/"distill"
ents=R.entries_with_sections(); items=gate.build_items(ents)
router=Router(preload=True, device="mps")

def best_passage(paths, query, win=500, step=250):
    q=set(R.tok(query)); best=("",-1)
    for p in paths:
        f=D/p
        if not f.exists(): continue
        t=f.read_text(errors="replace")
        for i in range(0,max(1,len(t)-win+1),step):
            w=t[i:i+win]; s=len(q & set(R.tok(w)))
            if s>best[1]: best=(w,s)
    return best[0]

Q={"a":{"type":"choice",
  "instructions":"A knowledge file was retrieved for a request. Most retrieved files are WRONG. Judge strictly: does `file` specifically address `request`?",
  "criteria":{"yes":"the file's subject matter is the same as what the request is about",
              "no":"the file is about a different tool, machine, project or topic"}}}

SRC={"spine-line":   lambda it: it["cand"]["rubric"],
     "file-head":    lambda it: gate.file_head(it["cand"]["paths"]),
     "best-passage": lambda it: best_passage(it["cand"]["paths"], it["q"]),
     "spine+passage":lambda it: it["cand"]["rubric"][:400]+"\n"+best_passage(it["cand"]["paths"], it["q"])}
out={}
for label, mk in SRC.items():
    rows=[]
    for it in items:
        st={"request": it["q"], "file": f"{it['cand']['title']}\n{mk(it)}"}
        o=router.predict(st,Q,model="english")["answers"]["a"]
        rows.append({"kind":it["kind"],"truth":it["truth"],"p":o["probabilities"].get("yes",0.0),"choice":o["choice"]})
    pos=[r for r in rows if r["kind"]=="positive"]; neg=[r for r in rows if r["kind"]=="negative"]
    acc=lambda rs: sum((r["choice"]=="yes")==r["truth"] for r in rs)/len(rs)
    tp=sorted(r["p"] for r in rows if r["truth"]); fp=sorted(r["p"] for r in rows if not r["truth"])
    best=max(((sum(p>=th for p in tp)/len(tp)+sum(p<th for p in fp)/len(fp))/2, th) for th in [i/100 for i in range(1,100)])
    out[label]={"recall":round(acc(pos),3),"specificity":round(acc(neg),3),
                "balanced_acc":round((acc(pos)+acc(neg))/2,3),
                "p_true_med":round(statistics.median(tp),4),"p_false_med":round(statistics.median(fp),4),
                "gap":round(statistics.median(tp)-statistics.median(fp),4),
                "best_thr_bal_acc":round(best[0],3)}
    print(f"{label:14s} {json.dumps(out[label])}", flush=True)
import time
d=Path(f"runs/{time.strftime('%Y%m%dT%H%M%SZ',time.gmtime())}-e7-spine-vs-body"); d.mkdir(parents=True,exist_ok=True)
(d/"summary.json").write_text(json.dumps(out,indent=2)); print("->",d)
