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

When a PR is ready for review, the authoring agent runs the clean reviewer (rule 9):

```
tests/review/run-clean-review.sh <PR_NUMBER> <a model other than the author's>
```

If no reviewer profile exists yet, the fallback is an Agent-tool reviewer, which inherits the session's profile and must disclose it (rule 9):

```
Agent({
  description: "Independent PR review",
  isolation: "worktree",
  model: <a model other than the author's — see rule 7>,
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

Copy this prompt verbatim. Fill in only `{PR_NUMBER}`. The only permitted addition is one line naming the repository and saying the session is headless (run commands in the foreground, finish the report before stopping), which `run-clean-review.sh` appends.

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
List each finding with its severity (PASS / FLAG / BLOCK), the file and line, and a clear explanation. Group by area. For each BLOCK, state the fix you would accept.

#### Verdict
APPROVE, REQUEST CHANGES, or NEEDS DISCUSSION. With a one-line justification.

Return the review as your final message. Do not post it, push, or modify the PR.
```

---

## Rules

1. **Never self-review in the same context.** If you wrote it, you cannot review it. Period.
2. **The reviewer's verdict is respected.** If it says BLOCK, you fix the issue before merging (rule 6 defines the only exceptions, after round three). Don't argue with the reviewer in a different context window — fix the code.
3. **Don't coach the reviewer.** The whole point is an unbiased perspective. If you tell it "pay special attention to the lock file migration," you've already biased it toward approving the migration and looking for small issues instead of questioning whether the approach is right.
4. **Run tests in the worktree.** The reviewer runs the deterministic suites listed in AGENTS.md (Testing) in its isolated copy. It never runs `./test-sandbox.sh` or any other live-model harness: `test-sandbox.sh` points `CLAUDE_CONFIG_DIR` at the real profile and starts nested sessions with permissions skipped. If the test harness is unavailable (e.g., missing auth config), note this in the review and evaluate test coverage from code inspection instead.
5. **One reviewer per round.** Don't spawn parallel reviewers hoping one will approve. If the first reviewer blocks, fix the issues and request a new review.
6. **Reviews converge in at most three rounds.** A round is one reviewer's complete report on the PR's current head; each round uses a new reviewer instance with clean context (the model may repeat across rounds, but never the author's — rule 7). A NEEDS DISCUSSION verdict goes to the maintainer and does not count as a round. After the third round, every remaining BLOCK must end in one of three ways before merge:
   - it is fixed as the reviewer prescribed (or, if no fix was prescribed, fixed), and the fix is quoted in the resolution comment;
   - it is turned into a failing test that is then made to pass;
   - it is recorded as a named known risk in the PR and, in the same PR, under `### Known risks` in `CHANGELOG.md` `[Unreleased]`. The release page of the version that ships it lists it; the PR that fixes it removes the entry.
   BLOCKs about security, user-data loss, or writes outside `{DISTILL_DIR}` or the test sandbox never take the third path. The reviewer marks such BLOCKs `[HARM]`; the author may not remove the mark.

   Commits after the third round are limited to the listed resolutions. Anything beyond them (new behaviour, new files, a changed user-facing surface, or a fix larger than the BLOCK it resolves) starts a new three-round cycle or waits for the maintainer. Path-1 and path-2 resolutions get one **closing check**: a fresh reviewer reads only the diff since round three, confirms each resolution does what the BLOCK asked, and may not raise new BLOCKs except `[HARM]`. A failed closing check sends the PR to the maintainer. Rounds are counted per PR from the merge of the PR that adopted this rule (#104) into `beta/1.2`; earlier rounds count as history, not toward the cap. If none of the three fits, the PR waits for the maintainer. Why: open-ended rounds kept finding new composition issues as a design grew (PR #93 had six rounds and all six returned REQUEST CHANGES), and nothing said when a design was good enough.
7. **The reviewer runs on a different model from the author, of comparable or greater capability.** If none is available (the author already runs on the most capable model and only one vendor is installed), use the most capable different model and note the downgrade in the review comment. Reviews from the model that wrote the change share its blind spots. Pick the reviewer's model explicitly (for example, the Agent tool's `model` option). For a release gate — cutting a prerelease or promoting a branch to `main` — also use a reviewer from a different vendor or harness when one is installed (for example, Codex). That reviewer reads the full diff being released (for a promotion, `main...beta/<version>`) and its verdict is posted on the release PR; rule 6 applies to it. The authoring agent records the reviewer's model in the review comment. Never use a forked agent (`subagent_type: "fork"`) as a reviewer: it inherits the author's context and model.
8. **Resolutions are traceable.** The authoring agent posts every review and its resolution as PR comments: each finding, and what changed or why it did not. When a finding is routed to another issue, add it to that issue in the same step. A routing that exists only in a PR comment or an agent's prompt is lost.
9. **The reviewer's environment carries no author context.** A clean context window is not enough if the reviewer's client auto-loads memory at session start (for example, this project's own `rules/distill.md` loading a maintainer's knowledge store, which may hold the author's reasoning or proposals). Run reviewers with such memory disabled or pointed at an empty store. If that is not possible, the reviewer says so in its report and treats anything loaded that way as background only; the authoring agent records it in the review comment. Never disable it by editing the real profile (`~/.claude/rules/`, `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` — AGENTS.md "Never touch real user data"). Use a separate config dir that never ran the installer (`CLAUDE_CONFIG_DIR`), or a session started from one. (`test-sandbox.sh` is not an example: it points `CLAUDE_CONFIG_DIR` at the real profile for auth.) A reviewer spawned with the Agent tool inherits the session's profile and takes the disclosure path. `tests/review/run-clean-review.sh <pr> <model>` does this: it runs the verbatim template headless in a separate reviewer profile (default `~/.claude-reviewer`), in a fresh detached worktree of the PR head, with no MCP servers, auto-memory off and no posting, pushing or merging tools, and refuses a profile that has aura-distill installed.

## What good looks like

A good independent review catches things like:
- "The dispatcher checks `.status` but the process engine still references `.lock` in one place" (consistency)
- "The install script writes to `~/.claude/settings.json` but doesn't handle the case where settings.json is malformed JSON" (edge case)
- "The FAQ says 'it complements memory.md' but the monitor explicitly tells Claude NOT to use memory.md" (contradiction)
- "There's no migration path for users who have the old `.lock` file — their next distill will think a stale lock exists" (regression)

These are exactly the things the authoring agent would miss — because it *knows* the lock migration is handled, and that knowledge prevents it from checking.
