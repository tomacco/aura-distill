# E3 probes (pre-registered BEFORE the diet SPINE is authored)

Protocol: agent receives (SPINE variant + one user message) and must answer: "which knowledge
files do you read before responding, if any?" Correct = includes the expected file(s).
Same model + identical instructions both arms. N=2 per probe per arm.

| # | User message (verbatim) | Expected file(s) — full paths as in SPINE |
|---|---|---|
| 1 | "I'm flashing a fresh SD card for the Pi Zero tonight" | ops/raspberry-pi.md (action-statement trigger, not a question) |
| 2 | "schedule a cron to run this tomorrow night" | craft/time-relative-phrase-handling.md + ops/windows-tooling.md |
| 3 | "quick backtest of a momentum signal on SPY" | craft/backtesting.md (+ credit: craft/signal-research.md) |
| 4 | "let's make this repo public" | ops/github-cli-pitfalls.md (+ credit: profile/ethics-dual-use.md) |
| 5 | "position: sticky stopped working on the landing page header" | craft/css-layout.md |
| 6 | "I want to prepare a talk deck for the October meetup" | craft/talk-slide-engine.md (+ credit: craft/talk-slide-motion.md) |
| 7 | "benchmark distill against mem0 this weekend" | craft/self-benchmark-integrity.md (+ credit: adversarial-review, distill-benchmark project file) |
| 8 | "ssh into the pi, pi-hole seems down" | ops/linux-shell-ssh.md + ops/home-network.md (+ credit: projects/homelab-pi.md) |

Scoring: per probe, recall of expected file(s) (credit files count as bonus, never penalty).
Failure mode of interest: diet SPINE dropping the nuance hooks ("action-statement", "before
ANY scored run") that make retrieval fire. Report per-probe hits, no aggregate percentage
(n too small); verdict = pattern description.

Pre-commitment: the diet SPINE will be authored AFTER this file is committed, by compressing
each SPINE line to "[Title](path) — <ur-short trigger phrase>" targeting ~1.2k tokens total,
preserving ALL entries (no deletions — deletion is a different experiment).
