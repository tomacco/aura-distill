#!/usr/bin/env python3
"""Zero-model SPINE router — the E1 winner (`rrf-full+bodyfull`), packaged.

Stdlib only, no model, no network. Ranks the SPINE's bullets for a request by fusing two BM25
rankings: one over the index line, one over the knowledge file itself. Reciprocal-rank fusion, not
score blending — the two documents differ by an order of magnitude in length, so their BM25 scores
are not comparable and normalising them does not make them so (measured: score fusion added 0, rank
fusion added 10 points of top-1).

Measured on 30 routing queries against a live 65-entry SPINE: top-1 0.87, top-3 0.90, hard-tier
top-1 0.80. Index build 18 ms over 97 files; query 4.85 ms; 29 MB RSS.

    python3 spine_router.py "I'm about to ssh into the pi and pkill a stuck process"
    python3 spine_router.py --n 3 --json "<request>"
    python3 spine_router.py --hook          # UserPromptSubmit hook mode, reads JSON on stdin

Hook mode prints a context block naming the top-N candidates and stays SILENT when the best BM25
score is below MIN_SCORE, so a request the index does not cover falls through to the normal
full-SPINE read instead of being routed confidently into the wrong file. Read MIN_SCORE's comment
before trusting the score for anything else: it detects OUT-OF-SCOPE requests, and it cannot detect
a wrong pick on an in-scope one.
"""
from __future__ import annotations

import json
import math
import os
import re
import sys
from pathlib import Path

def _store() -> Path:
    """Resolve the knowledge store the way install.sh does.

    `AURA_DISTILL_HOME` is this project's env var (install.sh); `~/.aura-distill` is the current
    store and `~/.claude/distill` is the LEGACY pre-migration location. An earlier version of this
    file defaulted to the legacy path under a made-up env var name, which on a stock install died
    with FileNotFoundError and on a half-migrated machine silently indexed the stale copy.
    """
    env = os.environ.get("AURA_DISTILL_HOME")
    if env:
        return Path(env).expanduser()
    current = Path.home()/".aura-distill"
    legacy = Path.home()/".claude"/"distill"
    if current.exists():
        return current
    if legacy.exists():
        print(f"warning: using legacy store {legacy}; the current location is {current}",
              file=sys.stderr)
        return legacy
    return current


DISTILL = _store()
SPINE = DISTILL/"SPINE.md"
RRF_K = 60
DEFAULT_N = 3
# Abstention threshold, on the RAW BM25 score of the best-matching entry — NOT on the fused score.
#
# PORTABILITY WARNING: this is an ABSOLUTE BM25 score, and BM25's IDF term scales with corpus size.
# It was calibrated on ONE 65-entry index. On a small index the same correct answer scores lower —
# verified on a 4-entry fixture, where a correctly-ranked top hit scored 5.2 and would be silently
# suppressed. Anything shipping this must calibrate per store (or switch to a rank/relative
# criterion); the number below is a research constant, not a portable default.
#
# Measured, and the measurement mattered: the fused RRF score does not separate right from wrong at
# all (correct top-1 median 0.03279, wrong top-1 median 0.03252, wrong max == correct max). That is
# structural, not bad luck — RRF assigns 1/(k+1) + 1/(k+1) to anything ranked first by both rankers,
# so the top of the scale is a constant. The rank-1-minus-rank-2 gap is *worse* than useless: it is
# LARGER on wrong answers than on right ones.
#
# The raw BM25 score is a weak but real signal. Calibrated against 30 in-scope queries and 10
# out-of-scope ones ("what's the weather", "write me a haiku", "hello"):
#   threshold 6.0 -> keeps 30/30 in-scope, rejects  6/10 out-of-scope
#   threshold 7.5 -> keeps 28/30 in-scope, rejects 10/10 out-of-scope   <- chosen
#   threshold 9.0 -> keeps 26/30 in-scope, rejects 10/10 out-of-scope
# 7.5 is the knee. The two in-scope queries it drops fall back to the normal full-SPINE read, which
# costs tokens but is never wrong — the asymmetry the whole mechanism is built on.
#
# What this threshold CANNOT do: tell you the router picked the wrong file when the request IS in
# scope. Nothing here can. That is the one thing a calibrated model could add over BM25, and it is
# why E3 is worth running even though BM25 already wins on accuracy.
MIN_SCORE = 7.5

LINK = re.compile(r"\[([^\]]+)\]\(([^)]+\.md)\)")
WORD = re.compile(r"[a-z0-9]+")


def tokenize(s: str) -> list[str]:
    return WORD.findall(s.lower())


class BM25:
    def __init__(self, docs: list[str], k1: float = 1.5, b: float = 0.75):
        self.k1, self.b = k1, b
        self.docs = [tokenize(d) for d in docs]
        self.n = len(self.docs) or 1
        self.avg = sum(map(len, self.docs))/self.n
        df: dict[str, int] = {}
        for d in self.docs:
            for w in set(d):
                df[w] = df.get(w, 0)+1
        self.idf = {w: math.log(1+(self.n-c+0.5)/(c+0.5)) for w, c in df.items()}
        self.tf = [{w: d.count(w) for w in set(d)} for d in self.docs]

    def scores(self, query: str) -> list[float]:
        q = tokenize(query)
        out = []
        for i, d in enumerate(self.docs):
            s = 0.0
            for w in q:
                f = self.tf[i].get(w)
                if f:
                    s += self.idf[w]*f*(self.k1+1)/(f+self.k1*(1-self.b+self.b*len(d)/self.avg))
            out.append(s)
        return out


def load_entries() -> list[dict]:
    """One entry per SPINE bullet. A multi-file bullet stays ONE entry: the SPINE author grouped
    those files deliberately, and splitting them would route to half of a grouped topic."""
    entries = []
    for line in SPINE.read_text().splitlines():
        if not line.startswith("- ["):
            continue
        links = LINK.findall(line)
        if not links:
            continue
        entries.append({
            "title": links[0][0],
            "paths": [p for _, p in links],
            "line": LINK.sub(r"\1", line[2:]).strip(),
        })
    return entries


class Router:
    def __init__(self, entries: list[dict] | None = None):
        self.entries = entries if entries is not None else load_entries()
        def words(e):
            return " ".join(e["paths"]).replace("/", " ").replace("-", " ").replace(".md", "")
        self.by_line = BM25([f"{e['title']} {e['line']} {words(e)}" for e in self.entries])
        bodies = []
        for e in self.entries:
            body = []
            for p in e["paths"]:
                f = (DISTILL/p).resolve()
                # SPINE.md is user-editable; a link like ../../.ssh/id_rsa must not be followed.
                if not f.is_relative_to(DISTILL.resolve()):
                    continue
                if f.exists():
                    body.append(f.read_text(errors="replace"))
            bodies.append(f"{e['title']} {words(e)} " + " ".join(body))
        self.by_body = BM25(bodies)

    def rank(self, request: str) -> list[tuple[int, float]]:
        """Indices into self.entries, best first, with the fused score."""
        order = []
        for bm in (self.by_line, self.by_body):
            s = bm.scores(request)
            order.append(sorted(range(len(s)), key=lambda i: -s[i]))
        fused: dict[int, float] = {}
        for ranking in order:
            for pos, idx in enumerate(ranking):
                fused[idx] = fused.get(idx, 0.0)+1.0/(RRF_K+pos+1)
        return sorted(fused.items(), key=lambda kv: -kv[1])

    def top(self, request: str, n: int = DEFAULT_N) -> list[dict]:
        """Top-n entries. `score` is the fused rank score (ordering only — see MIN_SCORE);
        `raw` is the better of the two BM25 scores, which is what abstention is judged on."""
        line, body = self.by_line.scores(request), self.by_body.scores(request)
        out = []
        for idx, score in self.rank(request)[:n]:
            out.append({**self.entries[idx], "score": round(score, 5),
                        "raw": round(max(line[idx], body[idx]), 3)})
        return out


def hook_main() -> int:
    """UserPromptSubmit hook: print a candidate block, or nothing at all.

    Silence is the safe default. If the top score is below MIN_SCORE the request is probably not
    covered by the index, and a confident wrong route costs more than the full SPINE read it saved.
    """
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0
    prompt = (payload.get("prompt") or "").strip()
    if not prompt or not SPINE.exists():
        return 0
    try:
        hits = Router().top(prompt, DEFAULT_N)
    except Exception:
        return 0                      # a hook must never break a session
    if not hits or hits[0]["raw"] < MIN_SCORE:
        return 0
    print("Knowledge candidates for this request (ranked, from the local SPINE index):")
    for h in hits:
        print(f"  - {', '.join(h['paths'])} — {h['title']}")
    print("Read the one that fits. If none of them do, read SPINE.md as usual.")
    return 0


def main() -> int:
    args = sys.argv[1:]
    if "--hook" in args:
        return hook_main()
    n = DEFAULT_N
    if "--n" in args:
        i = args.index("--n")
        if i + 1 >= len(args):
            print("--n needs a number", file=sys.stderr); return 2
        try:
            n = int(args[i+1])
        except ValueError:
            print(f"--n needs a number, got {args[i+1]!r}", file=sys.stderr); return 2
        del args[i:i+2]
    as_json = "--json" in args
    if as_json:
        args.remove("--json")
    if not args:
        print(__doc__.strip().splitlines()[0], file=sys.stderr)
        return 2
    if not SPINE.exists():
        print(f"no index at {SPINE} (set AURA_DISTILL_HOME)", file=sys.stderr)
        return 1
    hits = Router().top(" ".join(args), n)
    if as_json:
        print(json.dumps(hits, indent=2))
    else:
        for h in hits:
            print(f"{h['score']:.5f} raw={h['raw']:7.3f}  {', '.join(h['paths'])}  — {h['title']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
