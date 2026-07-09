# Routing roadmap v2 — post-steelman (2026-07-09)

Steelman: clean-context adversarial review with full market evidence. Verdict summary:
1 FATAL, 8 MAJOR. Full findings in agent transcript; integrated redesign below.
v1 roadmap (routing-productization-roadmap.md) is SUPERSEDED by this file for the stages
it contradicts; kept for provenance.

## The fatal finding (F-1): public probes are self-erasing
Discriminative probes (D4/D5 — the ONLY cells that separate tiers per E1) published on
GitHub enter the next model generation's training data BY CONSTRUCTION. A public battery
converges to measuring nothing, faster than a solo maintainer can rotate hand-built hard
probes. → Probe bank must be PRIVATE, maintainer-held; leaked probe = burned probe.

## Key majors (condensed)
- F-2: 4/7 demand columns + all cost columns are commodity (models.dev MIT, LiteLLM,
  OpenRouter) → matrix must be a JOIN, not a store; measure in-house ONLY the gap demands
  (D4 adversarial inference, D5 verification discipline, verbosity-per-demand,
  delegation-failure decomposition). ~70% less maintenance surface.
- F-3: a stale public scores artifact is WORSE than nothing (fail-up protects runtime, not
  reputation; forks/caches freeze stale numbers). Solo maintainer + 60d expiry +
  sub-quarterly releases = permanently-yellow benchmark.
- F-4: E1 is n=1 with contested/invalid cells — publishing it as baseline ships the artifact
  BEFORE its own discriminativeness gate. No published cell below n=5 + V1 pass.
- F-5: license trap — NEVER copy scores from gated aggregators (AA redistribution ban);
  metadata allowlist: models.dev/LiteLLM/OpenRouter; link-don't-store for scores.
- F-6: community score aggregation unsound at our cohort size (poisoning + harness
  heterogeneity) → defer indefinitely; if ever: harness fingerprints, separate tier,
  never overrides maintainer cells.
- F-7: per-event "suggest and ask" = negative EV + consent fatigue → class-level consent
  ONCE; route silently within the E1-proven zero-violation safe class under fail-up;
  SESSION-END summary with visible rationale; independent sampled correctness check (not
  accepted-rate) as the quality signal.
- F-8: local battery skill = prompt-injection surface + unbounded user-account spend →
  endpoint output is DATA never instructions; fixed local judge; hard cost cap + dry-run
  estimate; supervised only.
- F-9: public capability matrix is off-mission for a memory system; the moat is
  memory-learned LOCAL adaptation + visible rationale (the explainable-routing gap),
  not published data. Full-staffed commercial teams decline to publish this, for reasons
  that bite a solo maintainer 10x harder.

## Revised stages (steelman-integrated)
- S1 (public, now-able): durable layers in the repo — demand TAXONOMY + routing POLICY
  (name-free, number-free, rots in years) + JOIN spec referencing free metadata feeds +
  methodology doc. This is what "lives in the GitHub repo" safely.
- S2 (local-first, promoted from old Stage 4): the capabilities-matrix SKILL — runs the
  (private) battery against the user's own lineup incl. custom models, writes
  {DISTILL_DIR}/data/capabilities-local.json. Injection-hardened, cost-capped, supervised.
  The local file is the cache/baseline distill actually consumes.
- S3 (opt-in beta): class-level consent once; silent routing inside the safe class;
  fail-up; session-end summary w/ rationale; sampled correctness audits.
- S4 (public scores — OPTIONAL, MAYBE NEVER): only after V1 discriminativeness gate + n>=5
  per cell + maintainer-run private probes; aggregates only, never probe text. Explicitly
  allowed to conclude "never."
- Community contributions: DEFERRED indefinitely (F-6); Tier-1 structured bug reports
  (#31) remain the contribution channel.

## OPEN DECISION FOR IVAN (contradicts his 2026-07-09 ask — flagged per protocol)
Ivan asked for a capabilities matrix "living in my GitHub repo as baseline/cache." The
steelman says publishing per-model SCORES there is a liability (F-1/F-3/F-4/F-5); what CAN
live there safely is taxonomy+policy+join-spec+methodology, with scores generated LOCALLY
per install by the skill. Options:
A) Accept inversion (recommended): repo = durable layers + skill; scores local-only.
B) Compromise: repo also carries maintainer-run aggregate scores AFTER V1 gate + n>=5,
   private probes, clearly versioned — accepts residual staleness risk consciously.
C) Original plan regardless: publish thin-n scores now with disclosures — steelman says
   this damages credibility; not recommended.
