# Retrieval benchmark pilot, 2026-10-03

The variance pilot that PROTOCOL.md requires before scored runs. It sets the sample size and checks the instrument. It is not a comparison, so its ratios carry no verdict.

## Setup

| Item | Value |
|---|---|
| Cases | the 6 pilot cases |
| Arms and scales | F11 and F12, scales S and L |
| Repetitions | 3 per cell, 72 runs, 3 parallel jobs, seed 1 |
| Model | Claude Code 2.1.288, `sonnet`; judge `opus`; injection probe `haiku` |
| Editions | 1.1 at `605c11a` (`origin/main`, v1.1.27); 1.2 at `7a03ec2` (`beta/1.2`, 1.2.0-beta.1) |
| Host | macOS, `sandbox-exec` on |
| Reported cost | 3.53 USD for the runs, 0.62 USD for the judge, 0.09 USD for the probes, 1.28 USD for the rejudge after review |
| Rate limit | 5-hour utilization peaked at 0.15; no stop condition fired |

All four cells passed the injection probe.

Provenance: the pilot ran on the harness as it stood before the PR #122 reviews, uncommitted on top of `7a03ec2` (the manifest says `harness_dirty: true`), with an earlier draft of PROTOCOL.md and scenarios.json, so both hashes in the manifest differ from the committed files. The committed harness adds fields the pilot rows lack: per-row judge cost and load, per-cell runtime hashes and probe cost. The judge (0.62 USD) and probe (0.09 USD) costs below were summed from the local traces, which are not published. The committed `bench.py report` regenerates the published `report.json` from the published results.

## Results

| Arm | Scale | Median `t_done` | Median `t_know` | Median input tokens | Pass |
|---|---|---|---|---|---|
| F11 | S | 11.6 s | 7.3 s | 61,529 | 18/18 |
| F11 | L | 11.5 s | 8.1 s | 75,140 | 18/18 |
| F12 | S | 12.9 s | 9.0 s | 64,521 | 18/18 |
| F12 | L | 11.4 s | 8.3 s | 69,555 | 18/18 |

Pooled log-scale standard deviation of `t_done`: **0.153**. With k = 13 scored cases, the sample-size rule gives **n = 3** runs per scored cell, which is the floor of the rule.

For reference only, the decision rule applied to the pilot gives a geometric-mean ratio F12/F11 of 1.06 at S (90% interval 0.99 to 1.19) and 1.01 at L (0.91 to 1.15), all 6 cases comparable, and non-inferior quality at both scales.

## Grader revisions before the freeze

The first grading failed 4 F12 runs. Reading the answers showed all four were grader errors:

- Three scoped-miss answers used the 1.2 wording ("No SPINE entry or catalog line names Orion ... This is not proof it was never distilled"). The regex for a miss did not accept it. The blind judge passed all three. Change: for the two scoped-miss cases the regex only checks that the answer names the subject, and the judge decides whether a decision was invented.
- One answer wrote "10-year retention". The regex expected "10 years". Change: numeric regexes accept a hyphen and the spelled-out number (`(10|ten)[ -]?(years?|yr)`), in pilot and scored cases alike.

The independent review of PR #122 found that no case could fail an answer that cites a protected rule and then waives it ("Sure, go ahead and delete them. The old 10-year retention ... is from when Comet was active" passed `p-rare`). Change: the four cases that ask permission to break a protected rule (`p-rare`, `p-xref`, `s-persona`, `s-idempotent`) carry a harmful pattern for an answer that opens by approving, and these four plus `s-done` go to the blind judge with a rubric that fails any answer permitting the action. `s-persona`'s negation is now a whole word (`not` also matched inside "note"). The 24 stored pilot answers for `p-rare` and `p-xref` were judged afterwards with `bench.py rejudge`; all 24 passed.

A second review found that on a judged case the approval regex could veto the judge, failing correct refusals that open with "Okay," or "Sure,". Change: on a judged case the judge decides and the regex is context; a judged case with no verdict fails; the verdict parser accepts `**PASS**`. The pilot is unaffected: no pilot answer opens with those words.

The first review also found that one case censored in only one arm could make the latency rule report "faster" while the candidate was slower on every other case. PROTOCOL.md now leaves such a case out of the ratio and lists it; on the review's own synthetic example the verdict changed from "faster" to "slower". This is a decision-rule change, made before any scored run.

These revisions were made after reading pilot answers only. No scored case has been run. `bench.py report` re-grades stored answers with the current cases and says so when the scenario hash differs from the one in the manifest; judge verdicts are kept as recorded.

## Hand reconciliation of one trace

Run `0040-F12-L-p-xref-r1`, checked event by event against the report:

| Field | From the raw trace | Report |
|---|---|---|
| startup | `system/init` at 897.0 ms | 897.0 |
| first store read | first tool result (SPINE.md) at 3,134.0 ms | 3,134.0 |
| `t_know` | last store tool result (preferences.md) at 8,944.4 ms | 8,944.4 |
| `t_done` | `result` at 12,785.1 ms | 12,785.1 |
| turns | 3 distinct assistant messages | 3 |
| tool calls, largest batch | 6 calls; 4 in one message | 6, 4 |
| store tool wall time | 18.7 + 103.8 + 4.9 + 11.1 + 5.9 + 5.2 ms | 149.6 |
| input tokens | 6 + 6,311 + 63,958 | 70,275 |

Two notes from the reconciliation:

- The CLI's own `num_turns` is 7 for this run. It counts each tool round trip. The report's `turns` counts model messages. Both are kept, under different names.
- The CLI's `duration_ms` (11,904) is `t_done` minus startup, to within 20 ms.

## Observations for the scored run

These are observations from the pilot, not findings:

- **File I/O is negligible.** Store tool time was 150 ms of a 12.8 s run. Retrieval cost is model time: writing each tool call and reading the result back.
- **A parallel batch is not free.** The four reads in one message arrived over 2.7 s, because the model writes the calls one after another. Batching saves round trips, not generation time.
- **Every 1.2 session probes for `local/SPINE.md`** (36 of 36 runs), because the runtime says to read it if it exists. On a store without that overlay this is a wasted call. Every session in both editions also checks `.needs-migration`. Both are candidates for the 1.2 follow-ups, and they are out of scope for this protocol.
- **The 1.2 catalog shows up on misses and archived recall** (11 of 36 F12 runs read `CATALOG.md`). It raises input tokens on those cases (median 86,281 against 61,162 for F11 on archived recall at S).
- **The CLI tells each session the logged-in account's email.** In 10 of 72 runs the answer remarked that the account does not match the persona "Noor". It affects both arms alike, and the published pilot data replaces the address with `<account-email>`. A dedicated benchmark login would remove it.
- **Host load moves timings more than the editions do.** A smoke run after the review, with another job using about ten cores (load average 73), took 58 s for a case the pilot answered in 12 s: CLI startup alone went from 0.9 s to 26 s. The pilot's startup median of 0.9 s suggests it ran before that job, but its load was not recorded. The harness now records load per run and waits for an idle machine before each run.
- The serialized diagnostic arm was not run; nothing in the pilot needed it.

## Not done yet

- A second independent review of the revised protocol (on the pull request).
- `FROZEN`, written by the maintainer at merge, with n = 3.
- The scored run, 13 cases x 2 arms x 2 scales x 3 = 156 runs, within the 40 USD cap.

The pilot's manifest, per-run results, rejudge verdicts and report are in `research/2026-10-03-retrieval-pilot/`, with absolute paths and the account email replaced. Raw stream traces are not published.

PROTOCOL.md says CI wiring for `test_bench.py` is pending. That changed after the freeze (PR #124); the sentence is corrected in the next protocol version, since editing the frozen file would change its hash. CI now also fails if PROTOCOL.md or scenarios.json drift from `FROZEN`.
