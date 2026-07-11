# Changelog

All notable changes to aura-distill.

## [Unreleased]

### Added
- **Time Index** — the "When" axis. Distill's SPINE indexes knowledge by *domain*; humans also ask by *time* ("that thing from yesterday", "a few weeks ago", "when we did the launch"), which previously forced a slow raw-transcript grep (measured ~70s; now ~2s). Three pieces: (1) `bin/distill-recent` (`.sh` + `.ps1`, identical output — line-ending-normalized on PS 5.1) — a derived view over Claude Code's own `history.jsonl` (no new write path, covers sessions never distilled) that groups sessions into buckets matching human temporal memory: day-precision for today/yesterday, week-precision to ~3 weeks, month-precision to ~6 months, calendar months beyond — boundaries follow the temporal-memory literature (telescoping, Weber–Fechner compression, the 5+2 weekday cycle; see `research/2026-07-11-time-index/mental-timelines.md`). (2) `TIMELINE.md`, maintained by `/distill` (Step 3d): landmark-anchored events ("the payments launch") that consolidate into period lines as they age — landmark names are never dropped; `history.jsonl` rotates after ~5–6 weeks, so this layer carries the months-and-beyond range. (3) A routing block in `rules/distill.md`: landmarks first, recency view second, transcript grep last — plus a fuzzy-phrase table ("a few weeks ago" ≈ 2–6 wk, telescoping-corrected).
- **Full user control** for Time Index (same contract as Token Saver — which means **default ON**, including on updates, announced once): `--time-index` / `--no-time-index` / `--remove-time-index` (install.sh) and `$env:DISTILL_TIME_INDEX` = `on`/`off`/`remove` (install.ps1). Choice persists via `distill/.time-index`. The routing block costs ~15 always-on lines; disabling strips it from `rules/distill.md` — off means zero always-on token cost. `TIMELINE.md` is user knowledge and is never deleted by the installer. Tests: `tests/timeline/run-parity-test.sh` (21 assertions incl. bash↔PowerShell parity and hostile-input handling, verified on pwsh and Windows PowerShell 5.1).
- **Capabilities durable layers** (`capabilities/`): the rot-resistant foundation of model routing — demand TAXONOMY (8 dimensions), name-free routing POLICY (fail-up axiom, margin rule, class-level consent, visible rationale, sacred boundaries), JOIN-SPEC (commodity metadata imported by reference from models.dev/LiteLLM/OpenRouter with a license allowlist; scores never copied from gated sources), and MEASUREMENT METHODOLOGY (private probes via probe-generation recipes — public probe banks self-erase into training data; blind rubric-gated judging; discriminativeness gate; n floors). Deliberately contains NO per-model scores: those are generated locally per installation. Design survived a clean-context adversarial review that killed the original public-scores plan (research branch has the full verdict).
- **Economics ledger**: `/distill` now records its own cost — after each run, one JSONL line is appended to `{DISTILL_DIR}/data/economics.jsonl` (fields including timestamp, distillation tokens when available, tokens written, SPINE size, tier-file KB size, signal and file counts). Local diagnostic data, not part of the synced knowledge set. The distillation report gains an Economics line, and compaction now weighs recurring-cost tokens (SPINE, always-on) heavier than pay-per-read tier files — with an explicit integrity floor: [NON-NEGOTIABLE]/[DIRECTIVE]/safety entries are never compressed for token savings.
- **Token Saver** — two preset subagents installed to the profile's `agents/` directory (`~/.claude/agents/` by default; install.sh honors `--profile`): `scribe` (text-only jobs: judge/summarize/classify/extract/draft — no tools, boots ~2k tokens vs ~19–27k default, measured 14x lighter) and `scout` (read-only exploration: Glob/Grep/Read — ~3.5x lighter, cannot modify anything). Backed by the July 2026 token-economics research (tool schemas ≈22k of a default spawn's ~27k starting context).
- **Full user control** for Token Saver: `--token-saver` / `--no-token-saver` / `--remove-token-saver` flags (install.sh) and `$env:DISTILL_TOKEN_SAVER` = `on`/`off`/`remove` (install.ps1). Choice persists across updates via `distill/.token-saver`. Installer never overwrites agent files it didn't create.
- **Landing page** `docs/token-saving.html` — the token-saving research line explained (inverted pyramid, SVG diagrams, measured numbers): what shipped, what's in research (learned spawn profiles), what became a trade-off knob instead of shipping (diet SPINE), what was corrected (naive friction accounting). Announced by the installer on update.
- **Research pages**: `docs/research/token-economics.html` (40 days of real usage mined: ~85% of cost is context movement; distill overhead 5–6% of spend) and `docs/research/model-routing.html` (task-shape routing trials; orchestrators route near-optimally unaided).

### Fixed
- **Installer data loss**: updating overwrote `rules/distill.md` wholesale, wiping the user's synced "Always-On User Preferences" section back to the empty template (caught live-testing the v1.1.7 update). Both installers now preserve the section across updates (like SPINE) — only when it holds real content, not the template — and leave the existing file untouched if the download fails.

### Privacy
- Token Saver collects nothing — local files only. Standing policy documented on the landing page: any future telemetry must be opt-in, aggregate-only, with a published schema.

## [0.7.0] - 2026-05-15 (unreleased)

### Added
- **Knowledge markers**: `[CONTEXT]`, `[UPDATED]`, `[PROVISIONAL]`, `[IMPORTANT]`, `[NON-NEGOTIABLE]` — structured tags that trigger specific behaviors during retrieval.
- **Contradiction detection** in rules/distill.md — when stored knowledge conflicts with user's current request, surface it (one sentence, then help).
- **Communication style directive** — rule explicitly says to match user's tone (emoji, brevity, register).
- **A/B test framework** (`tests/scenarios/`) — compare Claude responses with/without distill knowledge.
- **Sofia Chen persona** — 8 scenarios testing cognitive biases (confirmation bias, contradictions, outdated procedures, double standards, timeline optimism, reasonable-but-wrong, rushing).

### Changed
- `rules/distill.md` expanded from 18 lines to ~30 — now includes marker semantics, contradiction handling, and style directive.
- `distill-process.md` Step 1c added — teaches the sub-agent HOW to encode markers.

## [0.6.0] - 2026-05-15

### Added
- **`rules/distill.md`** — native retrieval via Claude Code's rules/ directory. Replaces MCP server entirely.
- **Animated terminal demo** on landing page (GSAP) — simulates full Claude Code session with /distill.
- **Interactive shell** in terminal — fake commands, claude easter egg (kernel panic).
- **`test-sandbox.sh`** — integration tests using a second Claude Code instance.

### Removed
- **MCP server** (Node.js, TypeScript, SQLite) — the entire server directory. Zero dependencies now.
- **Node.js requirement** — install.sh no longer needs npm/node.

### Changed
- Install script simplified: downloads core files + rules/distill.md. That's it.
- Landing page rewritten: demo-first, "principles not facts" framing, neuroscience-inspired architecture section.
- README reframed: "not what it remembers — how it learns."

## [0.5.0] - 2026-05-08

### Added
- MCP server with SQLite for observability
- Memory pressure scoring
- Frustration escalation (repeated corrections = priority bump)
- Anti-sycophancy checks in distillation process
- Version checking and auto-update mechanism
- Memory migration from Claude's built-in auto-memory

### Changed
- Sub-agent architecture (distillation runs in isolated context)
- Tier system formalized (Spine → Active → Archive)

## [0.4.0] - 2026-04-30

### Added
- Initial distill command and process
- SPINE.md knowledge index
- Tiered knowledge storage
- Landing page (GitHub Pages)
- Install script (curl | bash)
