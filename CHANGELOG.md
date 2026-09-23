# Changelog

All notable changes to aura-distill.

## [Unreleased]

### Added
- **Release channels and upgrade protection** (#79, [ADR 0002](docs/adr/0002-release-channels.md)): an opt-in **beta channel** (`install.sh --channel beta`, `$env:DISTILL_CHANNEL='beta'`) that installs the one prerelease tag named by `channels/manifest.json` on `beta/1.2`, remembered in `~/.aura-distill/.channel`; `--channel stable` returns. Updates are now done by a script, `bin/distill-update.sh`, that the `/distill` dispatcher runs instead of composing `curl` commands: it follows the recorded channel, downloads everything to a temp dir and validates it before replacing anything, resolves the store path, and never installs another major version or a software-edition payload. A future software edition is only announced (once, as text, with its requirements and guide); it is never fetched. Both installers now validate the whole payload before writing and require typed consent (`adopt <version>`, interactive terminal only) for a different major. CI guard `tests/updater-compat/check-endpoints.sh` keeps the legacy `main` endpoints files-only, and `check-major-release.sh` checks a major's manifest entry and guide before it may be announced. Sandbox coverage in `tests/updater-compat/run.sh` sections (e) to (i) and `tests/test-codex.ps1`.
- **Clean reviewer runner** (`tests/review/run-clean-review.sh`): runs the independent PR review headless in a separate reviewer profile with no memory, no MCP servers and no tools that post, push or merge (REVIEW-PROTOCOL.md rule 9). Covered by `tests/review/test-run-clean-review.sh`, which uses a stub instead of a live model.
- Files-only memory redesign discovery (#75): design doc `docs/design-files-only-memory.md`, synthetic before/after store and deterministic invariant checks under `tests/files-only/`, CI job on Linux and macOS. No runtime behaviour change.
- **Research: local decision models for retrieval and distillation** (#100): measured whether a small local judgment model (Laya, 421M) can replace the frontier model's knowledge-index read. It cannot — a zero-model BM25 rank-fusion router beats it at routing (0.87 vs 0.67 top-1) in 4.85 ms and 29 MB, and injecting that router's top-3 into a real headless cell measured −70% cache-creation tokens, −64% cost and one fewer round trip at 3/3 correct. The model does win at judging a single candidate (0.83 specificity), the one thing no zero-model signal can do. Also measured: the index-read *turn* costs 21,247 tokens (5.9x this project's last published 3.6k for the same index; the file alone is an estimated 3.8-5.2x), driven by verbosity per entry rather than entry count; and ~93% of transcript volume is tool traffic, which kills a user-turn distillation pre-filter on arithmetic. Write-up in `research/2026-09-22-local-routing/`, published page at `docs/research/local-decision-models.html`. No behaviour changes ship from this work.
- **Antigravity (agy) connector** (#67): native Google Antigravity client for the shared `~/.aura-distill/` store, packaged as a plugin laid out per Antigravity's discovery contract (`plugins/aura-distill/`: marker `plugin.json`, `skills/distill/SKILL.md` — the distill workflow with mandatory isolated synthesis, migration gate, and fail-safe `.status` handling — and `rules/AGENTS.md`, a thin pointer deferring INBOX/memory-pressure behavior to the canonical `distill-monitor.md` so clients cannot drift), plus `bin/distill-recent-agy.sh`/`.ps1` — output-identical Time Index twins over Antigravity brain transcripts (`~/.gemini/antigravity-cli/brain/`), hardened against hostile records (malformed JSON, missing/garbage/out-of-range timestamps) with parity enforced by `tests/antigravity/run-parity-test.sh` (24 checks, verified PowerShell 5.1 == pwsh 7 == bash). Installer wiring is a follow-up on #67.
- **INBOX** (#47): `{DISTILL_DIR}/inbox/` — a queue of items for the next distillation. When the user explicitly asks to remember/save something, the session writes it immediately as one small markdown file (front-matter `origin`/`created`, collision-proof filenames for concurrent sessions) and confirms with the path. The next `/distill` consumes items through the full pipeline (classification, tracing, anti-sycophancy — pre-extracted signals, not pre-approved knowledge) and deletes them only after encoding is verified on disk. Replaces the old "note it mentally / offer /distill" behavior for explicit saves — nothing queued is lost to a session that never distills.
- **Distillation ledger** (#46): every `/distill` run now appends one line to `{DISTILL_DIR}/data/distill-ledger.jsonl` recording which conversation was distilled — identity resolved by an in-transcript beacon nonce emitted before spawning — plus when, from how many signals, and by which distiller version. Foundation for the auto-distiller (#51): automation must never process the same conversation twice. Append-only, null-over-invented-values, local diagnostic data — never synced or transmitted. Installers now create `{DISTILL_DIR}/data/`.
- **Capabilities durable layers** (`capabilities/`): the rot-resistant foundation of model routing — demand TAXONOMY (8 dimensions), name-free routing POLICY (fail-up axiom, margin rule, class-level consent, visible rationale, sacred boundaries), JOIN-SPEC (commodity metadata imported by reference from models.dev/LiteLLM/OpenRouter with a license allowlist; scores never copied from gated sources), and MEASUREMENT METHODOLOGY (private probes via probe-generation recipes — public probe banks self-erase into training data; blind rubric-gated judging; discriminativeness gate; n floors). Deliberately contains NO per-model scores: those are generated locally per installation. Design survived a clean-context adversarial review that killed the original public-scores plan (research branch has the full verdict).
- **Economics ledger**: `/distill` now records its own cost — after each run, one JSONL line is appended to `{DISTILL_DIR}/data/economics.jsonl` (fields including timestamp, distillation tokens when available, tokens written, SPINE size, tier-file KB size, signal and file counts). Local diagnostic data, not part of the synced knowledge set. The distillation report gains an Economics line, and compaction now weighs recurring-cost tokens (SPINE, always-on) heavier than pay-per-read tier files — with an explicit integrity floor: [NON-NEGOTIABLE]/[DIRECTIVE]/safety entries are never compressed for token savings.
- **Token Saver** — two preset subagents installed to the profile's `agents/` directory (`~/.claude/agents/` by default; install.sh honors `--profile`): `scribe` (text-only jobs: judge/summarize/classify/extract/draft — no tools, boots ~2k tokens vs ~19–27k default, measured 14x lighter) and `scout` (read-only exploration: Glob/Grep/Read — ~3.5x lighter, cannot modify anything). Backed by the July 2026 token-economics research (tool schemas ≈22k of a default spawn's ~27k starting context).
- **Full user control** for Token Saver: `--token-saver` / `--no-token-saver` / `--remove-token-saver` flags (install.sh) and `$env:DISTILL_TOKEN_SAVER` = `on`/`off`/`remove` (install.ps1). Choice persists across updates via `distill/.token-saver`. Installer never overwrites agent files it didn't create.
- **Landing page** `docs/token-saving.html` — the token-saving research line explained (inverted pyramid, SVG diagrams, measured numbers): what shipped, what's in research (learned spawn profiles), what became a trade-off knob instead of shipping (diet SPINE), what was corrected (naive friction accounting). Announced by the installer on update.
- **Research page** `docs/research/local-models.html` (#96): *Can a Local Model Do the Distilling?* — a **live** study, updated as runs land rather than published finished. Experiment 1 measures the signal-harvest stage on a local open-weights model (Qwen3.8-27B, MLX 8-bit, 48 GB Mac) against Opus 5 / Sonnet 5 / Haiku 4.5 on byte-identical input, blind-judged and normalised to Opus's own self-agreement ceiling (0.918 — two runs of the same frontier model disagree about one claim in twelve). Headline: the local model reached 81% of that ceiling at $0, beating both hosted cheap tiers on faithfulness, while Haiku grounded only 55% of its claims and invented user approval that never occurred. Carries a run log (including the independent review that corrected two already-published figures) and an explicit provisional marker: n=1, and the judge shares a family with the reference. Experiment 2 (16 GB candidates) in progress.
- **Research pages**: `docs/research/token-economics.html` (40 days of real usage mined: ~85% of cost is context movement; distill overhead 5–6% of spend) and `docs/research/model-routing.html` (task-shape routing trials; orchestrators route near-optimally unaided).

### Fixed
- **Installers could leave an empty or partial install on a failed download** (#79): core files were piped straight from `curl` into place, so a network error wrote empty files. Both installers now stage and validate the whole payload first and change nothing on failure. `tests/test-install.sh` and `test-sandbox.sh` no longer inherit `AURA_DISTILL_HOME`/`CODEX_HOME` from the calling shell, and `test-sandbox.sh` checks the shared store (`~/.aura-distill`) instead of the pre-1.1.10 path.
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
