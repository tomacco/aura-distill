#!/usr/bin/env bash
# Run the harvest prompt through a Claude model headlessly.
# usage: run_claude.sh <model-alias> <run-label>
# Writes exp1/runs/<label>.json (full claude -p JSON incl. usage) and exp1/runs/<label>.md (harvest text).
set -euo pipefail
ROOT="${EXP:-$(cd "$(dirname "$0")/.." && pwd)}"
RUNS="$ROOT/runs"
MODEL="$1"; LABEL="$2"
mkdir -p "$RUNS"
SYS="$(cat "$RUNS/harvest_system_prompt.md")"
START=$(date +%s.%N)
{ printf 'Here is the session transcript to harvest:\n\n<transcript>\n'; cat "$RUNS/transcript.txt"; printf '\n</transcript>\n\nProduce the Step 1 structured summary now.\n'; } \
  | command claude -p --model "$MODEL" --tools "" --setting-sources "" --no-session-persistence \
      --system-prompt "$SYS" --output-format json --max-turns 1 \
  > "$RUNS/$LABEL.json"
END=$(date +%s.%N)
RUNS="$RUNS" python3 - "$LABEL" "$START" "$END" <<'EOF'
import json, os, sys
label, start, end = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
runs = os.environ["RUNS"]
d = json.load(open(f"{runs}/{label}.json"))
# An API error (refusal, overload, budget/turn cap) must never be scored as a harvest.
if d.get("is_error") or d.get("subtype") != "success" or not isinstance(d.get("result"), str):
    sys.exit(f"FATAL: {label} did not return a successful result: "
             f"is_error={d.get('is_error')} subtype={d.get('subtype')} {str(d.get('result'))[:200]}")
open(f"{runs}/{label}.md", "w").write(d["result"])
u = d.get("usage", {})
meta = {"label": label, "model": d.get("modelUsage") and list(d["modelUsage"].keys())[0],
        "wall_s": round(end - start, 1), "duration_api_ms": d.get("duration_api_ms"),
        "cost_usd": d.get("total_cost_usd"),
        "input_tokens": u.get("input_tokens"), "cache_creation": u.get("cache_creation_input_tokens"),
        "cache_read": u.get("cache_read_input_tokens"), "output_tokens": u.get("output_tokens"),
        "num_turns": d.get("num_turns"), "output_chars": len(d["result"])}
json.dump(meta, open(f"{runs}/{label}.meta.json", "w"), indent=1)
print(json.dumps(meta))
EOF
