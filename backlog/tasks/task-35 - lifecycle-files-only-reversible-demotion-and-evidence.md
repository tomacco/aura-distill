---
id: task-35
title: "Lifecycle: files-only reversible demotion and evidence preservation"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [area:memory-service]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/73
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/73

## Execution update (2026-09-10)

Part of #74. Blocked by: #75

The current contract below supersedes conflicting mechanics or acceptance criteria in the historical proposal.

Track A owns this first lifecycle implementation, using files and existing harness capabilities. The software-enforced edition is later owned by #86; do not wait for software telemetry, a database or a service before improving the files-only process.

### User story

As a user, I want reversible maintenance under an enabled policy without deciding the fate of individual files at every distillation.

### Current scope and acceptance

- [ ] Implement the lifecycle policy approved in #75: preview/apply/restore, pins/exceptions, persisted enable/disable and an independent maintenance invocation using existing capabilities.
- [ ] Separate actual task activity, last edit, validation freshness, project status and authority. Missing activity observations remain unknown; maintenance touches do not count as use, and age alone never means a project ended.
- [ ] Preserve original evidence/source bytes, binding wording and applicability; archive discovery uses the file catalog, not an ever-growing SPINE digest.
- [ ] An enabled policy demotes eligible content without per-item questions; ambiguous/conflicting cases get durable reasons while safe independent actions proceed.
- [ ] Synthetic mature-store cases cover resumed projects, rare directives, missing activity, stale-but-running projects, pins, interrupted runs and restore. Do not replay against a real profile as a default test.
- [ ] Reports distinguish stored versus active context and unresolved debt. Moving files out of a metric denominator alone does not prove retrieval improvement.
- [ ] State which checks rely on agent execution and cannot be hard runtime guarantees in the files-only edition. #62/#80 measure actual compliance and retrieval quality.

#86 later reuses this policy with mechanical validation, complete indexing and observable operation statistics. No claim that the files-only release automatically observes every read is permitted.

Fable's original diagnosis/evidence below is retained. Its age-only eight-live-file acceptance, shared archive-name SPINE line and permanent pinning of whole protected files are superseded by this contract.

<details>
<summary>Original report and proposal (preserved historical context)</summary>

## Problem

The knowledge base only grows. Every cap and threshold in `distill-process.md` ends in "flag" or "ask the user", so nothing ever leaves the working set on its own. After three months of daily use the index sits at its hard cap, the largest files are three to five times over their cap, and every distillation ends by asking the user to make archival decisions. On 2026-09-10 the user answered that question with "current aura distill architecture / rules are showing its limits" rather than picking files. That is the correct reading: the user has become the garbage collector, and a garbage collector that needs a human decision per object does not run.

## Evidence (one real profile, 2026-09-10)

| Measure | Rule | Actual |
|---|---|---|
| SPINE lines | max 80, compact at 60 | 80 (hard cap reached) |
| SPINE size | pointer index | 39 KB, ~9.8K tokens loaded every session |
| Tier-2 files over the 45-line cap | compact | 15 files over 100 lines; largest 251 (`profile/working-style.md`) |
| Files past their own `staleness_threshold` | ask the user | 8 (project files 4 to 62 days over) |
| Archive | Tier 3 | 5 files total in three months |
| `kb_tokens` trend (economics ledger) | | 69K on 2026-07-09 to 113K on 2026-09-10, monotonic, ~+2K per run |
| `spine_tokens` trend | | 6.1K to 9.8K over the same period, monotonic |

The last distillation report said, verbatim, that it stopped compacting `ops/whea-crash-forensics.md` at 65 lines because "every remaining line is evidence or a checkpoint, so I stopped rather than drop data". That is the agent following the rules correctly. The rules have no move available.

## Root cause

Four rules interact:

1. **Every limit is advisory.** "If > 60, flag for compaction." "If > 45 lines, flag." "Ask the user: is [file] still relevant?" No rule can archive, split, or retire without a human answer, and the answer is requested at the worst moment: the end of a long session, as a list of eight file names.
2. **Archival is defined as a rewrite.** "Moving to archive means denser expression, not deletion." Under that definition archiving costs a full compression pass per file, so the agent defers it, so it never happens. Five archived files in three months.
3. **Evidence and principle share the same budget.** A principle line and the twelve dated observations that support it live in the same file under the same 45-line cap. Compaction cannot drop the observations (they are the validation record) and cannot drop the principle, so the cap is unenforceable by construction.
4. **The SPINE cap counts lines, so entries fatten.** Already filed as #41. It compounds here: at 80/80 lines the only way to add a domain is to delete one, and no rule permits that.

Net effect: growth is monotonic, health is reported at every run (the report is honest), and the only lever offered is a question the user is not positioned to answer.

## Why the open issues do not cover this

- #41 is per-entry length in the SPINE. This issue is about the working set never shrinking at any tier.
- #66 is about answering misses from the index. Orthogonal.
- #69 / #70 are about naming causes behind symptom clusters. Synthesis is one way to shrink a domain, but it does not address stale projects or the evidence-vs-principle budget.

## Proposal

Turn lifecycle into deterministic actions with defaults, and reserve questions for the cases where a default would be wrong.

1. **Staleness acts by default.** A `projects/` file past its threshold with no session touching it is archived in the same run: file moved to `archive/` unchanged (a move, not a rewrite), SPINE entry collapsed into a single shared line ("Archived projects: a, b, c. Read `archive/<name>.md` when the project comes back"). Reversible in one move. The report lists what was archived. `craft/`, `ops/`, `profile/`, `feedback/` keep the ask-first behaviour, because a stale principle is not the same as a finished project.
2. **Budgets become write-time constraints.** A SPINE write that would exceed the line or byte budget must merge or displace within the same run. A tier-2 write that lands a file over its cap triggers the split or the evidence move (item 3) in the same run. "Flag" is no longer a terminal state.
3. **Separate the evidence log from the principle.** Each tier-2 file keeps principles and their one-line citations; dated observations, counts, and superseded findings move to `archive/<file>-evidence.md` (append-only, never compressed). The cap applies to the principle file only. Validation history stays intact and cheap.
4. **A standalone lifecycle pass.** `/distill --gc` (or a step run by the auto-distiller in #51) executes items 1 to 3 without a session harvest, so hygiene does not depend on a session happening to end well.
5. **Make debt visible in the structured report** (#55): lines over cap, files past threshold, bytes over budget, and the delta versus the previous run. A run that leaves debt higher than it found it says so.

## Acceptance

- [ ] Replay on this profile: a `--gc` run ends with the 8 stale project files archived by a move, the SPINE under 60 lines, and zero questions asked for `projects/`.
- [ ] Archiving a project file is a move plus a SPINE pointer rewrite. Content is byte-identical after the move.
- [ ] `kb_tokens` and `spine_tokens` in `data/economics.jsonl` can go down. Today they cannot.
- [ ] The distillation report shows compaction debt with a sign, and the number is lower after a `--gc` run than before it.
- [ ] No `[NON-NEGOTIABLE]`, `[DIRECTIVE]`, or always-on entry is moved or compressed by any automatic action (the integrity rule in Step 5 stands).

---
Filed by `claude-fable-5-1-distill-tomacco` (Claude Fable 5.1, Claude Code CLI on Ivan's Windows box), at the user's request after the 2026-09-10 distillation. Address me by sign-off name in comments.

</details>

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
