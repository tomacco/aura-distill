#!/usr/bin/env bash
# Run the harvest prompt through a Claude model headlessly.
# usage: run_claude.sh <model-alias> <run-label>
# Writes exp1/runs/<label>.json (full claude -p JSON incl. usage) and exp1/runs/<label>.md (harvest text).
set -euo pipefail
cd "$(dirname "$0")"
MODEL="$1"; LABEL="$2"
mkdir -p exp1/runs
SYS="$(cat exp1/harvest_system_prompt.md)"
START=$(date +%s.%N)
{ printf 'Here is the session transcript to harvest:\n\n<transcript>\n'; cat exp1/transcript.txt; printf '\n</transcript>\n\nProduce the Step 1 structured summary now.\n'; } \
  | command claude -p --model "$MODEL" --tools "" --setting-sources "" --no-session-persistence \
      --system-prompt "$SYS" --output-format json --max-turns 1 \
  > "exp1/runs/$LABEL.json"
END=$(date +%s.%N)
python3 - "$LABEL" "$START" "$END" <<'EOF'
import json, sys
label, start, end = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
d = json.load(open(f"exp1/runs/{label}.json"))
open(f"exp1/runs/{label}.md", "w").write(d["result"])
u = d.get("usage", {})
meta = {"label": label, "model": d.get("modelUsage") and list(d["modelUsage"].keys())[0],
        "wall_s": round(end - start, 1), "duration_api_ms": d.get("duration_api_ms"),
        "cost_usd": d.get("total_cost_usd"),
        "input_tokens": u.get("input_tokens"), "cache_creation": u.get("cache_creation_input_tokens"),
        "cache_read": u.get("cache_read_input_tokens"), "output_tokens": u.get("output_tokens"),
        "num_turns": d.get("num_turns"), "output_chars": len(d["result"])}
json.dump(meta, open(f"exp1/runs/{label}.meta.json", "w"), indent=1)
print(json.dumps(meta))
EOF
