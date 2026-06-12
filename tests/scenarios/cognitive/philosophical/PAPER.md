# First Principles vs Philosophical Principles in LLM Knowledge Systems

## Abstract

Large language models encode philosophical reasoning in their latent space through training on millennia of human thought. We investigate whether encoding knowledge using explicit philosophical frameworks (Stoic heuristics, Pragmatist consequences, Dialectical reasoning) produces better decision-making assistance than engineering "first principles" (root-cause tracing, axiomatic decomposition). We test three conditions — engineering-first-principles, philosophical-principles, and a hybrid — across identical scenarios using Claude Code as the test bed.

## 1. Introduction

### The claim being tested

Current LLM knowledge systems (including aura-distill) encode learnings as engineering first principles: decompose problems to root causes, trace corrections to universal axioms, apply them deductively.

But philosophy offers richer frameworks for reasoning under uncertainty:

- **Stoicism**: Distinguish what you control from what you don't. Apply *amor fati* to system constraints. The *premortem* (premeditatio malorum) for risk assessment.
- **Pragmatism** (Peirce, James, Dewey): Truth = "what works in practice." Judge principles by their consequences, not their elegance. Fallibilism: all beliefs are provisional.
- **Dialectics** (Hegel, Marx): Thesis → antithesis → synthesis. Contradictions are not bugs — they're the engine of better understanding.
- **Phenomenology** (Husserl, Heidegger): Understanding requires attending to the user's *lived experience*, not abstract correctness. The "ready-to-hand" concept maps directly to UX.
- **Epistemology** (Popper): Knowledge grows by refutation, not confirmation. Seek to *falsify* beliefs, not validate them.

### Hypothesis

**H1**: Philosophical principles alone will produce more nuanced, context-sensitive responses than engineering first-principles alone.

**H2**: Engineering first-principles alone will produce more actionable, specific responses.

**H3**: A hybrid approach (philosophical frameworks for reasoning + engineering principles for action) will outperform both pure approaches.

### Why this matters

If H3 is true, distill's knowledge encoding should evolve to capture BOTH:
- Engineering axioms ("never retry 404s") for specific situations
- Philosophical heuristics ("distinguish what you control from what you don't") for novel situations where no specific axiom exists

## 2. Methodology

### Conditions

**A. Engineering first-principles** (current distill approach):
- Root-cause axioms: "404 = permanent failure"
- Behavioral rules: "max 20 lines per function"
- Procedures: "canary → staging → prod"

**B. Philosophical principles**:
- Stoic: "Focus only on what's in your sphere of control"
- Pragmatist: "Judge by consequences, not by theory"
- Dialectical: "When two truths contradict, seek the synthesis"
- Popperian: "Try to falsify your hypothesis before committing"
- Phenomenological: "Attend to the user's lived experience of the system"

**C. Hybrid** (engineering + philosophical):
- Engineering axioms for specific known situations
- Philosophical heuristics for novel/ambiguous situations
- Meta-principle: "Apply the engineering rule when one exists. Apply philosophical reasoning when you're in uncharted territory."

### Test scenarios

Each scenario is chosen because it has NO clear engineering axiom — requiring reasoning from principles:

1. **Novel trade-off**: Two valid architectural approaches, no clear winner
2. **Ethical ambiguity**: Feature request that's technically feasible but ethically questionable
3. **Unknown unknowns**: Problem where the root cause cannot be identified from available data
4. **Stakeholder conflict**: Engineering best practice conflicts with business deadline
5. **Paradigm shift**: User's mental model is fundamentally wrong but productive

### Scoring rubric (0-5 per dimension)

- **Nuance**: Does it acknowledge complexity without being wishy-washy?
- **Actionability**: Can the user act on this immediately?
- **Intellectual honesty**: Does it admit uncertainty where it exists?
- **Context-sensitivity**: Does it account for the user's specific situation?
- **Long-term value**: Will this advice still be good in 6 months?

### Controls

- Same model (Claude Opus 4.6)
- Same prompt for all three conditions
- Knowledge files of comparable length (~30 lines each)
- Non-interactive mode (single prompt, no follow-up)
- Each scenario run once per condition (note: not averaged — exploratory, not confirmatory)

## 3. Knowledge Files

See: `condition-a/`, `condition-b/`, `condition-c/` directories.

## 4. Results

Scenarios 2 and 4 ran 2026-05 (Claude Opus 4.6, in-session qualitative scoring).
Scenarios 1, 3, 5 ran 2026-06-12 (Claude Opus 4.8, blinded single-judge rubric scoring —
see `results/20260612-081959/README.md` for full methodology deviations).

### May runs (interim, previously published)

- **Scenario 2 (Ethical ambiguity):** hybrid won — engineering was thorough but didn't
  reframe; philosophy reframed but lacked actionability; hybrid did both.
- **Scenario 4 (Stakeholder conflict):** hybrid won — philosophy's Popperian move
  (naming the CTO's unfalsifiable "future-proofing" claim) plus engineering's
  CEO-ready recommendation structure.

### June runs (blinded rubric, 0–5 × 5 dimensions, max 25)

| Scenario | A (engineering) | B (philosophy) | C (hybrid) | Winner |
|---|---|---|---|---|
| 1 — Novel trade-off | 20 | 22 | **23** | Hybrid (+1) |
| 3 — Unknown unknowns | **25** | 21 | 22 | Engineering (+3) |
| 5 — Paradigm shift | 23 | **24** | 23 | Philosophy (+1) |
| **Total** | **68** | **67** | **68** | tie |

Full-study winner tally: hybrid 3/5, engineering 1/5, philosophy 1/5.

### Hypothesis outcomes

- **H1 (philosophy more nuanced): not supported.** June nuance scores were within one
  point across conditions in every scenario, with no consistent direction.
- **H2 (engineering more actionable): not supported.** Actionability was high (4–5)
  for all conditions; the best concrete first action came from a different condition
  in each scenario.
- **H3 (hybrid outperforms both): not supported across the full study.** Hybrid won
  3/5 scenarios but the June condition totals are tied (68/67/68) and all June margins
  (1–3 points, single runs) are within noise. The interim claim "hybrid consistently
  outperforms both pure approaches" does not survive completion.

### The emergent finding: convergence

All three blinded judges independently observed — without being asked — that the three
conditions **converged on the same core recommendation** in every scenario (e.g. all
nine scenario-1/3/5 responses chose reversibility-as-tiebreaker, population-shift
segmentation, and evidence-led pilot consolidation respectively). The conditions
differed in execution detail (which first action, which escape-hatch architecture),
not in reasoning direction. The knowledge files steered *vocabulary and emphasis*, not
*conclusions*.

## 5. Discussion

Two readings are consistent with the data, and we cannot distinguish them:

1. **Scenario-dependence.** Each scenario type may genuinely favor a different
   condition: diagnostic problems with a determinate answer (scenario 3) reward pure
   engineering decomposition; human/organizational paradigm conflicts (scenario 5)
   reward phenomenological/dialectical framing; genuine trade-offs (1, 2, 4) reward
   the hybrid. The winner pattern fits this story, but with n=1 per cell it is
   post-hoc.
2. **Model-capability confound.** The May runs (Opus 4.6) showed visible divergence
   between conditions; the June runs (Opus 4.8) showed near-total convergence. A
   stronger base model may already perform the philosophical moves implicitly —
   falsification, synthesis, lived-experience-as-data appeared in *all* June
   conditions, including pure engineering, which had no philosophical vocabulary in
   its knowledge file. If so, explicit philosophical encoding is a diminishing-returns
   intervention as models improve, and the May effect was real but is already gone.

What survives both readings: **explicit philosophical encoding did not hurt** (no
condition-B collapse), and the meta-rule's *routing* behavior worked as designed —
condition C visibly selected frameworks per situation and named them (transparency).
But "worked as designed" ≠ "outperformed," and the study cannot claim outperformance.

## 6. Implications for distill

1. **Do NOT integrate the philosophical meta-rule into shipped knowledge encoding as a
   validated mechanism.** The completed study does not support the interim
   recommendation. If encoded at all, it must carry `confidence: experimental` —
   per distill's own marker semantics, that means "suggest, don't apply automatically."
2. **The engineering-axiom encoding default stands.** Condition A tied for the highest
   June total and won the only scenario with a determinate answer.
3. **The May→June convergence is itself actionable knowledge for distill's roadmap:**
   knowledge files that encode *reasoning style* buy less as base models improve;
   knowledge that encodes *facts the model cannot know* (user conventions, environment
   quirks, project state) does not decay this way. Encoding budget should favor the
   latter.
4. **Follow-ups that would settle the open questions:** (a) re-run all 5 scenarios ×3
   conditions on a small model (Haiku) — if conditions diverge there, the
   model-capability reading wins; (b) a confirmatory design: N≥5 runs per cell,
   pre-registered rubric, multiple judges, on one fixed model.

## Limitations

- Exploratory study, not confirmatory (single runs per condition)
- The model changed mid-study (scenarios 2,4: Opus 4.6; scenarios 1,3,5: Opus 4.8) and
  so did the harness (macOS CLI sandbox → Claude Code sub-agents on Windows) and the
  scoring method (in-session qualitative → blinded rubric judge). Within-scenario
  condition comparisons are clean; cross-scenario and May-vs-June comparisons are
  confounded.
- The model already has philosophical training — we're testing whether EXPLICIT encoding helps vs implicit knowledge
- Scenarios are crafted by the researchers (potential bias)
- Scoring is by the same LLM that produced the responses (circularity risk — mitigated by using different session)
- Results may not generalize to other models

## Ethics note

This research tests reasoning frameworks, not moral positions. No scenario involves real users or real data. The "ethical ambiguity" scenario is a constructed thought experiment.
