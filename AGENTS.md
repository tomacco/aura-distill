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

`worktree remove` refuses if the directory has uncommitted changes, and `worktree add -b` refuses if
the branch exists. Both are correct — they are telling you something. Commit or stash, or pick another
name. **Do not reach for `--force`**: on `worktree remove` it discards those changes permanently.

Leave the primary checkout parked on `main`. A separate `git clone` works too; a worktree is cheaper
because it shares the object store.

**Why this is a rule and not a preference.** A checkout changes `HEAD` for *every* process in that
working tree, and nothing tells the others. The agent that gets moved sees a normal `git status` and
keeps committing — onto whatever branch it was moved to. On 2026-09-22 this put nine commits on local
`main` that their author believed were on a feature branch, and the other agent pushed `main` twice
during the same window from a different clone. Had it pushed from the shared tree, those nine
unreviewed commits would have entered `main` inside an unrelated push, bypassing `REVIEW-PROTOCOL.md`
with nothing looking wrong to anyone. The failure is silent by construction, so care does not prevent
it — only isolation does. (See #102; reviewers already work this way, `REVIEW-PROTOCOL.md`.)

**Never let message, issue or PR text reach a shell as an argument.** Pass it by file or stdin —
`gh pr comment N --body-file body.md`, `gh issue create --body-file body.md`, or a quoted heredoc —
never `--body "$text"` where `$text` came from somewhere else. The same incident included an agent
quoting `git checkout` in backticks inside a chat message, passing the text as a shell argument, and
having the backticks command-substituted: it executed a checkout in the shared tree, from a message
warning against exactly that.

### If it already happened

**Nothing is lost yet.** Commits made on the wrong branch are still reachable; the incident itself
destroys nothing. Every destructive step below is one *you* would be running, so the rule is: capture
first under a new name, restore second, and never force-update a ref you have not read.

**1. Confirm it, and find your commits.** The immediate tell is the branch name; the reflog says when
and from where.

```bash
git branch --show-current                 # not the branch you thought you were on
git reflog --date=short | grep 'checkout: moving' | head
git fetch origin                          # before any comparison against origin/*
git log --oneline origin/main..HEAD       # your stranded commits, wherever HEAD now points
```

**2. Capture them under a new name.** Never `git branch -f`: the branch you would overwrite may hold
your own pre-yank work, and force-updating it leaves those commits unreachable from any ref and
subject to `git gc`.

```bash
git branch rescue/<topic>                 # no -f; fails loudly if the name exists, which is correct
```

**3. Read what you captured before using it.**

```bash
git log --oneline origin/main..rescue/<topic>
```

If you were moved onto another agent's branch, this list contains **their** commits as well as yours.
Do not carry them into your PR — that recreates the review bypass in a new shape. Tell them, and keep
only your own.

**4. Restore the shared tree.** `git reset --hard` moves *the branch that is currently checked out*,
which may be theirs — so check out `main` explicitly first, and verify against `HEAD` rather than a
branch you assume the reset touched.

```bash
git status --porcelain                    # MUST be empty; it is someone else's tree too
git checkout main
git reset --hard origin/main
git rev-parse HEAD origin/main            # MUST match
```

**5. Continue in isolation.**

```bash
git worktree add ../aura-distill-<topic> rescue/<topic>
cd ../aura-distill-<topic> && git rebase origin/main
```

Tell the other agent before step 4: a `reset --hard` over uncommitted work is the one thing here that
is not recoverable, which is why the `status` check precedes it. Re-check it immediately before
running, not minutes earlier — the other agent is still working.

This runbook is executed against synthetic reproductions rather than reasoned about, because an
earlier draft of it was **more destructive than the incident it recovered from**: it used `branch -f`
(orphaning pre-yank commits), reset whichever branch happened to be checked out (wiping the other
agent's work), and verified the result by checking a branch the reset had not touched — so the check
passed while the damage was done. All three were found by running the steps, none by reading them.

## Branch conventions

- `main` — stable, released (quality gate: REVIEW-PROTOCOL.md)
- `feature/*` — in-progress work
- `research/*` — experiments and published research (never merged to main directly)
