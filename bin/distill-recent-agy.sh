#!/usr/bin/env bash
# distill-recent-agy -- aura-distill Time Index for Antigravity sessions (POSIX / Bash).
# Scans Antigravity brain transcripts (~/.gemini/antigravity-cli/brain/*/logs/transcript.jsonl)
# and buckets sessions on human mental timelines.

set -euo pipefail

BRAIN_DIR="${1:-${HOME}/.gemini/antigravity-cli/brain}"
PER_BUCKET="${2:-8}"

if [[ ! -d "$BRAIN_DIR" ]]; then
    echo "Antigravity brain directory not found at $BRAIN_DIR" >&2
    exit 2
fi

echo "=== Antigravity Session Time Index ==="
echo ""

# Scan brain sessions
find "$BRAIN_DIR" -maxdepth 4 -name "transcript.jsonl" | while read -r trans; do
    dir=$(dirname "$(dirname "$trans")")
    sid=$(basename "$dir")
    
    first_prompt=$(grep -m1 '"type":"USER_INPUT"' "$trans" 2>/dev/null | sed -E 's/.*"content":"([^"]+)".*/\1/' | sed 's/\\n/ /g' | cut -c 1-85 || echo "No prompt")
    last_assistant=$(grep '"type":"PLANNER_RESPONSE"' "$trans" 2>/dev/null | tail -n1 | sed -E 's/.*"content":"([^"]+)".*/\1/' | sed 's/\\n/ /g' | cut -c 1-90 || echo "")
    
    echo "- [${sid:0:8}] · $first_prompt"
    if [[ -n "$last_assistant" ]]; then
        echo "    left off: $last_assistant"
    fi
done
