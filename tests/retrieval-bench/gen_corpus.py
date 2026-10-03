#!/usr/bin/env python3
"""Scale a synthetic store for the retrieval benchmark (#77, #62).

Copies a base fixture (tests/files-only/store-before or store-after) and adds N filler cards
about fictional services, generated from a seed, so the same (base, N, seed) always gives the
same bytes. Filler never names the facts the benchmark asks about (see FORBIDDEN).

Edition shapes, applied by rule, not by an agent migration:
  1.1  each filler card gets a long digest line in SPINE.md, as 1.1 stores accumulate them
  1.2  each filler card gets a one-line trigger in SPINE.md (<= 200 bytes) and a CATALOG.md row

Usage: gen_corpus.py <base-store> <out-dir> --edition 1.1|1.2 --files N [--seed 1]
"""
import argparse, random, shutil, sys
from pathlib import Path

NAMES = ["Kestrel", "Marlin", "Heron", "Osprey", "Puffin", "Lynx", "Otter", "Falcon", "Ibis", "Wren",
         "Badger", "Condor", "Gannet", "Jackal", "Kite", "Lemur", "Mako", "Narwhal", "Ocelot", "Pika",
         "Quail", "Raven", "Stoat", "Tapir", "Urial", "Vole", "Walrus", "Yak", "Avocet", "Bison",
         "Caracal", "Dingo", "Egret", "Ferret", "Gecko", "Hoopoe", "Impala", "Jay", "Koala", "Loris",
         "Magpie", "Newt", "Oriole", "Petrel", "Quokka", "Robin", "Swift", "Tern", "Umber", "Vireo",
         "Wombat", "Xerus", "Yellowhammer", "Zebu", "Auk", "Bittern", "Crake", "Dunlin", "Eider", "Finch"]
FORBIDDEN = ["orion", "zephyr", "atlas", "beacon", "comet", "delta", "ember", "noor", "priya", "laura",
             "webhook relay", "fallback chain", "02:00", "smoke", "soak", "deployctl", "tombstone"]
KINDS = ["projects", "craft", "ops"]
NOUNS = {
    "projects": ["ingestion pipeline", "pricing service", "label printer gateway", "route optimiser",
                 "customs document service", "fleet telemetry collector", "returns portal", "slotting engine"],
    "craft": ["code review habits", "logging conventions", "API versioning", "schema evolution",
              "feature flag hygiene", "dependency upgrades", "error budgets", "load testing"],
    "ops": ["certificate rotation", "secrets rotation", "queue capacity", "backup verification",
            "cost alerts", "log retention", "on-call handover", "DNS changes"],
}
CHOICES = ["gRPC over REST", "Postgres over MySQL", "S3 lifecycle rules", "a weekly batch window",
           "per-tenant rate limits", "structured JSON logs", "blue/green switching", "a 7-day retention",
           "idempotency keys on writes", "a shared request-id header", "a 90-day key rotation",
           "SLO-based alerting", "read replicas for reporting", "a dead-man's switch on the cron"]
ORIGINS = ["evidence", "constraint", "directive", "convention"]


def card(rnd, kind, name):
    noun = rnd.choice(NOUNS[kind])
    picks = rnd.sample(CHOICES, 3)
    day = lambda: f"2026-{rnd.randint(1, 8):02d}-{rnd.randint(1, 28):02d}"
    scope = f"{name} {noun}"
    decisions = [f"- [DECISION] {p}. origin: {rnd.choice(ORIGINS)} ({day()}; measured {rnd.randint(5, 60)}% "
                 f"{rnd.choice(['fewer errors', 'lower cost', 'faster runs', 'smaller payloads'])})." for p in picks]
    if rnd.random() < 0.3:
        decisions.append(f"- [DECISION] Breaker opens after {rnd.randint(6, 12)} failures, "
                         f"half-opens after {rnd.choice([20, 30, 45, 90])} s. origin: evidence ({day()}).")
    opens = [f"- {rnd.choice(['Decide', 'Document', 'Measure', 'Retire'])} the {rnd.choice(['old', 'manual', 'nightly', 'v1'])} "
             f"{rnd.choice(['exporter', 'dashboard', 'runbook', 'cron job', 'client'])} ({rnd.choice(['blocked on budget', 'owner unclear', 'next sprint'])})."
             for _ in range(rnd.randint(2, 4))]
    log = [f"- {day()} {rnd.choice(['confirm', 'observe', 'correct'])}: {rnd.choice(picks)} "
           f"{rnd.choice(['held up in review', 'came up in the retro', 'was questioned and kept', 'caught a regression'])}"
           for _ in range(rnd.randint(6, 14))]
    body = "\n".join([
        "---", f"domain: {kind}", f"scope: {scope}", f"last_updated: {day()}", f"last_validated: {day()}",
        "staleness_threshold: 120", "---", "", "## State", "",
        f"- {name} {noun} {rnd.choice(['in production since', 'in pilot since', 'paused since'])} {day()}.", "",
        "## Decisions", "", *decisions, "", "## Open items", "", *opens, "", "## Evidence log", "", *log, ""])
    digest = (f"{scope}; decisions: {'; '.join(picks)}; open items: "
              f"{'; '.join(o[2:].rstrip('.') for o in opens)}. Read when working on {name}.")
    trigger = f"{scope}. Read when working on {name}."
    return noun, body, digest, trigger


def add_entry(spine, section, line):
    lines = spine.split("\n")
    try:
        i = lines.index(section)
    except ValueError:
        lines += ["", section]; i = len(lines) - 1
    j = i + 1
    while j < len(lines) and lines[j].startswith("- "):
        j += 1
    lines.insert(j, line)
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("base"); ap.add_argument("out")
    ap.add_argument("--edition", choices=["1.1", "1.2"], required=True)
    ap.add_argument("--files", type=int, required=True)
    ap.add_argument("--seed", type=int, default=1)
    a = ap.parse_args()
    if a.files > len(NAMES):
        sys.exit(f"at most {len(NAMES)} filler files")
    base, out = Path(a.base), Path(a.out)
    shutil.copytree(base, out)
    rnd = random.Random(a.seed)
    names = rnd.sample(NAMES, a.files)
    spine = (out / "SPINE.md").read_text()
    catalog_rows = []
    titles = {"projects": "## Projects", "craft": "## Craft", "ops": "## Ops"}
    for k, name in enumerate(names):
        kind = KINDS[k % 3]
        noun, body, digest, trigger = card(rnd, kind, name)
        low = body.lower()
        bad = [f for f in FORBIDDEN if f in low]
        if bad:
            sys.exit(f"filler for {name} contains a forbidden term: {bad}")
        rel = f"{kind}/{name.lower()}.md"
        (out / rel).parent.mkdir(parents=True, exist_ok=True)
        (out / rel).write_text(body)
        title = f"{name} {noun}"
        if a.edition == "1.1":
            spine = add_entry(spine, titles[kind], f"- [{title}]({rel}) — {digest}")
        else:
            line = f"- [{title}]({rel}) — {trigger}"
            assert len(line.encode()) <= 200, line
            spine = add_entry(spine, titles[kind], line)
            catalog_rows.append(f"- {rel} | {title} | validated 2026-08-30")
    (out / "SPINE.md").write_text(spine)
    if catalog_rows:
        cat = (out / "CATALOG.md").read_text()
        cat = add_entry(cat, "## active", "\n".join(sorted(catalog_rows)))
        (out / "CATALOG.md").write_text(cat)


if __name__ == "__main__":
    main()
