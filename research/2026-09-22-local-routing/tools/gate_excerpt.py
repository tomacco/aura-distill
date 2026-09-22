"""E6c — is the gate failing because the FILE HEAD is generic front-matter, not because the model
cannot judge? Laya sees ~700 chars of state; a knowledge file starts with YAML front-matter and a
title, which are nearly identical across files. Replace the head with the BM25-BEST PASSAGE: the
300-char window of the file that best matches the request. If the gate still fails on the most
favourable evidence we can hand it, the failure is the model, not the excerpt."""
import os, sys, json, statistics, re
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

q={"a":{"type":"choice",
   "instructions":"A knowledge file was retrieved for a request. Most retrieved files are WRONG. Judge strictly: does `file` specifically address `request`?",
   "criteria":{"yes":"the file's subject matter is the same as what the request is about",
               "no":"the file is about a different tool, machine, project or topic"}}}
for label, mk in (("head-1400", lambda it: gate.file_head(it["cand"]["paths"])),
                  ("best-passage", lambda it: best_passage(it["cand"]["paths"], it["q"]))):
    rows=[]
    for it in items:
        st={"request": it["q"], "file": f"{it['cand']['title']}\n{mk(it)}"}
        o=router.predict(st,q,model="english")["answers"]["a"]
        rows.append({"kind":it["kind"],"truth":it["truth"],"p":o["probabilities"].get("yes",0.0),"choice":o["choice"]})
    pos=[r for r in rows if r["kind"]=="positive"]; neg=[r for r in rows if r["kind"]=="negative"]
    acc=lambda rs: sum((r["choice"]=="yes")==r["truth"] for r in rs)/len(rs)
    tp=sorted(r["p"] for r in rows if r["truth"]); fp=sorted(r["p"] for r in rows if not r["truth"])
    best=max(((sum(p>=th for p in tp)/len(tp)+sum(p<th for p in fp)/len(fp))/2, th) for th in [i/100 for i in range(1,100)])
    print(label, json.dumps({"recall":round(acc(pos),3),"specificity":round(acc(neg),3),
        "balanced_acc":round((acc(pos)+acc(neg))/2,3),"p_true_med":round(statistics.median(tp),4),
        "p_false_med":round(statistics.median(fp),4),"best_threshold_bal_acc":round(best[0],3),"at":best[1]}), flush=True)
