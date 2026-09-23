#!/usr/bin/env python3
"""E4a — what a transcript actually costs to distill, and what a pre-filter could ever save.

Measures, per real session transcript on this machine:
  chars by role/kind — user text, assistant text, assistant thinking, tool_use inputs, tool_results
so we can bound the pre-filter idea BEFORE building it. A filter that drops user turns can only ever
save the user-turn share; if tool results dominate the transcript, that is where the tokens are and
a turn-level signal classifier is aimed at the wrong thing.

Estimates use 2.281 chars/token, calibrated from measured cache_creation on this same content
(tools/tokens.py). Marked as estimates everywhere.
"""
import glob, json, os
from collections import Counter

# The session that RUNS this measurement is also in ~/.claude/projects and grows while it runs,
# so including it makes the result unstable and circular: a research session is unusually
# tool-heavy, which is exactly the quantity being measured. Set AURA_EXCLUDE_SESSION to its id
# prefix (default: the 2026-09-22 routing session) to leave it out, and say so in any write-up.
EXCLUDE = os.environ.get("AURA_EXCLUDE_SESSION", "4536eac2")

CPT = 3.5   # tokenizer-measured band midpoint-high; see tools/tokens.py. Estimates only.


def main():
    tot = Counter(); per = []
    for f in sorted(glob.glob(os.path.expanduser("~/.claude/projects/*/*.jsonl"))):
        if "jev-cells" in f or (EXCLUDE and EXCLUDE in f):
            continue
        c = Counter(); turns = Counter()
        for line in open(f):
            try: d = json.loads(line)
            except Exception: continue
            m = d.get("message") or {}
            content = m.get("content")
            if isinstance(content, str):
                c["user_text" if d.get("type") == "user" else "assistant_text"] += len(content)
                turns["user" if d.get("type") == "user" else "assistant"] += 1
                continue
            # NOTE: main() and scan() must walk identical branches or their totals disagree.
            for b in (content or []):
                if not isinstance(b, dict): continue
                t = b.get("type")
                if t == "text":
                    key = "user_text" if d.get("type") == "user" else "assistant_text"
                    c[key] += len(b.get("text", "")); turns[key] += 1
                elif t == "thinking":
                    c["assistant_thinking"] += len(b.get("thinking", ""))
                elif t == "tool_use":
                    c["tool_use_input"] += len(json.dumps(b.get("input", ""))); turns["tool_use"] += 1
                elif t == "tool_result":
                    x = b.get("content")
                    c["tool_result"] += len(x if isinstance(x, str) else json.dumps(x))
        if sum(c.values()) == 0: continue
        per.append((os.path.basename(f)[:8], dict(c), dict(turns)))
        tot.update(c)

    grand = sum(tot.values())
    print(f"{len(per)} sessions, {grand:,} chars ≈ {grand/CPT:,.0f} tokens (est)\n")
    print(f"{'component':20s} {'chars':>10} {'share':>7} {'tokens(est)':>12}")
    for k, v in tot.most_common():
        print(f"{k:20s} {v:10,} {100*v/grand:6.1f}% {v/CPT:12,.0f}")
    u = tot["user_text"]
    print(f"\nCEILING for a user-turn pre-filter: {100*u/grand:.1f}% of transcript volume.")
    print(f"Even a PERFECT filter that dropped every uninformative user turn could not save more than that.")

def scan(cap):
    """Total transcript chars when every tool_use input and tool_result is truncated to `cap`
    chars (None = uncapped). Head-truncation, because a tool result's first lines carry the
    outcome and the tail is usually payload."""
    tot = 0
    lim = 10**9 if cap is None else cap
    for f in sorted(glob.glob(os.path.expanduser("~/.claude/projects/*/*.jsonl"))):
        if "jev-cells" in f or (EXCLUDE and EXCLUDE in f): continue
        for line in open(f):
            try: d = json.loads(line)
            except Exception: continue
            m = d.get("message") or {}; c = m.get("content")
            if isinstance(c, str):
                tot += len(c); continue
            for b in (c or []):
                if not isinstance(b, dict): continue
                t = b.get("type")
                if t == "text": tot += len(b.get("text", ""))
                elif t == "thinking": tot += len(b.get("thinking", ""))
                elif t == "tool_use": tot += min(len(json.dumps(b.get("input", ""))), lim)
                elif t == "tool_result":
                    x = b.get("content")
                    tot += min(len(x if isinstance(x, str) else json.dumps(x)), lim)
    return tot


def cap_curve():
    base = scan(None)
    print(f"\n{'tool cap (chars)':>16} {'chars':>10} {'tokens(est)':>12} {'reduction':>10}")
    for cap in (None, 4000, 2000, 1000, 500, 200, 0):
        v = scan(cap)
        label = "uncapped" if cap is None else str(cap)
        print(f"{label:>16} {v:10,} {v/CPT:12,.0f} {100*(1-v/base):9.1f}%")


if __name__ == "__main__":
    main()
    cap_curve()
