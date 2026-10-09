# Runbook: restoring a shared clone after a cross-agent checkout

Reached from `AGENTS.md` → *Working concurrently in this repo*. Read that first; it covers the rule
and the **capture** half, which is safe to do alone. This file covers only the **restore** half.

> **This is a two-agent operation.** `git checkout main` in a shared tree moves `HEAD` for every
> process in it — including the other agent, mid-task. Running it unilaterally reproduces the original
> incident with the roles swapped: their next commit lands on `main`, unreviewed, in a tree from which
> `main` gets pushed. **Do not start until the other agent has confirmed it has stopped.**

You do not need this runbook to keep working. Capture put your commits on `rescue/<topic>`; a worktree
gets you back to work. Restoring the shared tree is housekeeping — do it when the other agent is free,
not while you are blocked.

## Preconditions

- [ ] The other agent has **confirmed** it has stopped touching the tree.
- [ ] Your commits are already captured on `rescue/<topic>` and you have read the range.
- [ ] You have told the other agent about any of **their** commits your rescue range swept up, and any
      of **yours** still sitting on their branch.

## Procedure

Every `MUST` below is a stop, not a comment. If one fails, stop and fix that before continuing — the
failure modes here are silent, and the step after a skipped guard is the destructive one.

```bash
git fetch origin                          # origin/main is a local ref and you have not fetched lately

git worktree list                         # is main checked out in another worktree?
```

If `main` is checked out elsewhere, `git checkout main` here fails with exit 128 — and the next
command would then reset *whatever branch you are still on*, which may be another agent's. Either run
the restore in that worktree (`git -C <path> ...`), or remove it first. **Do not continue in this tree.**

```bash
git status --porcelain                    # MUST be empty — re-run it immediately before the reset,
                                          # not minutes earlier; the other agent may still be settling

git checkout main                         # MUST succeed. Exit 128 → STOP, see above.
git branch --show-current                 # MUST print exactly "main"

git reset --hard origin/main
git rev-parse HEAD origin/main            # MUST print two identical hashes
```

`git branch --show-current` between the checkout and the reset is the load-bearing guard. Without it,
a refused checkout leaves you on the other agent's branch, `reset --hard` destroys their work, and
`git rev-parse HEAD origin/main` still prints a matching pair — because after a refused checkout
`HEAD` legitimately equals the ref it is compared against. A verification that passes while the damage
is done is worse than none.

## Afterwards

```bash
git worktree add ../aura-distill-<topic> rescue/<topic>
cd ../aura-distill-<topic> && git rebase origin/main
```

The rebase can conflict — `rescue/<topic>` may contain another agent's commits alongside yours, and
upstream has moved. `git rebase --abort` returns you to a safe state; resolve from there, or drop the
commits that are not yours (they belong on their branch, not in your PR). Delete `rescue/<topic>`
once its commits are on your real branch.

## Verification

This procedure is verified by execution against throwaway repositories, not by reading, because three
successive drafts of it were wrong in ways only running them revealed: one orphaned pre-yank commits
with `branch -f`, one destroyed an uninvolved branch after a refused checkout while printing a passing
verification, and one reported all-clear because it diagnosed from `HEAD` after the tree had moved
twice.

**Any edit to this file must be re-run first** against a fixture covering at least: pre-existing work
on your own branch, being moved onto another agent's branch, a second move afterwards, `main` occupied
by another worktree, and upstream advanced meanwhile. Reasoning about these steps has a measured
failure rate of three out of three.
