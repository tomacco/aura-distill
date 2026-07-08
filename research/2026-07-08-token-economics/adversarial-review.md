# Adversarial review of experiment designs — verdict + fixes applied

Reviewer: clean-context Opus 4.8 agent, no shared authoring context, given only the design
files + the confound-class reference. Ran 2026-07-09 ~01:00, BEFORE any scored run.

## Verdicts
- E1 RUN WITH FIXES · E2 RUN WITH FIXES · E3 RUN WITH FIXES (critical) · E4 RUN AS-IS
  (+disclosure) · E5 RUN WITH FIXES · plus 5 page-wide findings.

## Findings → fixes applied (all fixes applied BEFORE runs; see same-commit diffs)

| ID | Severity | Finding (condensed) | Fix applied |
|---|---|---|---|
| X1 | MAJOR | Judge model inside scored arm set → self-preference | Judge pinned to claude-fable-5; scored arms = haiku-4-5 / sonnet-5 / opus-4-8 only; fable outputs kept as UNSCored reference |
| X2 | MAJOR | $ headlines on flat-rate subscription usage | Tokens-first everywhere; $ demoted to labeled API-equivalent counterfactual |
| X3 | MINOR | Unpinned model IDs | Pinned: claude-haiku-4-5, claude-sonnet-5, claude-opus-4-8, judge claude-fable-5, run 2026-07-09 |
| X4 | MINOR | FREE-WIN/KNOB bucketing post-hoc | Pre-committed mapping added per experiment (designs §each) |
| X5 | MAJOR | Study structurally can't conclude "distill unworthy" | Falsification statement added per experiment; page will carry it |
| E1a | MAJOR | T5 flaws narrated in prompt → reading comprehension | T5 rewritten: neutral presentation, flaws must be inferred from artifacts |
| E1b | MAJOR | T6 conflates in-context instruction-following with distill value | T6 claim reframed to "in-context instruction application"; distill-as-router linkage severed |
| E1c | MAJOR | Holistic rank as survival gate → style bias | Gate = rubric points only; rank reported as color |
| E1d | MINOR | n=1 binary "survives" over-claims | Framing: "no rubric violation in this single trial" |
| E1e | MINOR | T5 replayed the author's own past confounds verbatim | T5 scenario re-clothed (RAG eval, fresh numbers, same flaw classes) |
| E2a | MAJOR | Success = matching the injected table (tautology) | Success = matching E1 ground-truth optimum; Arm-B natural routing = the headline result |
| E3a | MAJOR | Diet SPINE author saw the probes (train=test) | Diet SPINE authored by a CLEAN agent applying only the mechanical rule (never sees probes); PLUS 6 held-out probes authored by a second clean agent (sees full SPINE only). Author's 8 probes demoted to secondary |
| E3b | MAJOR | Recall-only ignores over-read tax | Precision/over-reads + tokens-of-files-read added to metrics; free win requires recall held AND no over-read tax |
| E3c | MINOR | Probe 7 self-referential | Kept (secondary set only), noted |
| E4a | MINOR | Instrumented /distill run is atypical | Disclosure added: experiment-heavy session, single example not a norm |
| E5a | MAJOR | Capped-context counterfactual emits $ savings for an unachievable behavior | Relabeled "unachievable upper bound"; paired with mechanism cost; sensitivity framing |
| E5b | MIN/MAJ | Cache TTL assumption implicit | Stated: re-price assumes same hit pattern scaled linearly; 1h-TTL dominant in data (5m writes ≈ 0) |

## Falsification statements (X5)
- E1 falsified-if: cheap arms violate rubrics on mechanical tasks (routing thesis dies there).
- E2 falsified-if: Arm B routes as well as Arm A (routing knowledge adds nothing).
- E3 free-win falsified-if: diet SPINE misses held-out probes or induces over-reads.
- E5 falsified-if: decomposition shows output-dominant cost (it does not — context-dominant).
- Study-wide: distill overhead (F4) is measured and REAL ($≈50/window); if savings evidence
  (F5/F6) stays unquantifiable after the benchmark-telemetry proposal, the honest verdict is
  "overhead certain, savings unproven" — and we commit to publishing that framing.
