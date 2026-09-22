"""E6b — is the yes-bias a property of the model or of my prompt? Four formulations, one load."""
import os, sys, json, statistics, time
sys.path.insert(0,'tools')
os.environ.setdefault("USE_TF","0")
import gate, route_local as R
from laya import Router
ents=R.entries_with_sections(); items=gate.build_items(ents)
router=Router(preload=True, device="mps")

FORMS={
 "A-original": ("Does the knowledge file shown in `file` contain the information needed to handle `request`?",
   {"yes":"the file covers the task, tool, project or machine the request is about","no":"the file is about something else"}),
 "B-negative-first": ("Is the knowledge file in `file` IRRELEVANT to `request`?",
   {"yes":"the file is about a different topic and would not help","no":"the file genuinely covers the request"}),
 "C-strict": ("A knowledge file was retrieved for a request. Most retrieved files are WRONG. Judge strictly: does `file` specifically address `request`?",
   {"yes":"the file's subject matter is the same as what the request is about","no":"the file is about a different tool, machine, project or topic"}),
 "D-score": None,  # score-type question instead of choice
}
def state(it): return {"request": it["q"], "file": f"{it['cand']['title']}\n{gate.file_head(it['cand']['paths'])}"}
res={}
for name,f in FORMS.items():
    rows=[]
    for it in items:
        if name=="D-score":
            q={"a":{"type":"score","instructions":"How well does the knowledge file in `file` match what `request` is about?",
                    "criteria":["unrelated","loosely related","related","exactly this topic"]}}
            o=router.predict(state(it),q,model="english")["answers"]["a"]
            p=o["score"]; ch = "yes" if p>=0.5 else "no"
        else:
            q={"a":{"type":"choice","instructions":f[0],"criteria":f[1]}}
            o=router.predict(state(it),q,model="english")["answers"]["a"]
            p=o["probabilities"].get("yes",0.0)
            ch=o["choice"]
            if name=="B-negative-first": ch = "no" if ch=="yes" else "yes"; p = 1-p
        rows.append({"kind":it["kind"],"truth":it["truth"],"p":p,"choice":ch})
    pos=[r for r in rows if r["kind"]=="positive"]; neg=[r for r in rows if r["kind"]=="negative"]
    acc=lambda rs: sum((r["choice"]=="yes")==r["truth"] for r in rs)/len(rs)
    tp=sorted(r["p"] for r in rows if r["truth"]); fp=sorted(r["p"] for r in rows if not r["truth"])
    best=max(((sum(p>=th for p in tp)/len(tp)+sum(p<th for p in fp)/len(fp))/2, th) for th in [i/100 for i in range(1,100)])
    res[name]={"recall":round(acc(pos),3),"specificity":round(acc(neg),3),
               "balanced_acc":round((acc(pos)+acc(neg))/2,3),
               "p_true_med":round(statistics.median(tp),4),"p_false_med":round(statistics.median(fp),4),
               "best_threshold_bal_acc":round(best[0],3),"at":best[1]}
    print(name, json.dumps(res[name]), flush=True)
json.dump(res, open("/private/tmp/claude-501/-Users-ivan--claude-home/4536eac2-6657-4cec-816b-029c4bae846a/scratchpad/e6b.json","w"), indent=2)
