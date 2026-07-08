# Token Economics Research — Overnight Plan (2026-07-08)

Session: `d5ce833d-a019-4cc3-b789-acd99070f034` (interactive, C:\Users\Ivan)
Branch: `research/2026-07-08-token-economics` · Worktree: `C:\Users\Ivan\repos\aura-distill-token-econ`

RULES FOR THIS FILE (gates the resume watchdog — must reflect reality at every moment):
- A box is checked ONLY after the artifact it names exists on disk / is committed. Never pre-check.
- On resume: read this file top to bottom, continue at the first unchecked box.
- Checkpoint: commit to the research branch after every completed box.

## Mission
Quantify aura-distill's token economics (overhead vs savings) from real local Claude Code
transcripts; research + test novel cost-reduction approaches incl. model routing; publish
research pages in the established docs/research format. Protect personal data — publish
aggregates and scrubbed examples only.

## Plan

- [x] 1. DATA: transcript miner script written + run; aggregate dataset committed
      (per-session, per-model, cache, sidechain, monthly; NO raw content committed)
- [x] 2. DATA: distill overhead measured (session-start floor, /distill invocation cost,
      knowledge-file read volume) — committed as analysis doc
- [ ] 3. DATA: distill savings evidence (friction-recurrence before/after encoding;
      re-derivation counterfactuals, overheads netted out) — committed
- [ ] 4. DATA: model-mix + routing analysis (tokens by model, routable fraction, $ deltas
      at API pricing; pricing verified via claude-api skill) — committed
- [ ] 5. RESEARCH: web research on novel approaches (routing/cascades, memory economics,
      caching, cost-aware distillation) — synthesis doc committed
- [ ] 6. EXPERIMENTS: designs written; clean-context ADVERSARIAL REVIEW of designs passed
      (craft/self-benchmark-integrity.md) — review verdict committed
- [ ] 7. EXPERIMENTS: approved experiments run (token-conscious; fail fast on limit
      strings); results committed
- [ ] 8. PAGES: docs/research/token-economics.html (+ routing page if warranted) in house
      style; index.html updated; committed
- [ ] 9. SOURCE DOCS: research/2026-07-08-token-economics/*.md (methodology, data notes,
      SESSION-LOG) committed
- [ ] 10. SHIP: research branch pushed to origin (NEVER main); final SESSION-LOG entry;
      watchdog schtask DELETED (hygiene)

## Notes / state (append-only)
- 2026-07-09 00:05 — Plan created. Worktree + branch created. Pricing subagent running.
- 2026-07-09 ~00:50 — Dataset + findings F1-F9 committed. Watchdog live+test-fired. Web briefs 3/4 in. Designs pre-registered; adversarial review running. NEXT: review verdict -> run E1/E3 -> routing synthesis -> pages.
