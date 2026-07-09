# Demand taxonomy v1

A task (or subagent spawn) declares WHAT IT NEEDS — never which model it wants. Version:
taxonomy changes are versioned and reviewed yearly; scores are only comparable within one
taxonomy version.

| ID | Demand | What it means | Typical task shapes |
|---|---|---|---|
| D1 | Mechanical fidelity | exact rule-following transforms; nothing inferred | format conversion, schema mapping, templated edits |
| D2 | Structured extraction | pull exact facts from noisy material | log mining, table extraction, fact lookup in provided text |
| D3 | Code comprehension | understand unfamiliar code incl. control-flow side effects | code Q&A, review-for-understanding, bug localization |
| D4 | Adversarial / latent inference | find what is NOT stated; flaws that must be inferred | design review, benchmark critique, red-teaming a plan |
| D5 | Verification discipline | checking work: test-firing, validating outputs, catching own errors | anything where "it ran" ≠ "it worked" |
| D6 | Sustained constraints | invariants held across long output / multi-step edits | multi-file refactors, style-constrained long writing |
| D7 | Long-context synthesis | conclusions requiring genuinely distant parts of a large context | cross-document synthesis, large-codebase questions |
| D8 | Tool-use orchestration | choosing/sequencing tools; recovering from tool errors | agentic execution, multi-step operations |

Notes:
- Demands are NOT difficulty levels. A task declares a SET (e.g. log triage = D2+D5).
- Measurement status differs by demand: D1/D2 saturate early on current model generations
  (they stop discriminating between tiers); D4/D5 are where tiers actually separate, and —
  per our market sweep — no public leaderboard scores them. See METHODOLOGY.md.
- Verbosity is not a demand; it is a COST property measured per model per demand (the same
  answer can cost 3–7x more tokens on one model than another).
- The tool-capability axis (which TOOLS a spawn carries: text-only / read-only / full) is
  orthogonal to demands and handled by spawn tiers (see Token Saver presets).
