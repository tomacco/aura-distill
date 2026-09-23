# Experiment 1 — can a local open-weights model do the signal harvest?

**Write-up:** [docs/research/local-models.html](https://tomacco.github.io/aura-distill/research/local-models.html) — the live study page, updated as runs land. This folder is its raw measurement record.

**Date:** 2026-09-22 · **Issue:** [#96](https://github.com/tomacco/aura-distill/issues/96) · Part of [#50](https://github.com/tomacco/aura-distill/issues/50) (model routing), feeds [#51](https://github.com/tomacco/aura-distill/issues/51) / [#53](https://github.com/tomacco/aura-distill/issues/53) (auto-distillation)

## The question

`/distill` Step 1 — **signal harvest** — reads a session transcript and emits the A–E structured
summary (failures, corrections, user observations, decision origins, metadata). The routing directive
(#50) assigns it to the *cheap* tier. This experiment asks how far down that tier goes: can it run on
a **local open-weights model**, at zero API cost, and how much semantic quality is lost?

Machine under test: **Apple M5 Pro, 48 GB** unified memory. Target users have 16 GB, so this run
measures the *ceiling* of a model family on the developer's machine before the 16 GB sibling is
tested (experiment 2).

## Design

One real Claude Code transcript, rendered deterministically to text by `tools/render_transcript.py`
(user turns, assistant turns, tool calls, tool results truncated to 400/600 chars). **Every model sees
byte-identical input.** The system prompt (`runs/harvest_system_prompt.md`) is `distill.md`'s Step 1
sections A–E character-for-character, preceded by an output contract (five sections, in order,
grounded in the transcript, nothing outside them). Step 1's dispatcher preamble and section F (the
identity beacon) are dropped — they address a live main-context agent that does not exist here.
No tools, no MCP, one turn.

| | |
|---|---|
| Transcript | 43,534 bytes · 13,585 tokens (Qwen tokenizer) · 4 user turns · 5 assistant turns · 37 tool calls |
| Session content | an aura-distill routing benchmark: binary forensics, a headless A/B experiment, a mid-session pivot |
| Reference | **Opus 5** (`opus-1`) |
| Scale anchors | **Opus 5 rerun** (`opus-2` — the self-agreement ceiling), **Sonnet 5**, **Haiku 4.5** |
| Candidate | **Qwen3.8-27B, MLX 8-bit** (`lmstudio-community/Qwen3.8-27B-MLX-8bit`), `mlx-lm` 0.31.3, thinking on, temp 0.6 / top-p 0.95 / top-k 20 |

### How "X % as good as Opus" is computed

A blind judge (Opus 5, never told which system produced which output) does two passes:

1. **Recall.** The reference harvest is decomposed once into **116 atomic claims** (A 32 · B 14 ·
   C 20 · D 26 · E 24). For each, the candidate is marked PRESENT / PARTIAL / ABSENT.
   `recall = (present + 0.5 × partial) / 116`.
2. **Grounding.** The candidate is decomposed into *its own* atomic claims, each checked against the
   **transcript** (ground truth): GROUNDED / DISTORTED / FABRICATED.

Then a **calibrated adjudication pass** (`tools/adjudicate.py`) re-labels the DISTORTED/FABRICATED
boundary. This exists because the first pass scored each candidate in an *independent* call, and the
boundary drifted between them: notes reading "no such assumption appears in the transcript — invented"
were filed as DISTORTED for one candidate and FABRICATED for another. The adjudicator pools all 43
non-GROUNDED claims from every candidate into **one** blind, shuffled call with a pinned rubric and
worked examples, so a single boundary applies to all of them. It changed **10 of 43** labels. Every
number below is post-adjudication; `judge/adjudication.json` records what moved and where.

Plus a spec check: five sections in order, D-items carry an origin, no stray commentary.

**The ceiling is not 1.0.** Opus rerunning the same prompt recalls only **91.8 %** of its own first
run's claims — that is what "100 % of Opus" means here; `% of Opus = recall / 0.918`. Recall alone is
also not quality: a model can score recall by asserting things the transcript never said, which is why
grounding and fabrication sit next to it.

## Results

| run | where | wall | in tok | out tok | tok/s | peak RAM | cost | recall | **% of Opus** | grounding | fabricated |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `opus-1` (reference) | API | 71 s | 26,884 | 5,086 | — | — | $0.396 | — | — | — | — |
| `opus-2` (ceiling) | API | 81 s | 26,884 | 5,794 | — | — | $0.158 † | 0.918 | **100 %** | 0.943 | 0 |
| `sonnet-1` | API | 47 s | 20,667 | 4,381 | — | — | $0.126 | 0.681 | **74 %** | 0.863 | 1 (2.0 %) |
| `haiku-1` | API | 103 s | 20,439 | 7,062 | — | — | $0.076 | 0.534 | **58 %** | 0.552 | 6 (10.3 %) |
| **`qwen38-27b-8bit`** *(thinking on)* | **local** | **1,834 s** | 14,273 | 15,765 | 8.8 | 32.3 GB | **$0** | **0.741** | **81 %** | 0.879 | 2 (3.4 %) |
| `qwen38-27b-8bit-nothink` | local | 382 s | 14,237 | 3,007 | 8.8 | 32.3 GB | $0 | 0.659 | 72 % | 0.867 | 1 (2.2 %) |

† **Not like-for-like.** `opus-2` read `opus-1`'s prompt cache (`cache_read: 26,882`), while Sonnet and
Haiku each paid full cache-creation price. Uncached, Opus on this job costs **$0.396** — 3.1× Sonnet,
not the 25 % the column suggests. The cheap rows are the honest comparison for #50 anyway.

Per-section recall for the local model: A failures 0.61 · B corrections 0.96 · C user model 0.85 ·
D decision origins 0.65 · E metadata 0.79.

### 1. Feasibility: yes, with room to spare

27B at 8-bit loaded in **4.0 s** (warm page cache) and peaked at **32.3 GB** of 48 GB — weights ~29 GB
plus KV cache for a 14.3k-token prompt and 15.8k generated tokens. `mlx-lm` ran the Qwen3.5-arch
checkpoint text-only without extra work. Nothing swapped; a ~6 GB peer job ran alongside it untouched.
The 48 GB machine is not the constraint at this size. **16 GB is** — see "What this does not answer".

### 2. Execution time: 26× slower than the API, and that is the whole cost

**30.6 minutes** against Opus's 71 seconds. The breakdown matters:

- prompt processing 341.8 tok/s → 43 s to first token, fine;
- generation **8.8 tok/s** — a dense 27B at 8-bit is memory-bandwidth bound, ~29 GB read per token;
- it spent **42,654 characters on thinking** before writing a single line of the answer — roughly
  two-thirds of its ~15.8k generated tokens were reasoning the user never sees.

The levers for experiment 2 are therefore: **thinking budget**, a **MoE** with few active parameters
instead of a dense model, and **4-bit**. A 27B dense at 8-bit is the slowest shape in the candidate
space. Note that none of those three is a pure speed knob — each changes what the model *does* — so
experiment 2 measures them rather than projecting from this run's token counts.

This is why the stage was scoped as background batch from the start. At 30 minutes per transcript a
nightly auto-distiller (#51) over a handful of undistilled sessions is unremarkable; an interactive
`/distill` at that latency is not shippable.

### 3. Tokens saved: the entire API bill for the stage

The local run displaces **every** API token for the harvest: 20.4–26.9k input and 4.4–7.1k output per
transcript become zero. At Sept-2026 list prices that is **$0.076 per transcript against Haiku**,
$0.126 against Sonnet, $0.396 against Opus uncached — the cheap-tier figure being the honest
comparison, since #50 already forbids frontier here.

**The headless harness floor, measured directly** (not inferred by subtracting across tokenizers):
sending a two-character prompt through the same flags as the harvest run costs **8,302 tokens**
(`claude -p --model haiku --tools "" --setting-sources "" --system-prompt <the harvest prompt>`).
Of that, the harvest system prompt is ~600–800 tokens, so **~7.5k is pure harness floor** carried into
every headless call. `--tools ""` and `--tools none` measured **identical** (8,302 each), so the two
spellings are interchangeable. For comparison, `research/2026-07-09-token-saver/` measured a 5,236-token
floor for `--tools none` in July 2026 on Windows; the gap is CLI-version and platform drift, not a
contradiction, and neither number should be quoted without its flags and date.

That also decomposes the 12,611-token gap between the API input count (26,884) and the local prompt
(14,273): **~8.3k of it is harness floor and ~4.3k is tokenizer difference** on the same text (Claude's
tokenizer is markedly less efficient on tool-call JSON than Qwen's). A local model pays neither.

**The verbosity tax that #50 warns about shows up inverted.** Haiku emitted 39 % more output tokens
than Opus for a worse answer; the local model emitted 3.1× Opus's output, two-thirds of it thinking.
Cheap does not mean terse.

### 4. Semantic quality: 81 % of Opus, and better-behaved than the hosted cheap tier

Ranked by what a knowledge base actually needs — not inventing things (post-adjudication):

| | fabricated | distorted | grounding |
|---|---|---|---|
| Opus (ceiling) | 0 | 3 | 0.943 |
| **Qwen3.8-27B local** | **2 (3.4 %)** | 5 | 0.879 |
| Sonnet | 1 (2.0 %) | 6 | 0.863 |
| Haiku | **6 (10.3 %)** | 20 | 0.552 |

Haiku is the finding nobody should skip: **one claim in ten had no referent in the transcript at all**,
and the inventions were the dangerous kind — attributing knowledge and reactions to the user that never
occurred ("user knows repo conventions by heart", "user signalled acceptance via follow-up", "user
immediately accepted the pricing"). A distiller that writes those into `profile/` corrupts the
knowledge base silently, and it is exactly what `distill-process.md`'s anti-sycophancy rule forbids.
Its grounding of 0.552 — nearly half its claims wrong in some way — is the real disqualifier.

The local model is not clean either: **2 of its 58 claims were invented**, both fictitious assistant
mental states (an assumption never held, a prior hypothesis never stated). It also inverted two
user-behaviour readings, **recasting the user's knowledge gaps as demonstrated expertise** (claiming
the user knows a tool, where the transcript shows the user asking what it does). Sycophancy toward the
user model is the shared weakness of every non-frontier model tested, local included. If a local model
ships, section C needs a guard — or section C stays on a hosted mid-tier model while A/B/D/E go local.

Where it loses its 19 %: **numbers and mid-session engineering detail**. It drops specific token
counts, dollar figures, percentages and file counts, and it is weakest exactly where the reference is
densest (section A failures, 0.61; section D origins, 0.65). It is *strongest* on corrections (0.96)
and the narrative arc. Structurally it was flawless — five sections in order, every decision carrying
an origin label, no stray commentary — and the judge rated its origin-labelling discipline **better
than the reference's**.

## Experiment 2, run 1 — thinking off

Same model and weights, same input, same judge; only deliberation removed.

| | thinking on | thinking off | change |
|---|---|---|---|
| % of Opus ceiling | 81 % | 72 % | −9 pts |
| grounding | 0.879 | 0.867 | −0.012 |
| fabricated | 2 (3.4 %) | 1 (2.2 %) | −1 |
| wall clock | 1,834 s | **382 s** | **4.8× faster** |
| generated tokens | 15,765 | 3,007 | −12,758 |

**Thinking buys coverage, not honesty.** The whole cost lands on recall; grounding moves ~1 point and
fabrications go *down*. Generation stayed at 8.8 tok/s in both runs, so the speedup is fewer tokens,
not faster ones — the bandwidth bound is confirmed, not circumvented. Peak memory was unchanged at
32.3 GB, so this does nothing for 16 GB by itself; it isolates one lever before the memory-constrained
candidates move three at once.

The prediction that thinking-off was the biggest available speed lever held (4.8×). The question it
was run to settle — whether less deliberation would worsen or improve the user-model errors — came
back neutral, and is now closed.

## Experiment 2, runs 2–4 — the 16 GB candidates

| candidate | peak RAM | wall | recall | % of Opus | grounding | distorted | fabricated |
|---|---|---|---|---|---|---|---|
| Qwen3.8-9B, 4-bit | 7.1 GB | 54 s | 0.375 | 41 % | 0.594 | 13 | 0 |
| gpt-oss-20b, MXFP4-Q8 | 13.2 GB | 83 s | 0.328 | 36 % | 0.600 | 15 | 1 |
| Gemma 3 12B, 4-bit *(substitute)* | 10.0 GB | 52 s | 0.147 | 16 % | 0.645 | 11 | 0 |

**No 16 GB configuration is usable for this stage today.** A 40-point gap to the 48 GB result, and
grounding in the low 0.6s across three families. gpt-oss at 13.2 GB also exceeds the default macOS
GPU wired limit (~10.6 GB on a 16 GB machine), so it needs an `iogpu.wired_limit_mb` change users
will not make.

**The failure is misattribution, not invention.** Outright fabrication is rare (0, 1, 0 claims); the
damage is in DISTORTED — 13, 15 and 11 claims each, a real referent stated wrongly, overwhelmingly by
swapping who did what. Sections C and D exist to record who decided what and why, so scrambled agency
is the worst error this pipeline can receive.

**Gemma 4 could not be run at all.** Neither size that fits 16 GB loads on any released mlx-lm: the
12B declares `gemma4_unified` (unimplemented in 0.31.3, the newest on PyPI) and E4B fails with a
126-parameter mismatch against the `gemma4` implementation. The 26B-A4B MoE that would load is
15.6 GB. Gemma 3 12B stands in, labelled a substitute. Runtime support gates availability
independently of capability — a first-class risk for a local strategy that does not exist for a
hosted API.

## 24 GB tier — quantisation instead of a smaller model

| Qwen3.8-27B | 8-bit | 4-bit | change |
|---|---|---|---|
| % of Opus ceiling | 81 % | **77 %** | −4 pts |
| grounding | 0.879 | 0.844 | −0.035 |
| fabricated | 2 (3.4 %) | **0** | −2 |
| peak memory | 32.3 GB | **18.85 GB** | −13.4 GB |
| wall clock | 1,834 s | 403 s | 4.6× faster |
| generation | 8.8 tok/s | 15.4 tok/s | +75 % |

**Capacity beats precision, and it is not close.** Halving precision on a 27B cost 4 points; dropping
to a 9B at the same precision cost 40. Both free comparable memory. The 4-bit run was also *cleaner*
on fabrication than the 8-bit.

**It still does not fit 24 GB.** Peak memory measured at two transcript lengths gives the KV slope
directly: 14,273 tokens → 18.85 GB, and 64,034 tokens → 22.41 GB. That is a **17.8 GB resident floor
plus ~72 MB per 1,000 tokens**. Against macOS's default GPU-wired cap of ~75 % of RAM:

| machine | default GPU limit | longest transcript that fits |
|---|---|---|
| 16 GB | ~12 GB | none — the model does not load |
| 24 GB | ~18 GB | ~2k tokens, i.e. effectively none |
| 24 GB, limit raised to 20 GB | 20 GB | ~30k tokens |
| 24 GB, limit raised to 22 GB | 22 GB | ~58k tokens, leaving 2 GB for the rest of the machine |
| 32 GB+ | ~24 GB | comfortable |

**The practical floor for this stage is 32 GB.** A 24 GB Mac runs it only with `iogpu.wired_limit_mb`
raised by `sudo sysctl` — lost on reboot unless persisted, and not fit for general setup instructions.

*Measured on a 48 GB machine.* The memory figures are real; the 16/24 GB verdicts compare those
figures against those machines' documented limits, not runs on such machines.

## Replication on real sessions (n = 3)

Two further transcripts from a private corpus of real sessions, ranked by the distiller's own
recorded signal counts. Same harness, prompt and judge; each transcript gets its own Opus reference
and its own self-agreement ceiling. Only the two candidates that carry the decision were re-run.

| transcript | ceiling | Qwen3.8-27B 4-bit (local, $0) | Haiku 4.5 (hosted) |
|---|---|---|---|
| 13.6k · Claude (original) | 0.918 | 77 % | 58 % |
| 8.6k · Claude | 0.930 | 87 % | 65 % |
| 63.3k · Codex | 0.869 | **96 %** | 53 % |
| **mean** | 0.906 | **87 %** | **59 %** |

| faithfulness | 13.6k | 8.6k | 63.3k | mean |
|---|---|---|---|---|
| local grounding | 0.844 | 0.914 | 0.889 | **0.882** |
| Haiku grounding | 0.552 | 0.766 | 0.600 | **0.639** |
| local fabricated | 0 | 0 | 0 | **0** |
| Haiku fabricated | 6 | 1 | 1 | 8 |
| local distorted | 7 | 3 | 5 | 15 |
| Haiku distorted | 20 | 10 | 19 | 49 |

**The claim that argues against the routing directive is no longer n = 1.** A free local model beat
the hosted cheap tier on three of three real sessions, across two CLI formats, with zero fabrications
against eight. The original transcript was the local model's *worst* showing.

**The ceiling is a property of the transcript** (0.918 / 0.930 / 0.869), not a constant — a study
reporting "% of a reference model" without measuring it per input mixes run-to-run variance into its
quality gaps.

**Observation, not a finding:** the local model improved as transcripts lengthened (77 → 87 → 96 %)
while the ceiling fell. Three points cannot support a mechanism. It does settle that the "long
transcripts unaddressed" caveat pointed the wrong way — length is not where the local model failed.

Artifacts in `corpus/`. The corpus excludes one session containing employer-internal infrastructure
detail, at its owner's direction.

## Conclusions

1. **A local open-weights model can do this stage — with 32 GB.** 81 % of Opus at 8-bit, 77 % at
   4-bit in under seven minutes, $0. Below 32 GB nothing tested is usable: at 24 GB the quality is
   there but the memory is not, and at 16 GB neither is.
2. **It is not a drop-in for the hosted cheap tier — it is better than it.** On this transcript the
   local 27B dominates Haiku on every quality axis and edges Sonnet on recall while trailing it
   slightly on fabrication, at no cost. The trade is entirely latency.
3. **The cheap-tier assumption in #50 deserves re-examination.** Haiku's 0.552 grounding and 10 %
   fabrication on user-model claims are a correctness problem, not a prose-quality problem.
4. **Thinking tokens are the optimization target**, not model size.

## What this does not answer

- **n = 1 transcript, n = 1 run per model.** No variance estimate. The ceiling (0.918) is a single
  measurement too. Treat every figure as provisional until replicated over ~5 sessions.
- **The judge is Opus, and the reference is Opus.** Self-preference bias is plausible even blind;
  it would inflate `opus-2` and deflate everyone else by an unknown amount. The adjudication pass
  fixes *consistency* of the fabrication boundary, not this bias.
- **16 GB — the case that actually matters — is untested.** This says what the *family* can do on
  48 GB, not what users get. Experiment 2 takes the 16 GB-class candidates (Qwen 3.x 8–9B, Gemma 4
  small, gpt-oss-20b at MXFP4) through this identical harness.
- **A rendered transcript is a proxy for live context.** In `/distill` today, Step 1 runs against the
  live conversation; here it runs against a text rendering with tool results truncated to 400/600
  chars. That proxy is right for the #51 auto-distiller (which will also read transcripts from disk)
  and wrong for measuring today's in-session `/distill`.
- **Only the harvest stage.** Encoding (Step 3 of `distill-process.md`) writes to the knowledge base
  and is a harder, higher-stakes job. Nothing here licenses running *that* locally.
- **Long transcripts are unaddressed.** 13.6k tokens fit trivially. A 100k-token session's KV cache
  will not fit on 16 GB; chunk-and-merge has to be designed and measured separately.

## Reproducing

Verified end to end by `tests/test_harness.sh` (offline, no API, no model). All tools resolve paths
from this directory; `EXP=<dir>` overrides the root.

```bash
uv venv --python 3.12 .venv && source .venv/bin/activate && uv pip install mlx-lm huggingface_hub
python tools/render_transcript.py <session.jsonl> > runs/transcript.txt
./tools/run_claude.sh opus opus-1                    # reference
python tools/judge.py extract opus-1                 # -> 116 atomic claims
./tools/run_claude.sh sonnet sonnet-1 && ./tools/run_claude.sh haiku haiku-1
python tools/run_local.py lmstudio-community/Qwen3.8-27B-MLX-8bit qwen38-27b-8bit-think
for c in opus-2 sonnet-1 haiku-1 qwen38-27b-8bit-think; do python tools/judge.py score opus-1 $c; done
python tools/adjudicate.py                           # one calibrated DISTORTED/FABRICATED boundary
python tools/report.py
```

## Files

| path | what |
|---|---|
| `tools/` | renderer, API runner, local MLX runner, judge, adjudicator, report builder |
| `tests/test_harness.sh` | offline smoke test: tool paths resolve, published numbers recompute, renderer is deterministic and keeps real user turns |
| `runs/harvest_system_prompt.md` | the exact prompt every model received |
| `runs/*.meta.json` | timing, tokens, cost, peak memory per run |
| `judge/*.score.json` | per-claim verdicts, distortion/fabrication notes, qualitative verdict |
| `judge/adjudication.json` | what the calibrated boundary pass changed, per candidate |
| `judge/opus-1.claims.json` | reference claim counts per section |
| `results.json` | the results table, machine-readable |

## What is published, and what is not

This repo is public and the input is a real session. What ships: all measurements, all tooling, the
judges' *evaluative* notes and verdicts. What does not: the rendered transcript, the five harvest
outputs, the 116 reference claim texts, the adjudication pool, and verbatim user speech — all of it
raw session content. Personal identifiers are generalised throughout.

The evaluative notes are kept deliberately, even though they characterise the session's participants,
**because they are the result** — "the model claimed the user knew X when the transcript shows the user
asking what X is" is the finding, and deleting it would leave the central claim unverifiable. The
person described is the repo owner, publishing their own session. `.gitignore` blocks the withheld
artifacts from ever being committed by accident; `tools/` regenerates all of them from any local
`.jsonl`.

## Follow-ups this experiment opens

- `docs/research/model-routing.html` currently recommends routing **extraction** to Haiku-tier
  subagents. This experiment is evidence against that for the harvest stage — but at n = 1 it is not
  enough to rewrite a published playbook, so the page is left alone and the tension is filed instead.
- No `docs/research/*.html` page, research-index entry or tracker entry ships here, unlike
  `research/2026-07-09-token-saver/`. This folder is the raw measurement record; the write-up for the
  site should follow the 16 GB experiment, when there is a user-facing recommendation to make.
- `AGENTS.md` says `research/*` branches are "never merged to main directly", while
  `research/2026-07-09-token-saver/` sits on main. One of the two should change.
