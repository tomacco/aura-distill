# Capabilities — the durable layers of model routing

Distill's model-routing foundation, split by how fast each layer rots:

| Layer | File | Contains | Rots |
|---|---|---|---|
| Policy | [POLICY.md](POLICY.md) | how routing decisions are made | years |
| Taxonomy | [TAXONOMY.md](TAXONOMY.md) | the demand dimensions tasks declare | ~yearly |
| Join spec | [JOIN-SPEC.md](JOIN-SPEC.md) | where commodity model metadata comes from | slow |
| Methodology | [METHODOLOGY.md](METHODOLOGY.md) | how capability scores are measured | slow |
| **Scores** | **not here — by design** | per-model measurements | **weeks** |

**Why no scores in this repo.** Per-model capability scores rot on the vendors' release
cadence, and the probes that discriminate between models are exactly the ones that must
never be published (a public probe bank enters the next model generation's training data
by construction — it self-erases). So scores are generated **locally, per installation**,
by the capabilities-matrix skill, against *your* model lineup — including private or
fine-tuned models — and live in `{DISTILL_DIR}/data/capabilities-local.json`, which never
leaves your machine.

This inversion came out of an adversarial review of our own first design, which planned a
public scores matrix. The review is public in the research branch; the short version: a
solo-maintained public benchmark would be permanently stale, license-encumbered, and
contaminated — while everything durable about routing fits in the four files above.

**Principles (non-negotiable):**
- No model names in policy. Names appear only in local, expiring data records.
- Fail UP: missing, stale, or ambiguous capability data routes to the most capable model.
  Degraded routing may cost money, never quality.
- Full transparency: every routing decision carries visible rationale; consent is explicit
  and class-level; one switch turns it all off.
- Commodity metadata (pricing, context windows, feature flags) is imported by reference
  from maintained open sources — never rebuilt, never copied from license-gated ones.
