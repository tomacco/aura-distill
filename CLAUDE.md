# aura-distill Development Guide

## What this is

A first-principles memory system for Claude Code. Users install it via `install.sh`, which places files into `~/.claude/distill/`. The `/distill` slash command triggers retrospective distillation of conversation signals into tiered knowledge files.

## Architecture

- `distill.md` — Dispatcher (runs in main context, harvests signals, spawns sub-agent)
- `distill-process.md` — Sub-agent instructions (the full distillation pipeline)
- `distill-monitor.md` — Session-start monitor (minimal, loaded via `rules/distill.md`)
- `knowledge-architecture.md` — Tier system design doc
- `install.sh` / `install.ps1` — User-facing installers
- `tests/` — A/B test scenarios, cognitive bias tests, persona-based methodology tests
- `docs/` — GitHub Pages site (landing, research)
- `dashboard/` — Analytics dashboard

## CRITICAL: Never touch real user data

**NEVER read, write, or test against real Claude profile directories on this machine.**

These directories contain the developer's real distilled knowledge. An errant write, backup, or test run against them risks data loss (this has already happened once — see the `_distill_isolation_bak` incident).

When developing or testing:
- Use test personas under `tests/scenarios/methodology/persona-sofia/` and `persona-marcus/`
- Use the sandboxed test harness: `./test-sandbox.sh` (creates a temp dir via `mktemp -d`)
- For ad-hoc testing, create temp directories: `mktemp -d` or use `tests/scenarios/`
- If you need to reference real distill structure for context, **read only** — never write

## Version management

- Current version is in `VERSION` file (semver)
- The auto-bump workflow (`.github/workflows/bump-version.yml`) bumps the patch version
  on every content merge to main and syncs it across `VERSION`, `install.sh`,
  `install.ps1`, `README.md`, `docs/header.svg`, and `docs/index.html`
- After editing the workflow, run `./test-version-bump.sh` — it executes the run block
  verbatim against fixture copies and asserts all six files update
- The Homebrew formula (`homebrew/Formula/aura-distill.rb`) is NOT auto-bumped: it pins
  a tagged release tarball + sha256, so updating it requires cutting a git tag and
  recomputing the hash (manual release step)

## Key conventions

- All distill files use `{DISTILL_DIR}` as a placeholder — `install.sh` resolves it to the actual path via `sed`
- The SPINE (Tier 1) is the auto-loaded index — max 80 lines, pointers only
- Tier 2 files are max 60 lines each, one topic per file
- The `rules/distill.md` always-on section is capped at 15 lines of preferences

## Testing

- `tests/scenarios/methodology/` — A/B tests comparing WITH vs WITHOUT distill knowledge
- `tests/scenarios/cognitive/` — Bias detection tests (anchoring, authority, recency, loss aversion)
- `tests/scenarios/retrieval/` — Knowledge retrieval accuracy tests
- `tests/scenarios/distillation/` — Full-loop distillation tests
- Test personas: Sofia (senior backend engineer) and Marcus (product manager)
- Run persona tests: `./tests/scenarios/methodology/run-persona-test.sh`
- Run integration tests: `./test-sandbox.sh`

## PR reviews

Every PR must be reviewed by an independent agent before merging. See `REVIEW-PROTOCOL.md`.

The authoring agent spawns a reviewer in a worktree with zero shared context. The reviewer gets only product context — never the author's reasoning, known limitations, or focus suggestions. This is structural, not optional: shared context makes self-review biased by definition.

## Branch conventions

- `main` — stable, released (quality gate: REVIEW-PROTOCOL.md)
- `feature/*` — in-progress work
