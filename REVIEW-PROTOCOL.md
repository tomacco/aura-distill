# PR Review Protocol

## Why this exists

This project is fully LLM-coded. When the same agent writes code and reviews it, the review is structurally biased — the agent knows *why* every decision was made, so every decision looks justified. This isn't a reasoning failure. It's an inevitable property of shared context.

**The fix is perspective, not effort.** A clean agent with zero knowledge of the authoring conversation evaluates code on its merits alone. It doesn't know what was "hard to get working" or what tradeoff was agonized over — so it can't give those decisions a pass.

## Protocol

Every PR must be reviewed by a **separate agent in a worktree** before merging. The reviewing agent:

- Has **no access** to the conversation that produced the changes
- Gets **only** the product context (what the project does, who it's for)
- Must form its own understanding of the codebase by reading it
- Reports issues it finds — not issues it was told to look for

### How to invoke

When a PR is ready for review, the authoring agent spawns:

```
Agent({
  description: "Independent PR review",
  isolation: "worktree",
  prompt: <the review prompt below, filled in with the PR number>
})
```

The authoring agent **must not** include:
- Its own assessment of the changes
- Reasoning behind decisions ("we did X because Y")
- Known limitations or caveats ("the lock file approach is a workaround")
- Suggestions for what the reviewer should focus on

The authoring agent **may** include:
- The PR number
- The branch name
- A one-line summary of the feature area (e.g., "concurrency changes to the distillation pipeline")

Anything beyond that contaminates the review.

---

## Review prompt template

Copy this prompt verbatim. Fill in only `{PR_NUMBER}`.

```
You are reviewing PR #{PR_NUMBER} on an open-source project you have never seen before.

## Product context

aura-distill is a first-principles memory system shared by Claude Code and Codex. Users install it via install.sh or install.ps1, which places knowledge in ~/.aura-distill/ and adds client adapters. Claude can trigger distillation with the /distill slash command; Codex users ask it to distill. The distillation turns conversation signals into tiered knowledge files. The system runs entirely inside the client — no server, no dependencies, just markdown files and prompts.

Target users: developers using Claude Code or Codex who want persistent, structured memory across sessions.

## Your task

Review this PR thoroughly. You are the only quality gate before this ships to users.

### Step 0: Understand the project

Read AGENTS.md, README.md, and the architecture files listed in AGENTS.md's Architecture section (distill.md, distill-process.md, distill-monitor.md, knowledge-architecture.md, install.sh). Do NOT skip this — you need project context to evaluate whether changes are correct and coherent.

### Step 1: Understand the PR

Run `gh pr view {PR_NUMBER}` and `gh pr diff {PR_NUMBER}`. Read every changed file in full (not just the diff) to understand the surrounding context.

### Step 2: Evaluate

For each area, report PASS, FLAG (concern but not blocking), or BLOCK (must fix before merge):

**Correctness**
- Do the changes do what they claim?
- Are there logic errors, race conditions, or unhandled edge cases?
- Do file references and paths resolve correctly?

**Consistency**
- Do changes in one file match changes in related files? (e.g., if the dispatcher references .status, does the process engine also reference .status?)
- Are naming conventions consistent with the rest of the codebase?
- Do version numbers match across VERSION, install.sh, and docs?

**Security**
- Could any change expose user data or grant unintended permissions?
- Are there any paths where user input flows into shell commands unsanitized?
- Does the install script do anything beyond what it claims?

**Regression risk**
- Could existing users be broken by this change?
- Are there backwards-compatibility concerns (e.g., old .lock files vs new .status files)?
- If a file format changed, is there migration handling?

**Test coverage**
- Are the changes tested? Run the test suite if one exists.
- Are edge cases covered?
- If tests were updated, do the new assertions match the new behavior?

**Documentation**
- Do user-facing docs (README, landing page, install output) match the new behavior?
- Are internal docs (AGENTS.md, architecture docs) updated?

**Prompt quality** (specific to this project — the "code" is largely LLM prompts)
- Are instructions to Claude clear and unambiguous?
- Could Claude misinterpret any instruction in a way that causes harm?
- Are there conflicting instructions between files?

### Step 3: Report

Structure your review as:

#### Summary
One paragraph: what this PR does and your overall assessment.

#### Findings
List each finding with its severity (PASS / FLAG / BLOCK), the file and line, and a clear explanation. Group by area.

#### Verdict
APPROVE, REQUEST CHANGES, or NEEDS DISCUSSION. With a one-line justification.
```

---

## Rules

1. **Never self-review in the same context.** If you wrote it, you cannot review it. Period.
2. **The reviewer's verdict is respected.** If it says BLOCK, you fix the issue before merging. Don't argue with the reviewer in a different context window — fix the code.
3. **Don't coach the reviewer.** The whole point is an unbiased perspective. If you tell it "pay special attention to the lock file migration," you've already biased it toward approving the migration and looking for small issues instead of questioning whether the approach is right.
4. **Run tests in the worktree.** The reviewer should execute `./test-sandbox.sh` or equivalent in its isolated copy. If the test harness is unavailable (e.g., missing auth config), note this in the review and evaluate test coverage from code inspection instead.
5. **One reviewer per PR.** Don't spawn multiple reviewers hoping one will approve. If the first reviewer blocks, fix the issues and request a new review.

## What good looks like

A good independent review catches things like:
- "The dispatcher checks `.status` but the process engine still references `.lock` in one place" (consistency)
- "The install script writes to `~/.claude/settings.json` but doesn't handle the case where settings.json is malformed JSON" (edge case)
- "The FAQ says 'it complements memory.md' but the monitor explicitly tells Claude NOT to use memory.md" (contradiction)
- "There's no migration path for users who have the old `.lock` file — their next distill will think a stale lock exists" (regression)

These are exactly the things the authoring agent would miss — because it *knows* the lock migration is handled, and that knowledge prevents it from checking.
