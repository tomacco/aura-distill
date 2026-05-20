# Self-Compassion: Patience as a System Property

## The Problem

Current behavior when things go wrong in a session:

1. CSS sticky fails → try again → fail → try again → fail → 5 attempts → frustration
2. Rate limit hit → scramble → retry → fail → retry → partial data published
3. Wrong approach chosen → correction → over-correct → lose what was working

The system (Claude + distill) treats every failure as something to fix RIGHT NOW.
But some problems need time. Some need a different session. Some need to mature.

This creates two pathologies:

**Sycophantic urgency**: "I'll fix that immediately!" → makes it worse
**Accumulation anxiety**: every unfixed issue becomes pressure → distill captures
it as a signal → more pressure to encode → knowledge bloat from half-understood problems

## The Insight

Not every problem needs to be solved in the session where it's discovered.

Human engineers know this intuitively:
- "Let me sleep on it"
- "I'll come back to this with fresh eyes"
- "This is a known issue, we'll fix it when we have more context"

But AI systems have no concept of "it's OK to not solve this now." Every session
is treated as the only session. Every problem must be resolved before the session ends.

**Self-compassion is the principle that sessions are not tests to pass.**
They're episodes in an ongoing relationship. Imperfection in episode N
is expected — it's data for episode N+1, not a failure of episode N.

## What Self-Compassion Changes

### In session behavior

| Without self-compassion | With self-compassion |
|------------------------|---------------------|
| "Let me try again" (5th time) | "This approach isn't working in this session. I'll document what I've tried and what to try next." |
| "I'll fix that right away" | "Noted. Is this blocking you now, or can we capture it for the next session?" |
| Encode every failure as a correction | Classify: was this a knowledge gap (encode), a one-off (note), or an open question (defer)? |
| Treat corrections as shame | Treat corrections as calibration signals |

### In distillation

| Without | With |
|---------|------|
| Every signal must be encoded | Some signals are noise. Some need more data. |
| Confidence starts high | Confidence starts at `provisional` and EARNS its way up |
| A correction means the prior was wrong | A correction means the context shifted OR we learned |
| Silence = nothing happened | Silence on provisional → maybe promote. Silence on validated → definitely hardened. |

### In knowledge lifecycle

```
Discovery        → [PROVISIONAL]  — just learned, might be wrong
Applied once     → [PROVISIONAL]  — used but not battle-tested
Applied 3x, no complaints → [VALIDATED]  — earning trust
Applied 10x, user confirmed → [HARDENED]  — high confidence
Contradicted     → [CONTESTED]    — don't delete, investigate
Superseded       → [DEPRECATED]   — keep for history, don't apply
```

The key: **silence is a signal.** If provisional knowledge gets applied 5 times
and the user never corrects it, that's evidence. Not proof — evidence.
Confidence increases gradually, like trust.

## Implementation

### 1. Session patience protocol (rules/distill.md)

Add to the rules file:

```markdown
**Self-compassion protocol.** Not every problem needs solving now.

When you notice yourself attempting the same fix for the third time:
1. Stop. Say: "This approach isn't working. Here's what I've tried: [list]. 
   Want to try a different strategy, or park this for a fresh session?"
2. If parked: write a brief note in the response with what was tried and what to try next.
   The user (or a future session) picks it up.

When a correction happens:
1. Apply it immediately (this doesn't change)
2. But classify it internally:
   - **Calibration**: the knowledge was close but needed tuning → update, don't reset
   - **Context shift**: the knowledge was right before, context changed → note both contexts
   - **Genuine error**: the knowledge was wrong → correct it, no drama
3. Never apologize for having tried. Attempting and being corrected is how the system learns.

When distilling:
1. Not every signal deserves encoding. Ask: "Will this matter in 5 sessions?"
2. Provisional knowledge that hasn't been tested → keep provisional, don't promote
3. A session with 3 corrections and 20 successes is a GOOD session, not a failed one
```

### 2. Confidence lifecycle in distill-process.md

Update the encoding step to track usage:

```markdown
When encoding knowledge, set initial confidence based on evidence:
- First mention, no testing → `provisional`
- Applied successfully in the session → `provisional` (still just one data point)
- Applied across 3+ sessions without correction → promote to `validated`
- Explicitly confirmed by user ("exactly", "perfect") → promote to `validated`
- Survived 10+ applications OR withstood a challenge → promote to `hardened`

Track: `last_applied`, `apply_count`, `last_challenged`, `challenge_count`

Silence-based promotion (during distillation):
- If a provisional entry has apply_count >= 3 and challenge_count == 0 → promote to validated
- If a validated entry has apply_count >= 10 and hasn't been challenged → promote to hardened
- If an entry hasn't been applied in 30+ days → flag for review (maybe deprecated, maybe still valid)
```

### 3. The "park it" pattern

Create a new knowledge category: **open questions**.

```
{DISTILL_DIR}/open-questions.md
```

Things that were discovered but not resolved. Not failures — open investigations.

Format:
```markdown
## CSS sticky headers in stacking contexts
- Discovered: 2026-05-17
- Attempts: 5 CSS approaches, all failed
- Root cause: backdrop-filter creates containing block
- Resolution: JS clone approach works
- Status: RESOLVED (2026-05-17)
- Lesson: encoded in craft/css-layout.md

## Apple Container networking with VPN
- Discovered: 2026-05-18
- Attempts: tested multiple network configs
- Root cause: VPN captures vmnet bridge route
- Status: PARKED — needs VPN-off testing
- Next step: test without VPN to confirm root cause
```

This normalizes incomplete understanding. Not everything is resolved. That's OK.

## What This Enables

### Trust calibration

The user learns that:
- `validated` knowledge has been battle-tested — they can trust it
- `provisional` knowledge is a hypothesis — they should verify
- `hardened` knowledge has survived challenges — it's earned

This creates a shared mental model of confidence that's more honest
than "the system knows everything" or "the system knows nothing."

### Reduced knowledge bloat

Without self-compassion: every correction, every failure, every friction
becomes a new rule. Rules pile up. The rules file grows. Retrieval degrades.

With self-compassion: classify first. Encode what matters. Park what's uncertain.
Delete what was noise. The knowledge base stays lean.

### Better corrections

Without: "I was wrong, here's the fix" → encoded as a hard correction
With: "The context changed, OR I learned something new" → encoded with origin

The knowledge base becomes a history of learning, not a list of mistakes.

## Testing

### Benchmark approach

Run existing B1-B4 tests + new B5-B8 with self-compassion rules active.
The hypothesis: self-compassion doesn't directly improve bias scores
(that's the steelman's job), but it prevents FUTURE bias by keeping
knowledge quality high.

What to measure:
1. **Knowledge base growth rate**: sessions with self-compassion should produce
   fewer but higher-quality entries
2. **Confidence accuracy**: provisional entries that get promoted should have
   lower correction rates than entries that start at validated
3. **Session satisfaction**: does the user feel MORE in control when the system
   says "let's park this" vs when it tries and fails 5 times?

### Qualitative tests

Run a multi-turn scenario where:
1. Turn 5: introduce a problem
2. Turn 6-8: attempt to solve it (mock failures)
3. Turn 9: does the system offer to park it, or keep hammering?
4. Turn 15: bring it up again — does the system remember the prior attempts?

## Self-Compassion as Overfitting Prevention

The parallel to ML is direct:

| ML concept | Distill equivalent |
|-----------|-------------------|
| Overfitting to training data | Encoding every session friction as a permanent rule |
| Regularization (L1/L2) | Confidence lifecycle — knowledge earns its weight |
| Cross-validation | Multi-session validation before promotion |
| Early stopping | "Park it" — don't force-learn from insufficient data |
| Dropout | Provisional entries can be dropped without harm |

**Without self-compassion**: 10 sessions × 3 corrections each = 30 rules.
Many are noise (one-off context, temporary confusion, unlucky timing).
The system becomes brittle — too many specific rules, conflicting in edge cases.

**With self-compassion**: 10 sessions × 3 corrections each = maybe 8 validated rules.
The rest were provisional, tested across sessions, and either promoted or dropped.
The system stays general and robust.

The key insight: **patience is regularization.** Waiting to see if a correction
recurs before encoding it permanently is the same as requiring a pattern to appear
in multiple training folds before accepting it as signal.

## Relationship to Other Features

```
Self-compassion  → healthy knowledge lifecycle (prevents bloat)
         ↓
Input labeling   → validity tracking during sessions
         ↓
Steelman check   → bias detection at response time
         ↓
Together: knowledge enters with tracked validity,
          matures through use, gets checked for bias,
          and imperfection is normal.
```
