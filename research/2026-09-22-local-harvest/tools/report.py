#!/usr/bin/env python3
"""Assemble exp1 results into the results table + a machine-readable results.json."""
import glob, json, os

os.chdir(os.path.dirname(os.path.abspath(__file__)))
EXP = os.environ.get("EXP", "exp1")

# List price per MTok (USD), Sept 2026 — used only to price the API-side runs.
PRICES = {"claude-opus-5": (5, 25), "claude-sonnet-5": (2, 10), "claude-haiku-4-5-20251001": (1, 5)}

rows = []
for m in sorted(glob.glob(f"{EXP}/runs/*.meta.json")):
    label = os.path.basename(m).replace(".meta.json", "")
    d = json.load(open(m))
    sc = f"{EXP}/judge/{label}.score.json"
    s = json.load(open(sc))["summary"] if os.path.exists(sc) else {}
    local = "prompt_tokens" in d
    rows.append({
        "label": label,
        "where": "local" if local else "api",
        "model": d.get("model"),
        "wall_s": d.get("wall_s"),
        "load_s": d.get("load_s"),
        "input_tokens": d.get("prompt_tokens") if local else (d.get("cache_creation") or 0) + (d.get("cache_read") or 0) + (d.get("input_tokens") or 0),
        "output_tokens": d.get("generated_tokens") if local else d.get("output_tokens"),
        "gen_tps": d.get("generation_tps"),
        "peak_memory_gb": d.get("peak_memory_gb"),
        "cost_usd": d.get("cost_usd", 0.0),
        "output_chars": d.get("output_chars"),
        "recall": s.get("recall"), "grounding": s.get("grounding"), "fabrication": s.get("fabrication"),
        "present": s.get("present"), "partial": s.get("partial"), "absent": s.get("absent"),
        "n_cand_claims": s.get("n_cand_claims"), "distorted": s.get("distorted"), "fabricated": s.get("fabricated"),
        "spec": s.get("spec"), "qualitative": s.get("qualitative"),
    })

ceiling = next((r["recall"] for r in rows if r["label"].startswith("opus-2")), None)
for r in rows:
    r["pct_of_opus"] = round(100 * r["recall"] / ceiling) if (r["recall"] and ceiling) else None

json.dump({"ceiling_recall": ceiling, "rows": rows}, open(f"{EXP}/results.json", "w"), indent=1)

hdr = ["run", "where", "wall s", "in tok", "out tok", "tok/s", "peak GB", "cost $", "recall", "% of Opus", "grounding", "fabrication"]
print("| " + " | ".join(hdr) + " |")
print("|" + "---|" * len(hdr))
for r in rows:
    print("| {label} | {where} | {wall_s} | {input_tokens} | {output_tokens} | {gen_tps} | {peak_memory_gb} | {cost} | {recall} | {pct} | {grounding} | {fabrication} |".format(
        cost=f"{r['cost_usd']:.3f}" if r["cost_usd"] else "0",
        pct=f"{r['pct_of_opus']}%" if r["pct_of_opus"] else "—", **r))
