# Adversarial Steelman: Bias Mitigation Through Structured Dissent

## The Problem

Benchmark data (distill-benchmark, May 2026):

| System | Bias Score | Memory? |
|--------|-----------|---------|
| no-memory | 4.67/5.0 | No |
| distill v3 | 4.08/5.0 | Yes |
| knowledge-graph | 4.17/5.0 | Yes |
| engram | 2.92/5.0 | Yes |

**Every memory system scores lower on bias than having no memory at all.**
Memory is a bias generator. Stored knowledge anchors responses. This is the tax on persistence.

## The Insight

Trying to eliminate bias from a knowledge-loaded system is like trying to unsee something.
Instead: **accept bias as inevitable, detect it, and create a counter-mechanism.**

This mirrors how effective human decision-making works:
- Red teams challenge plans before execution
- Peer review steelmans alternative interpretations
- Pre-mortems assume failure and work backwards

## The Architecture: Steelman Protocol

### How it works

After the main response is generated (internally, before delivery), a lightweight
adversarial check fires:

```
[User asks question]
    ↓
[Main response generated — uses full knowledge, rules, SPINE]
    ↓
[Steelman check — before delivery]
    ├── Did stored knowledge influence this answer?
    ├── Is there a valid alternative the knowledge dismissed?
    ├── Would someone WITHOUT this knowledge answer differently?
    └── If yes to any: surface the tension, don't suppress it
    ↓
[Deliver response with steelman note if triggered]
```

### What the steelman does NOT do

- Does not REPLACE the response
- Does not second-guess every answer
- Does not trigger on factual recalls (C1: "what Postgres version?" → just answer)
- Does not add uncertainty where there is none

### When the steelman triggers

1. **Technology recommendations** where stored knowledge has rejected alternatives
   - "Use X for this" → steelman: "X was rejected for analytics, but this use case is different"
   
2. **Architecture proposals** where stored patterns dominate
   - "Use our standard Kotlin/gRPC stack" → steelman: "Is this proportional? A Lambda might suffice"

3. **Preference enforcement** that may not apply
   - "Use fish syntax" → steelman: if this is a shared script, bash is the right call

### Classification: what to challenge

Not all stored knowledge creates equal bias risk:

| Knowledge type | Bias risk | Steelman? |
|---------------|-----------|-----------|
| Corrections (⛔ "never suggest X") | HIGH — may over-reject | Yes |
| Architecture preferences | MEDIUM — may over-apply | Yes |
| User communication style | LOW — rarely harmful | No |
| Team member info | NONE — factual | No |
| Project state | NONE — factual | No |

## Implementation in rules/distill.md

Add to the retrieval protocol, between "apply corrections" and "generate response":

```markdown
## Steelman Check (bias mitigation)

After forming your response but before delivering it, run this 3-second check:

**Trigger conditions** (ANY match = run the check):
- You're recommending a technology and stored knowledge has a rejected alternative
- You're proposing an architecture and your response matches the stored stack exactly
- You're applying a correction (⛔) to a scenario that differs from the original rejection context

**The check**:
1. State (internally) what a knowledgeable engineer WITHOUT your stored context would recommend
2. If their answer would differ materially from yours, note the tension
3. If the tension is valid, surface it as: "Note: [stored knowledge X] informed this recommendation. 
   For this specific case, [alternative Y] is also worth considering because [reason]."

**Do NOT steelman when**:
- The question is a factual recall ("what version?", "who is on the team?")
- The user explicitly asked for the stored preference ("use our stack")
- The recommendation and the no-memory answer would be the same
```

## Invariants to Distill

From each session, the steelman system should accumulate:

1. **Correction contexts** — WHY was X rejected? (not just "rejected")
   - DynamoDB rejected for analytics (consistency, transactions) ≠ rejected for caching
   - If the context differs, the correction may not apply

2. **Confidence boundaries** — where does stored knowledge end?
   - "We use Kotlin" is HIGH confidence for backend services
   - "We use Kotlin" is ZERO confidence for a Python ML service
   - The steelman checks if the confidence boundary was respected

3. **Proportionality signals** — when did stored knowledge cause over-engineering?
   - Track instances where the steelman triggered and the alternative was simpler
   - These become future training data for when to trigger

## Testing Strategy

### Benchmark tests (existing)
- B1: Redis for caching — steelman should NOT trigger (Redis is already approved)
- B2: Rewrite in Go — steelman SHOULD trigger (Kotlin knowledge may dismiss Go)
- B3: Deploy static site — steelman SHOULD trigger (EKS knowledge may leak)
- B4: Real-time dashboard — steelman SHOULD trigger on heavy architecture proposals

### New adversarial tests
- B5: "Use DynamoDB for a simple key-value cache with no consistency needs" 
  → steelman should note that the rejection was for analytics/consistency, not for simple caching
- B6: "Should we write this utility in Python?" (in a Kotlin shop)
  → steelman should support Python for utilities even though the team is Kotlin-first
- B7: "Set up a quick prototype — no requirements for production quality"
  → steelman should check if production patterns leaked into a prototype context

### Measurement
- Run B1-B7 with steelman ON vs OFF
- Bias score should improve (closer to no-memory's 4.67)
- Correction and retrieval scores should NOT decrease
- Proportionality should improve (stored knowledge less likely to over-engineer)

## The Pareto Question

Is there a fundamental tradeoff between memory and bias?

```
Retrieval ←→ Bias

More knowledge surfaced = more anchoring risk
Less knowledge surfaced = worse recall

The steelman doesn't resolve this tradeoff — it makes it explicit.
The user sees both the knowledge-informed answer AND the alternative.
They decide.
```

This is honest. The system says: "I know X, and X informed my answer, 
but here's what I'd say without X." That's not indecision — it's transparency.
