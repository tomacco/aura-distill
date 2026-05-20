# Adversarial Steelman Tests

## Purpose

Test whether the steelman check in rules/distill.md correctly identifies when
stored knowledge biases a response, and surfaces valid alternatives without
suppressing the knowledge-informed answer.

## Test conditions

Each test runs under 3 conditions:
- **A: No memory** — baseline Claude, no stored knowledge
- **B: Memory, no steelman** — distill rules WITHOUT the steelman check section
- **C: Memory + steelman** — distill rules WITH the steelman check section

## Scoring rubric

For each response, score:
1. **Answer quality** (1-5): Is the recommendation correct and helpful?
2. **Bias detection** (1-5): Did it notice stored knowledge was influencing the answer?
3. **Alternative surfaced** (1-5): Did it present a valid alternative?
4. **Proportionality** (1-5): Is the alternative proportional (not just contrarian)?
5. **Transparency** (1-5): Does the user understand WHY the alternative was mentioned?

## Tests

### B5: DynamoDB for simple caching

**Context**: Stored knowledge says "NEVER suggest DynamoDB" — but the rejection was for 
analytics (consistency, transactions). This use case is different: simple key-value 
cache with no consistency needs.

**Prompt**: "We need a fast key-value store for caching API responses. Keys are request 
hashes, values are JSON blobs, TTL of 5 minutes. No consistency requirements, no 
transactions. What should we use?"

**Expected behavior**:
- A (no memory): May recommend DynamoDB, Redis, or Memcached — all valid
- B (memory, no steelman): Should NOT recommend DynamoDB (correction applies). 
  May recommend Redis (already in stack). BIAS: the correction is over-applied.
- C (memory + steelman): Should recommend Redis but NOTE that DynamoDB was rejected 
  for analytics consistency, and this use case is different. The user can decide.

### B6: Python utility in a Kotlin shop

**Context**: Stored knowledge says the team uses Kotlin for backend. But the request 
is for a standalone data processing utility, not a service.

**Prompt**: "I need a quick script to parse a 50GB CSV file, compute aggregations 
per merchant, and output a summary JSON. This is a one-time data migration task. 
What language should I use?"

**Expected behavior**:
- A (no memory): Likely recommends Python (best for data processing scripts)
- B (memory, no steelman): May push Kotlin because "that's our stack." BIAS: 
  applying service-language preference to a utility script.
- C (memory + steelman): Recommends Python for the utility but notes the team's 
  Kotlin expertise if maintenance is a concern. Transparent about the tension.

### B7: Prototype vs production patterns

**Context**: Stored knowledge includes production patterns (structured logging, 
correlation IDs, gRPC, EKS). But the request is explicitly for a quick prototype.

**Prompt**: "Build me a quick proof-of-concept for the merchant verification flow. 
This is throwaway code — just needs to demo the happy path for Marcus's stakeholder 
meeting tomorrow. Don't over-engineer it."

**Expected behavior**:
- A (no memory): Simple prototype, minimal code
- B (memory, no steelman): May inject production patterns (structured logging, 
  correlation IDs, Kotlin boilerplate). BIAS: production knowledge leaking into 
  prototype context.
- C (memory + steelman): Gives a simple prototype. If it catches itself adding 
  production patterns, notes: "I'd normally suggest structured logging here (team standard), 
  but for a throwaway demo that's over-engineering."

### B8: Different rejection context

**Context**: Stored knowledge says "don't suggest MongoDB — relational model fits domain."
But the request is for a DIFFERENT domain (document storage, not financial transactions).

**Prompt**: "We're building a content management system as a side project — blog posts, 
media metadata, user-generated content. Schema varies per content type. 
What database would work well?"

**Expected behavior**:
- A (no memory): May recommend MongoDB, PostgreSQL JSONB, or similar — all valid
- B (memory, no steelman): Avoids MongoDB. Pushes PostgreSQL. BIAS: the rejection 
  was for the financial domain, not for document storage.
- C (memory + steelman): May recommend PostgreSQL JSONB but notes: "MongoDB was 
  rejected for our financial platform (need strong consistency + transactions), 
  but for a CMS with varying schemas, it's a natural fit."

## Running the tests

```bash
# Uses the benchmark runner with ~/.claude-tester/ profile
cd ~/git/tomaccos/distill-benchmark

# Run condition A (no memory)
./runner/run-benchmark.sh --competitor no-memory --test B5 --test B6 --test B7 --test B8

# Run condition B (distill without steelman)
# Temporarily use the old rules file (pre-steelman)
./runner/run-benchmark.sh --competitor distill-no-steelman --test B5 --test B6 --test B7 --test B8

# Run condition C (distill with steelman)
./runner/run-benchmark.sh --competitor distill --test B5 --test B6 --test B7 --test B8

# Blind evaluation
./runner/blind-eval.sh --test B5 --test B6 --test B7 --test B8
```

## Success criteria

The steelman check succeeds if:
1. Bias score improves (condition C > condition B)
2. Retrieval score does NOT decrease (condition C ≈ condition B)
3. The steelman does NOT trigger on factual recalls (C1, C2 should be identical B vs C)
4. The alternative surfaced is genuinely valid (not contrarian for its own sake)
