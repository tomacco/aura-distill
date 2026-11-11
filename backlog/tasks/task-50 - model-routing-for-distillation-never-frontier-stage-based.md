---
id: task-50
title: "Model routing for distillation: never frontier; stage-based cheap/mid tiers"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [enhancement]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/50
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/50

## Directive

Distillation must **never run on frontier-tier models** (Fable-class) — too expensive for a background/batch job. This issue makes model selection for distillation deliberate instead of inherited from the invoking session.

## Proposal — route stages by capability demand, never by model name

The distillation pipeline is not one job; its stages have different capability floors:

| Stage | Demand | Tier |
|---|---|---|
| Signal extraction / transcript chunk mapping | mechanical transform + extraction | cheap (Haiku-class) |
| Synthesis, SPINE merge, contradiction resolution, confidence updates | judgment over structured inputs | mid (Sonnet-class) |
| Any stage | — | frontier: **never** |

Resolution happens at runtime through the capabilities layer (`capabilities/` — TAXONOMY/POLICY/JOIN-SPEC shipped in v1.1.10; local calibration via the capabilities skill, PR #38), so the policy contains nothing perishable. Per the routing directive: full transparency ALWAYS + explicit user approval ALWAYS; per-user override knob for each stage.

## Evidence (internal + external, 2026)

- Internal (E1, provisional): Haiku-class untouched on mechanical transforms AND extraction; Sonnet-class floor for comprehension-heavy judgment; watch the **verbosity tax** — cheap models emit 3–7x more output tokens for identical answers, so net the savings before claiming them.
- External: complexity-based routing typically cuts bills 50–80% with minimal quality loss; 70–80% of production queries are simple enough for cheap models; budget-tier quality ranking (GPT-5.4 Mini > Haiku 4.5 > Gemini Flash > DeepSeek V4) is within 3–7pp. Staying in-family (Claude) keeps cache economics (Haiku + cache reads is competitive with ultra-cheap third parties) and avoids a new provider dependency — third-party models remain available through the private local capabilities matrix if a user configures them.
- Sources: [IntuitionLabs low-cost LLM comparison](https://intuitionlabs.ai/articles/low-cost-llm-comparison), [BenchLM budget LLMs 2026](https://benchlm.ai/blog/posts/best-budget-llms-2026), [TokenMix budget model comparison](https://tokenmix.ai/blog/gpt-5-4-mini-vs-claude-haiku), [Grizzly Peak per-task pricing](https://www.grizzlypeaksoftware.com/library/comparing-llm-provider-pricing-and-performance-19oanku0)

## Acceptance criteria

- [ ] Distill pipeline stages declare demand classes (D1–D8 taxonomy); no model names in policy
- [ ] Headless invocations pass an explicit model per stage (`claude -p --model ...` or spawn-profile equivalent)
- [ ] Frontier exclusion enforced structurally (a check, not a comment) — routing gaps are HABIT-shaped, so encode the default, don't rely on per-run judgment
- [ ] Verbosity tax netted in any savings claim
- [ ] Transparency: each distill report states which model ran which stage

Part of the auto-distillation epic. Feeds: auto-distiller.

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
