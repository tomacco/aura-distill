#!/usr/bin/env python3
"""Token accounting for the SPINE read.

WHAT IS MEASURED: `cache_creation_input_tokens` on the turn whose input carries the SPINE
tool_result, from real baseline transcripts. That number is the cost of the TURN — the tool_use
block, the tool result, the surrounding assistant content — not of `SPINE.md` alone. It is the
right number for "what does the shortlist mechanism remove" (E5 confirms it removes ~all of it)
and the WRONG number to divide by file chars to get a density.

An earlier version of this file did exactly that and reported 2.281 chars/token as a property of
the content. Two independent BPE tokenizers put SPINE.md at ~3.5 chars/token (gpt2 14,017 tokens,
ModernBERT 13,854), and a prose control at 3.87 — so the index is denser than prose, but nowhere
near 2.28. The gap between ~14k and the measured 21.2k is turn overhead plus the fact that
Anthropic's tokenizer runs 1x-1.35x denser than these proxies.

CHARS_PER_TOKEN below is therefore an ESTIMATE with a stated band, not a measurement, and every
figure derived from it is labelled as an estimate.
"""
import json, glob, sys
from pathlib import Path
HOME = Path.home(); D = HOME/".claude"/"distill"

def spine_read_cost():
    """cache_creation on the MESSAGE after the one that read SPINE.md.

    A transcript writes one line per content block, all sharing the message id and usage —
    so dedupe by message id before looking at 'the next turn', or you read the SAME turn back.
    """
    out=[]
    for f in glob.glob(str(Path(__file__).parent.parent/"runs/*baseline*/cell-*/transcript.jsonl")):
        msgs={}  # id -> (order, usage, read_spine)
        for i,l in enumerate(open(f)):
            t=json.loads(l)
            if t.get("type")!="assistant": continue
            m=t["message"]; mid=m.get("id")
            reads = any(c.get("type")=="tool_use" and c.get("name")=="Read" and "SPINE.md" in str(c.get("input"))
                        for c in m.get("content",[]))
            o,u,r = msgs.get(mid,(i,m.get("usage",{}),False))
            msgs[mid]=(o,u,r or reads)
        seq=[v for _,v in sorted(msgs.items(), key=lambda kv: kv[1][0])]
        for a,b in zip(seq,seq[1:]):
            if a[2]: out.append(b[1].get("cache_creation_input_tokens"))
    return [x for x in out if x]

def main():
    costs = spine_read_cost()
    chars = len(D.joinpath("SPINE.md").read_text())
    lines = [l for l in D.joinpath("SPINE.md").read_text().splitlines() if l.startswith("- [")]
    med = sorted(costs)[len(costs)//2] if costs else None
    # Do NOT derive density from the turn cost. Use a tokenizer-measured band.
    CPT_LOW, CPT_HIGH = 2.6, 3.5     # Anthropic tokenizer 1.35x denser .. plain BPE
    ratio = 3.5
    kb = sorted((p, len(p.read_text())) for p in D.rglob("*.md") if "archive" not in str(p))
    med_file_chars = sorted(c for _,c in kb)[len(kb)//2]
    band = lambda c: [round(c/CPT_HIGH), round(c/CPT_LOW)]
    print(json.dumps({
        "spine_chars": chars, "spine_bullets": len(lines),
        "spine_READ_TURN_tokens_measured": costs,
        "spine_READ_TURN_tokens_median": med,
        "_note": "the line above is the TURN, not the file",
        "spine_file_tokens_est_band": band(chars),
        "chars_per_token_band": [CPT_LOW, CPT_HIGH],
        "kb_files": len(kb), "kb_chars": sum(c for _,c in kb),
        "kb_tokens_est_band": band(sum(c for _,c in kb)),
        "domain_file_chars_median": med_file_chars,
        "domain_file_tokens_est_band_median": band(med_file_chars),
    }, indent=2))

if __name__=="__main__": main()
