#!/usr/bin/env bash
# Offline smoke test for the experiment harness. No API, no model, no network.
# Catches the class of bug where the tools' path resolution drifts from the committed layout.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# 1. report.py must run against the committed artifacts, from any cwd.
cd /
OUT="$(python3 "$ROOT/tools/report.py")" || fail "report.py did not run"
grep -q "qwen38-27b-8bit-think" <<<"$OUT" || fail "report.py produced no local-model row"
grep -q "100%" <<<"$OUT" || fail "report.py did not normalise against the ceiling"

# 2. Every published number in results.json must recompute from the judge artifacts.
python3 - "$ROOT" <<'PY' || fail "published numbers do not recompute"
import json, os, sys
root = sys.argv[1]
res = {r["label"]: r for r in json.load(open(os.path.join(root, "results.json")))["rows"]}
for label, r in res.items():
    p = os.path.join(root, "judge", f"{label}.score.json")
    if not os.path.exists(p):
        continue
    d = json.load(open(p))
    st = [c["status"] for c in d["detail"]["candidate_claims"]]
    rc = [x["status"] for x in d["detail"]["recall"]]
    n = len(rc)
    assert abs(r["recall"] - round((rc.count("PRESENT") + 0.5 * rc.count("PARTIAL")) / n, 3)) < 1e-9, label
    assert abs(r["grounding"] - round(st.count("GROUNDED") / len(st), 3)) < 1e-9, label
    assert abs(r["fabrication"] - round(st.count("FABRICATED") / len(st), 3)) < 1e-9, label
PY

# 3. render_transcript.py must be deterministic and keep user turns that begin with "<".
cd "$TMP"
python3 - <<'PY'
import json
msg = lambda t, txt: json.dumps({"type": t, "message": {"content": [{"type": "text", "text": txt}]}})
open("f.jsonl", "w").write("\n".join([
    msg("user", "<diff> a real pasted block"),
    msg("user", "<system-reminder>harness noise</system-reminder>"),
    msg("assistant", "reply"),
    json.dumps({"type": "user", "isSidechain": True,
                "message": {"content": [{"type": "text", "text": "subagent chatter"}]}}),
]) + "\n")
PY
A="$(python3 "$ROOT/tools/render_transcript.py" f.jsonl 2>/dev/null)"
B="$(python3 "$ROOT/tools/render_transcript.py" f.jsonl 2>/dev/null)"
[ "$A" = "$B" ] || fail "render_transcript.py is not deterministic"
grep -q "a real pasted block" <<<"$A" || fail "dropped a genuine user turn starting with '<'"
grep -q "harness noise" <<<"$A" && fail "kept a system-reminder block"
grep -q "subagent chatter" <<<"$A" && fail "kept sub-agent sidechain traffic"
grep -q "^\[U1\]" <<<"$A" || fail "user turns are not numbered per role"

echo "PASS: harness smoke tests (3 groups)"
