#!/usr/bin/env python3
"""Run the harvest prompt through a local MLX model.

usage: run_local.py <hf-repo-or-path> <run-label> [--no-think] [--max-tokens N]
Writes exp1/runs/<label>.md (harvest text, thinking stripped), <label>.raw.md (untouched
output) and <label>.meta.json (timing, token counts, peak memory).
"""
import argparse, json, os, resource, sys, time

import mlx.core as mx
from mlx_lm import load, stream_generate
from mlx_lm.sample_utils import make_sampler

ap = argparse.ArgumentParser()
ap.add_argument("model")
ap.add_argument("label")
ap.add_argument("--no-think", action="store_true")
ap.add_argument("--max-tokens", type=int, default=16000)
ap.add_argument("--exp", default="exp1")
a = ap.parse_args()

os.chdir(os.path.dirname(os.path.abspath(__file__)))
system = open(f"{a.exp}/harvest_system_prompt.md").read()
transcript = open(f"{a.exp}/transcript.txt").read()
user = ("Here is the session transcript to harvest:\n\n<transcript>\n" + transcript +
        "\n</transcript>\n\nProduce the Step 1 structured summary now.\n")

t_load0 = time.time()
model, tokenizer = load(a.model)
t_load = time.time() - t_load0

msgs = [{"role": "system", "content": system}, {"role": "user", "content": user}]
kw = {}
if a.no_think:
    kw["enable_thinking"] = False
prompt = tokenizer.apply_chat_template(msgs, add_generation_prompt=True, tokenize=False, **kw)
n_prompt = len(tokenizer.encode(prompt))

sampler = make_sampler(temp=0.6, top_p=0.95, top_k=20)  # Qwen's recommended thinking settings
t0 = time.time()
first_tok = None
text = ""
n_gen = 0
last = None
for r in stream_generate(model, tokenizer, prompt, max_tokens=a.max_tokens, sampler=sampler):
    if first_tok is None:
        first_tok = time.time() - t0
    text += r.text
    n_gen += 1
    last = r
t_total = time.time() - t0

raw = text
# Strip a leading <think>…</think> block if present
out = raw
if "</think>" in out:
    out = out.split("</think>", 1)[1].strip()
    thinking_chars = len(raw) - len(out)
else:
    thinking_chars = 0

os.makedirs(f"{a.exp}/runs", exist_ok=True)
open(f"{a.exp}/runs/{a.label}.raw.md", "w").write(raw)
open(f"{a.exp}/runs/{a.label}.md", "w").write(out)
meta = {
    "label": a.label, "model": a.model, "thinking": not a.no_think,
    "load_s": round(t_load, 1), "wall_s": round(t_total, 1), "ttft_s": round(first_tok or 0, 1),
    "prompt_tokens": n_prompt, "generated_tokens": n_gen,
    "prompt_tps": round(last.prompt_tps, 1) if last else None,
    "generation_tps": round(last.generation_tps, 1) if last else None,
    "peak_memory_gb": round(mx.get_peak_memory() / 1e9, 2),
    "thinking_chars": thinking_chars, "output_chars": len(out),
    "finish_reason": last.finish_reason if last else None,
}
json.dump(meta, open(f"{a.exp}/runs/{a.label}.meta.json", "w"), indent=1)
print(json.dumps(meta))
