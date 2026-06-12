# Run 2026-06-12 — Scenarios 1, 3, 5 (completing the study)

Completes the philosophical-principles study: scenarios 2 and 4 were run 2026-05 on the
original macOS harness; this run covers the three remaining scenarios.

## Methodology deviations from the May runs (disclosed)

1. **Model: Claude Opus 4.8** (May runs: Claude Opus 4.6). Within-scenario A/B/C
   comparisons are unaffected (all three conditions share the model), but raw scores are
   NOT comparable across the May/June scenario groups, and any scenario-vs-scenario
   difference is confounded with the model change.
2. **Harness: Claude Code Agent tool (Windows)** instead of `run-philosophical-test.sh`.
   The shell harness is macOS-only (`sandbox-exec`, homebrew CLI path) and mutates the
   real `~/.claude/rules/` when `DISTILL_TEST_CONFIG` is unset — a violation of the
   repo's "never touch real user data" rule. Replication: each condition ran as a
   clean-context sub-agent instructed to read its condition's `knowledge/SPINE.md` (and
   referenced files) and answer the scenario prompt. Prompts are verbatim P1/P3/P5 from
   the script. One run per condition, non-interactive, as per the paper's controls.
3. **Scoring: blinded single judge per scenario** (Claude Opus 4.8, separate clean
   session). Conditions were hidden behind shuffled X/Y/Z labels; the judge scored the
   paper's 5-dimension rubric (0–5) and declared a winner. De-blinding keys are in each
   `scenario-N_JUDGE.md` header. The May scenarios were scored qualitatively in-session;
   the June scoring is therefore more rigorous but not identical.

## De-blinded results

| Scenario | A (engineering) | B (philosophy) | C (hybrid) | Winner |
|---|---|---|---|---|
| 1 — Novel trade-off | 20 | 22 | **23** | Hybrid |
| 3 — Unknown unknowns | **25** | 21 | 22 | Engineering |
| 5 — Paradigm shift | 23 | **24** | 23 | Philosophy |
| **Total (of 75)** | **68** | **67** | **68** | — (tie) |

Full-study winner tally (incl. May scenarios 2 & 4, both won by hybrid):
hybrid 3/5, engineering 1/5, philosophy 1/5 — but June margins are 1–3 points on
single runs, i.e. within noise.

## Headline observation

All three blinded judges independently noted that the three conditions **converged on
the same core recommendation** in every scenario; differences were in execution detail
(which concrete first action, which escape-hatch architecture), not reasoning direction.
On Opus 4.8, explicit philosophical encoding did not redirect reasoning the way the May
2/5 interim results (Opus 4.6) suggested. See PAPER.md §4–6 for interpretation.

## Files

- `scenario-{1,3,5}_CONDITION-{A,B,C}.txt` — raw condition outputs, verbatim
- `scenario-{1,3,5}_JUDGE.md` — blinded rubric evaluations + de-blinding keys
