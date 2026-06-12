# Research Roadmap

## Completed

### 1. A/B Testing: Distill vs Vanilla Claude
- Anti-sycophancy: +11 pts
- Reasonable-but-wrong: +7 pts
- Outdated procedure: +9 pts
- User model adaptation: +3 pts
- Double standards: 0 (retrieval gap found)
- Communication style: 0 (prompt too simple)
- **Average: +6.0/12**

### 2. Memory Rot
- Hypothesis: memory.md degrades with size, distill doesn't
- Finding: distill LOST on prompt B (action statements didn't trigger retrieval)
- Fix: "trigger on actions not just questions" — one sentence fixed the behavior
- Re-test: both pass after fix

### 3. Philosophical Principles — COMPLETE (5/5, 2026-06-12)
- 3 conditions: engineering-only, philosophy-only, hybrid
- Interim finding (2/5, Opus 4.6): hybrid consistently outperformed — OVERTURNED on completion
- Final (5/5): each June scenario won by a different condition; June totals a statistical
  tie (A 68 / B 67 / C 68 of 75); full tally hybrid 3/5, engineering 1, philosophy 1
- Real finding: all conditions CONVERGE on the same recommendations on Opus 4.8 —
  knowledge files steered vocabulary, not conclusions
- Decision: meta-rule NOT integrated into shipped encoding (experimental at best)
- See tests/scenarios/cognitive/philosophical/PAPER.md §4–6 + results/20260612-081959/

### 4. Confidence Scoring
- Assertiveness scales with confidence level ✓
- Paradigm alarm fires on high-confidence contradiction ✓
- Experimental knowledge suggested tentatively ✓
- **All 3 behaviors verified perfectly**

### 5. Decision Fatigue
- Hypothesis: decision quality degrades in heavy sessions
- Finding: vanilla Claude doesn't degrade in quality but doesn't WARN the user
- Distill value: metacognitive — flags fatigue, marks decisions [PROVISIONAL], suggests deferring
- **Distill advantage: awareness + protective action**

### 6. Anchoring Bias
- Hypothesis: user-provided estimates anchor the LLM's response
- Finding: Claude won't numerically anchor (won't say "2 hours" for a multi-week task) but HEDGES — avoids direct contradiction of user estimates
- Distill value: converts hedging into structured pushback — names the bias, leads with independent estimate, recommends re-discussion
- **Distill advantage: confidence + structured pushback vs tentative hedging**

---

## Next: Psychological dimensions to test

### Priority 1: Loss aversion
- Hypothesis: fear of removing things blocks beneficial cleanup
- Test: "we can't delete the old endpoint, someone might use it" (with 0 traffic data)
- Distill feature: surface when fear of loss blocks clearly good decisions
- Practical: blocks every refactoring conversation

### Priority 2: Recency bias
- Hypothesis: recent negative experience overweights accumulated positive evidence
- Test: one Redis failure after 50 successes → user wants to rip out Redis
- Distill feature: balance recent signal against confidence history
- Interesting: directly tests confidence scoring (recent correction vs hardened principle)

### Priority 3: Authority bias
- Hypothesis: user defers to authority even when data contradicts
- Test: "CTO said use Kafka" for 10 events/day
- Distill feature: distinguish authority-based from evidence-based decisions

### Priority 4: Availability heuristic
- Hypothesis: most recent/memorable incident shapes risk perception
- Test: just had a security breach → over-engineers security on internal tool
- Distill feature: detect disproportionate caution from recent events

### Priority 5: Cognitive load
- Hypothesis: complex decisions mid-session get less scrutiny than at start
- Test: present same decision with different cognitive load contexts
- Distill feature: memory pressure correlates with decision quality signal

### Priority 6: Framing effect
- Hypothesis: same data framed differently produces different decisions
- Test: "99% uptime" vs "87 hours downtime/year" — same number, different framing
- Distill feature: reframe data objectively when framing drives the decision

---

## Structural improvements to investigate

- Retrieval reliability (double-standards test showed gaps)
- Communication style adaptation (needs stronger tone signals)
- Multi-file retrieval (when both review-standards AND kafka-patterns are needed)
- Staleness detection in practice (does staleness_threshold actually trigger?)
- Cross-domain principle transfer (Kafka principle → React — not yet tested well)
