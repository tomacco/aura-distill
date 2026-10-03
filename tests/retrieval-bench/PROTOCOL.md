# Retrieval benchmark protocol

Part of #77 (protocol) and #62 (harness and baseline). Parent: #74.

This protocol decides how we compare retrieval across the three editions: current files (1.1), redesigned files (1.2) and, later, the memory service. The comparison has to show how much faster retrieval gets and whether it loses relevant knowledge. Every threshold here is fixed before any scored run. A result that misses a threshold is reported as it is, and the threshold is not moved.

Status: **proposed**. Pilot results and grader revisions: `PILOT.md`. The protocol is frozen when the maintainer merges it and commits `FROZEN` (see Freeze). Until then only pilot cases may run.

## Questions

1. Does the 1.2 files edition reach correct answers faster than 1.1 on the same knowledge?
2. Is 1.2 non-inferior on quality: required facts present, no harmful extras, no protected rule missed?
3. Do the answers hold at a store size close to real use (about 70 files and a 20 KB SPINE for 1.1)?

The service edition is out of scope for scored runs until #84 and #87 exist. Its cells are recorded as null.

## Arms

| Arm | Edition | Store | Surface | Role |
|---|---|---|---|---|
| F11 | 1.1 runtime from `origin/main` | `store-before` | Claude (`CLAUDE.md`) | incumbent, primary |
| F12 | 1.2 runtime from the protocol commit | `store-after` | Claude (`CLAUDE.md`) | candidate, primary |
| F11-codex, F12-codex | same | same | Codex managed block as appended system prompt, on the Claude CLI | secondary stratum; Codex wording, not a Codex measurement |
| F11-serial | 1.1 | `store-before` | Claude, plus "at most one tool call per assistant turn" | diagnostic only, never scored |
| SVC | service (#84, #87) | same corpus | CLI or MCP | null until implemented |

The primary comparison is F12 against F11 on the Claude surface. It changes selection and compaction (thin SPINE, catalog, archive layout). It does not change transport: both arms read local files with the same tools. A transport-only comparison needs the service arm and is not claimed here.

F11-serial exists to explain the historical 2026-08-18 numbers in #62, which serialized reads on purpose. Those numbers stay as diagnostic observations. No speed multiplier is derived from them.

The local path is the only path measured. A remote path (MCP over the network) is a separate stratum and is unsupported until the service exists.

## Corpus

Stores are synthetic. The base is the persona "Noor" in `tests/files-only/store-before` (1.1 shape) and `store-after` (the same knowledge after the 1.2 migration). `gen_corpus.py` adds filler cards about fictional services, from a seed, so the same inputs give the same bytes. It refuses filler that names any fact a case asks about.

| Scale | Filler files | 1.1 store (knowledge files) | 1.2 store (knowledge files) |
|---|---|---|---|
| S | 0 | 11, SPINE 2.6 KB | 15, SPINE 1.5 KB |
| M | 25 | 36, SPINE 10.8 KB | 40, SPINE 4.1 KB |
| L | 55 | 66, SPINE 20.5 KB, 76 lines | 70, SPINE 7.2 KB |

Scored runs use S and L. M is available for exploration and is not scored.

Scale L matches the SPINE of a real long-lived 1.1 store (about 20 KB at the 80-line cap). Total store bytes at L (about 125 KB) are lower than a real store; that limit is stated in every report.

The 1.2 shape of filler is applied by rule (a one-line trigger and a catalog row), not by running the agent migration. A real migration might write different triggers.

No live user knowledge is copied into fixtures, code or results.

## Cases

`scenarios.json` holds every case. Each case has a question, required regexes (all must match the final answer) and harmful regexes (none may match). Cases marked `judge` also go to the judge, which decides what a regex cannot (for a scoped miss: that no decision was invented).

- **Pilot cases** (6, prefix `p-`): startup, exact entity, cross-reference, archived recall, scoped miss, rare directive. Used for development and for the variance pilot.
- **Scored cases** (13, prefix `s-`): startup, exact entity, artifact, alias, ambiguous, conflict, cross-reference fan-out, two rare directives, archived recall, status, time, scoped miss. Held out: they were written before any pilot run and the harness refuses to run them until `FROZEN` exists.

Axes in #77 that this edition cannot measure, and why:

| Axis | Status |
|---|---|
| Offline | Not applicable: both file editions are offline by construction. |
| Cold and warm caches | Recorded per run from prompt-cache usage. Not controlled, so no cold/warm comparison is claimed. |
| Remote path | Unsupported until the service exists. |
| Exact URL | No URL fact in the persona store. The exact-entity and artifact cases stand in for it. |

## Timing boundaries

Each run is one fresh headless `claude -p` session. The harness stamps every stream event on arrival with its own monotonic clock, measured from process spawn. It never subtracts clocks from two hosts. Each run is one process, so no trace correlation across processes is needed in this edition; the service edition must add a trace ID across client and engine.

| Measure | Definition |
|---|---|
| startup | spawn to the `system/init` event |
| first store read | spawn to the first tool result that touched the store |
| time to usable knowledge (`t_know`) | spawn to the last tool result that touched the store |
| store tool wall time | sum over store tool calls of result arrival minus call arrival (includes CLI overhead) |
| engine time, transport | null for file editions (no separate engine) |
| model turns | distinct assistant messages; also tool calls, the largest parallel batch, and the CLI's own `num_turns` (one per tool round trip) |
| time to completed task (`t_done`) | spawn to the `result` event |
| time to completed correct task | `t_done` if the run passed, otherwise counted as never finishing |
| usage | input, cache-creation, cache-read and output tokens, and reported cost, from the `result` event |

Retries and failures stay in the data. A run that times out or errors is a failed run.

## Quality

A run passes when the session ends in success and every required regex matches, and then either the judge says PASS (cases with a judge) or no harmful regex matches (cases without one). On a judged case the harmful regex is recorded as context only: a regex cannot tell "Okay, short answer: no" from an approval, and the judge can. A judged case with no verdict fails.

A required regex only shows that a fact is present, and the same fact can appear in an answer that waives it ("the 10-year retention is from when Comet was active, go ahead"). So every case that asks permission to break a protected rule, and the evidence-for-done case, carries a harmful pattern for an answer that opens by approving (kept as context) and goes to the judge with a rubric that fails any answer permitting the action. Rule 3 below depends on this for the rare-directive cases.

The judge runs outside the scored arms, in its own session with no store, and sees only the question, the answer and the rubric. It does not know which arm produced the answer, is told not to use tools, and runs with the file and shell tools disabled. A rubric added after runs exist is applied to the stored answers with `bench.py rejudge`; those verdicts are kept in `rejudged.jsonl` beside the original results.

Quality is measured on required facts and constraints, not on which files were read. File sets are reported as context because the 1.2 layout moves content between files.

Contested and failed runs are kept, with their raw traces.

## Equalization

Both arms use the same model, CLI version, tools, permissions, working-directory layout, store path depth and filler seed. The only differences are the runtime bytes injected (from each edition's git ref) and the store shape.

Before any runs, each arm and scale gets an injection probe: a separate session asks which file the instructions say to read first, and the answer must be that cell's `SPINE.md`. A cell that fails the probe is reported as unverified.

Host load is part of the measurement, so it is controlled. The benchmark yields to other work on the machine: before the first run and before each run, the harness waits while the 1-minute load average is above the core count, and gives up after 12 hours without running anything further. It records the load and the wait with every run, and the report shows load per arm. A run started with `--ignore-load` is not scored.

Order is randomized and interleaved from a recorded seed: each block is one repetition, scale and case, with the arms shuffled inside it. Runs execute with a fixed number of parallel jobs, the same for every arm.

## Reproducibility manifest

`manifest.json` in each output directory records: protocol and scenario hashes, harness commit and dirty flag, each edition's ref and commit, model and judge model, CLI version, host and sandbox, per cell the corpus hash, the installed store hash (corpus plus the edition's `distill-monitor.md` and `distill-process.md`), and the hash and size of the injected instructions (managed block plus rules file), injection probe result, seed, order, job count, budget, stop reason and reported cost. Raw traces are under `runs/`, judge traces under `judge/`, probes under `probes/`.

## Decision rules

Fixed now, applied by `bench.py report`. A is the incumbent (F11), B the candidate (F12). Each scale is judged on its own.

**Primary latency endpoint.** For each case, the median of time to completed correct task in each arm. A failed run counts as never finishing, so a cell where most runs fail has an infinite (censored) median. A case censored in either arm is not comparable for latency: it is left out of the ratio and listed in the report, and quality rules 2 and 3 below still judge it. The effect is the geometric mean over the comparable cases of median(B) / median(A). A 90% interval comes from 2000 bootstrap resamples of runs within each cell; a resample in which a case becomes censored leaves that case out of that resample. When fewer than half of the cases are comparable, the verdict is "not enough comparable cases".

| Result | Verdict |
|---|---|
| ratio at most 0.85 and interval upper bound below 1.0 | faster: practical gain |
| ratio above 1.10 and interval lower bound above 1.0 | slower: regression |
| anything else | no practical difference shown |

**Primary quality endpoint: non-inferiority.** B is non-inferior when all three hold:

1. B's pass rate is at least A's minus 5 percentage points.
2. No case where A passes in a majority of runs and B does not.
3. Every run of B on a rare-directive case passes (protected rules are never traded for speed).

**Secondary, reported without a verdict:** time to usable knowledge, input tokens, turns, store reads, cost, and the Codex surface stratum.

**Tail statistics.** Percentiles such as p90 are reported only for cells with at least 20 runs. Below that, the report shows median, minimum and maximum.

## Pilot and sample size

The pilot runs the 6 pilot cases, F11 and F12, scales S and L, 3 repetitions: 72 runs plus probes and judge calls. It establishes the log-scale standard deviation of `t_done` per cell. The pilot is not a comparison and its ratios carry no verdict.

Repetitions per scored cell, from the pooled pilot standard deviation `s` and `k` = 13 scored cases:

`n = clamp(3, 10, ceil(2 * (1.645 + 0.842)^2 * s^2 / (k * ln(1/0.85)^2)))`

This targets a 15% difference in the geometric mean at one-sided 5% and 80% power. It treats cases as independent replicates and uses the per-run spread, while the endpoint is a median of a few runs (less efficient than a mean at n = 3). At the pilot's spread the computed value is below 1 and the floor of 3 absorbs both approximations; above a spread of about 0.3 they would matter, and the rule would need revisiting before a scored run. The value of `n` is written into `FROZEN` and does not change after scored runs start.

## Budget and stop conditions

- Scored run cap: 13 cases x 2 arms x 2 scales x n runs, at most 520 runs (156 at the pilot's n = 3).
- Cost cap: 40 USD reported cost for the scored run (the pilot cap is 15 USD).
- Stop when the 5-hour rate-limit utilization reaches 0.8, or when more than 20% of runs end without success after the first 10.
- The cost cap counts runs, judge calls and injection probes, as the CLI reports them. A run cap that cuts the plan short is recorded as a stop reason.
- A stopped run is reported as stopped, with the cells it completed, and is never re-planned. The harness has no resume yet, so a stopped scored run is reported as incomplete; finishing it needs resume support and a protocol note before it starts.

## Trust in the instrument

Before any scored result is trusted, one raw trace is reconciled by hand against the report: event timestamps, the computed boundaries, read counts and usage. The reconciliation is recorded in `PILOT.md`.

## Review

An independent adversarial review of this protocol precedes scored runs (REVIEW-PROTOCOL.md). Its findings and the changes they caused are recorded on the pull request and summarized in `PILOT.md`.

## Freeze

Freezing takes three steps:

1. The maintainer merges the protocol.
2. A commit adds `FROZEN`, written by `bench.py freeze --n <n>`, with the protocol hash, the scenarios hash, `n`, and the date.
3. From then on the protocol, the cases and the decision rules change only in a new protocol version, and results from different versions are not pooled.

The harness enforces the freeze. `run --split scored` refuses without `FROZEN`, refuses when either hash differs from it, takes `n` from it and refuses `--reps` and `--cases`. `report` withholds the verdicts of a scored run whose hashes differ from the frozen ones, or that was started with `--ignore-load`, and warns about any run that started above the core count. Release gate #90 consumes the verdicts as they come out.

## Running

```
python3 tests/retrieval-bench/bench.py run --split pilot --arms F11,F12 --scales S,L --reps 3
python3 tests/retrieval-bench/bench.py run --split scored --arms F11,F12 --scales S,L --reps <n from FROZEN>
python3 tests/retrieval-bench/bench.py report <out-dir>
```

Needs a logged-in `claude` CLI and costs model tokens, so it does not run in CI. Isolation relies on macOS `sandbox-exec`, which denies the real stores, the profile's instruction files, commands, skills, agents and plugins. It is a deny list over an allow-by-default profile, so a session with permissions skipped can still write elsewhere on the machine; elsewhere the harness refuses to run unless `--unsandboxed` is given. The output directory is a temp directory unless `--out` is given. Output carries answers verbatim, and the CLI tells sessions the logged-in account's email, so output directories are not committed as they are: a published copy goes under `research/` with the email replaced.
