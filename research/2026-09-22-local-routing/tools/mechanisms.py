#!/usr/bin/env python3
"""E2a — expected cost of each candidate RETRIEVAL MECHANISM, using measured constants.

Constants are measured, not assumed:
  SPINE_T   21247  tokens for the SPINE read            (tools/tokens.py, n=4 cells, spread 16)
  CPT        3.5   chars/token, tokenizer-measured (tools/tokens.py); NOT derived from SPINE_T,
             which is the cost of the whole read TURN and would inflate it to 2.28
  CHOOSE_S   2.7   s for the routing decision           (baseline run 2026-09-21, median of 4)
Recall comes from the winning zero-model router (rrf-full+bodyfull) on topics-eval.json.

Mechanisms
  status-quo      agent reads SPINE, chooses, reads the file
  shortlist-N     hook injects the top-N SPINE BULLETS; agent chooses; full SPINE on a miss
  inject-files-N  hook injects the top-N FILE BODIES; no SPINE, no routing turn; full SPINE on a miss
A "miss" = ground-truth file not in the top N. Its price is the shortlist AND the status quo after it.
"""
import json, statistics, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import run as H, route_local as R, variants as V

SPINE_T, CPT, CHOOSE_S = 21247, 3.5, 2.7   # CPT tokenizer-measured (see tools/tokens.py), not derived from SPINE_T
H.RUBRIC_CHARS = 100000
D = Path.home()/".claude"/"distill"


def main():
    ents = R.entries_with_sections()
    router = V.RRF(V.build("bm25-full", ents), V.build("bm25-bodyfull", ents))
    bykey = {e["key"]: e for e in ents}
    file_t = {e["key"]: sum(len((D/p).read_text()) for p in e["paths"] if (D/p).exists())/CPT for e in ents}
    bullet_t = {e["key"]: len(e["rubric"])/CPT for e in ents}
    med_file = statistics.median(file_t.values())

    ranked = []
    for t in R.EVAL:
        r = router.rank(t["query"]); ok = set(t["expected"])
        rk = next((i+1 for i, (k, _) in enumerate(r) if ok & set(bykey[k]["paths"])), None)
        ranked.append({"id": t["id"], "rank": rk, "top": [k for k, _ in r[:10]]})

    print(f"constants: SPINE={SPINE_T} tok, median knowledge file={med_file:.0f} tok, choose={CHOOSE_S}s")
    print(f"\n{'mechanism':18s} {'recall':>7} {'E[tokens]':>10} {'saving':>7} {'turns saved':>12}")
    base = SPINE_T + med_file
    print(f"{'status-quo':18s} {'1.00':>7} {base:10.0f} {'—':>7} {'—':>12}")
    for N in (1, 3, 5, 8):
        rec = sum(1 for r in ranked if r["rank"] and r["rank"] <= N)/len(ranked)
        # shortlist: N bullets (use the actual bullets each query surfaced, averaged)
        sl = statistics.mean(sum(bullet_t[k] for k in r["top"][:N]) for r in ranked) + 40
        e = sl + med_file + (1-rec)*base
        print(f"{'shortlist-'+str(N):18s} {rec:7.2f} {e:10.0f} {100*(1-e/base):6.1f}% {'0 (still chooses)':>12}")
    for N in (1, 2, 3):
        rec = sum(1 for r in ranked if r["rank"] and r["rank"] <= N)/len(ranked)
        inj = statistics.mean(sum(file_t[k] for k in r["top"][:N]) for r in ranked) + 40
        e = inj + (1-rec)*base
        print(f"{'inject-files-'+str(N):18s} {rec:7.2f} {e:10.0f} {100*(1-e/base):6.1f}% {'1 + '+str(CHOOSE_S)+'s':>12}")
    print("\nper-file token sizes: median %.0f  p90 %.0f  max %.0f" % (
        med_file, sorted(file_t.values())[int(.9*len(file_t))], max(file_t.values())))

if __name__ == "__main__": main()
