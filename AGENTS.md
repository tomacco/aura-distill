# aura-distill Development Guide

This is the canonical guide for anyone — human or AI agent, whatever the tool — working in this repo. `CLAUDE.md` is a pointer here; do not duplicate content there.

## What this is

A first-principles memory system shared by Claude Code, Codex, and Google Antigravity (agy). Users install it via `install.sh` or `install.ps1`, which places knowledge in `~/.aura-distill/` and adds client adapters. Claude can trigger it with `/distill`; Codex users ask it to distill; Antigravity loads it as a skill (installer wiring pending — see #67).

## Architecture

- `distill.md` — Dispatcher (runs in main context, harvests signals, spawns sub-agent)
- `distill-process.md` — Sub-agent instructions (the full distillation pipeline)
- `distill-monitor.md` — Session-start monitor (minimal, loaded via the client integration)
- `plugins/aura-distill/` — Antigravity (agy) plugin, laid out per Antigravity's discovery contract: `plugin.json` (marker), `skills/distill/SKILL.md` (the distill workflow), `rules/AGENTS.md` (thin pointer to the canonical `distill-monitor.md` + Antigravity-specific Time Index)
- `bin/distill-recent-agy.sh` / `.ps1` — Antigravity Time Index over brain transcripts (output-identical twins; parity enforced by `tests/antigravity/run-parity-test.sh`)
- `knowledge-architecture.md` — Tier system design doc
- `install.sh` / `install.ps1` — User-facing installers
- `tests/` — A/B test scenarios, cognitive bias tests, persona-based methodology tests
- `docs/` — GitHub Pages site (landing, research)
- `dashboard/` — Analytics dashboard

## CRITICAL: Never touch real user data

**NEVER read, write, or test against real Claude/Codex profile directories or `~/.aura-distill` on this machine.**

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
- Run Antigravity Time Index parity + hostile-input tests: `./tests/antigravity/run-parity-test.sh` (and the connector runners `run-antigravity-connector-tests.sh` / `.ps1`)
- Run deterministic Claude/Codex installer tests: `pwsh tests/test-codex.ps1`
- Run a real isolated Codex retrieval test: `pwsh tests/test-codex.ps1 -LiveRetrieval`

## Issues & PRs

- **Every PR must reference a GitHub issue** (`Closes #N` for full resolution, `Part of #N` for partial work). No orphan PRs — if no issue exists for the work, create one first.
- Every PR must be reviewed by an independent agent before merging. See `REVIEW-PROTOCOL.md`.
- The authoring agent spawns a reviewer in a worktree with zero shared context. The reviewer gets only product context — never the author's reasoning, known limitations, or focus suggestions. This is structural, not optional: shared context makes self-review biased by definition.

## Working concurrently in this repo

Several agents may run at once, and more than one may be pointed at this clone.

**Never `git checkout` in a clone you do not exclusively own. Use `git worktree add`.**

```bash
git worktree add ../aura-distill-<topic> -b <feature|research>/<topic>   # your own dir, your own HEAD
cd ../aura-distill-<topic>                                    # work here
git worktree remove ../aura-distill-<topic>                   # when done
```

Leave the primary checkout parked on `main`. A separate clone works too; a worktree shares the object
store. Both `worktree` commands above refuse rather than clobber — on a dirty directory or an existing
branch. **Never answer that with `--force`**; `worktree remove --force` discards uncommitted work.

**Why this is a rule.** A checkout changes `HEAD` for *every* process in that tree, and nothing tells
the others. The moved agent sees a normal `git status` and keeps committing onto whatever branch it
landed on. On 2026-09-22 that put nine commits on local `main` whose author believed they were on a
feature branch, while the other agent pushed `main` twice from a different clone — from the shared
tree, that push carries nine unreviewed commits into `main`, bypassing `REVIEW-PROTOCOL.md` with
nothing looking wrong. Silent by construction, so care does not prevent it; only isolation does.
(#102; reviewers already work this way — `REVIEW-PROTOCOL.md`.)

**Never let message, issue or PR text reach a shell as an argument.** Use `--body-file` or a
*quoted* heredoc; never `--body "$text"` when `$text` came from elsewhere. In the same incident an
agent quoted `git checkout` in backticks inside a chat message, passed it as a shell argument, and the
substitution executed a checkout in the shared tree — from a message warning against exactly that.

### If it already happened

**Nothing is lost yet** — commits on the wrong branch stay reachable. Every destructive step is one
*you* would run. Capture first; never force-update a ref you have not read.

**Capture is safe and solo; restoring the shared tree is neither** — `git checkout main` there yanks
the other agent exactly as you were yanked.

```bash
git fetch origin
git branch --show-current                 # not the branch you expected (empty = detached HEAD)
git reflog --date=short | grep -E 'checkout: moving|commit:' | head -20
```

Read the reflog, not `HEAD`: after a second move your commits sit on a branch you are no longer on,
and `origin/main..HEAD` then reports a confident all-clear. Reflog `commit:` lines survive any number
of moves.

```bash
git branch rescue/<topic> <sha of your newest commit>   # plain branch, never -f; a name clash should fail
git log --format='%h %an %s' origin/main..rescue/<topic>
```

Read that range first. If you were moved onto another agent's branch it holds **their** commits —
carrying those into your PR recreates the review bypass in a new shape. Yours are likewise still on
their branch, where they have no symptom and nobody will look: tell them.

**Then stop and coordinate.** Restoring `main` in a tree someone else is working in is a two-agent
operation — `docs/runbooks/shared-clone-recovery.md`. You are not blocked meanwhile: work from
`rescue/<topic>` in your own worktree, which is where you wanted to be.

```bash
git worktree add ../aura-distill-<topic> rescue/<topic>
```

**Any edit to this procedure must be re-run against throwaway repositories before it lands.** Three
successive drafts were wrong in ways only execution revealed: one orphaned commits, one destroyed an
uninvolved branch while printing a passing check, one reported all-clear after a second move.

## Branch conventions

- `main` — stable, released (quality gate: REVIEW-PROTOCOL.md)
- `feature/*` — in-progress work
- `research/*` — experiments and published research (never merged to main directly)
