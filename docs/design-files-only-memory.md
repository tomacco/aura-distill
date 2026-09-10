# Files-only memory redesign

Discovery deliverable for [#75](https://github.com/tomacco/aura-distill/issues/75), part of program [#74](https://github.com/tomacco/aura-distill/issues/74). Status: **proposed** (independent adversarial review applied, see the end). Implementation is [#78](https://github.com/tomacco/aura-distill/issues/78); lifecycle is [#73](https://github.com/tomacco/aura-distill/issues/73); thin-index enforcement is [#41](https://github.com/tomacco/aura-distill/issues/41); read batching is [#64](https://github.com/tomacco/aura-distill/issues/64).

The problem in one line: the knowledge base only grows, every limit ends in "ask the user", and the one file loaded on every session start has become a digest instead of an index. This document decides the file layout, the budgets, the lifecycle policy, the retrieval protocol, the migration path and the honest guarantees of an edition that runs on files plus the harness the user already has. No new executable, daemon, service, connector, account or network dependency.

## 1. Foundations (verified in the current code)

Each fact is observed in the repository at `main` (v1.1.17). Proposals start in section 2.

| # | Fact | Evidence |
|---|---|---|
| F1 | The only file loaded on every session start is `SPINE.md`; the always-on preferences block in `rules/distill.md` is capped at 15 lines. Tier-2 files are read on demand. | `distill-monitor.md` "MANDATORY: Knowledge retrieval"; `distill-process.md` Step 3c |
| F2 | Caps are counted in **lines**: SPINE 80 (compact at 60), tier-2 60 (compact at 45). Nothing bounds bytes per entry or per file. | `distill-process.md` "The Tier System", Step 5; `knowledge-architecture.md` |
| F3 | The SPINE format implies ~150 characters per line ("Each line must fit in ~150 characters"), i.e. an intended ceiling near 12 KB, but that ceiling is never checked. A real profile reached 80 lines and 39 KB. | `knowledge-architecture.md` Tier 1 rules; #73 evidence table |
| F4 | Every lifecycle rule terminates in "flag" or "ask the user". No rule may archive, split or retire on its own. | `distill-process.md` Step 5 "Spine compaction", "File compaction", "Staleness review"; `knowledge-architecture.md` "Staleness review" |
| F5 | Archiving is defined as a **rewrite** ("denser expression, not deletion"), so it costs a compression pass per file. Observed result: 5 archived files in three months. | `distill-process.md` Step 3 "General encoding rules"; `knowledge-architecture.md` Tier 3; #73 |
| F6 | Principles and their dated evidence (confirmations, corrections, observations) live in the same file under the same cap. Compaction may drop neither, so the cap cannot be met once a principle accumulates history. | `distill-process.md` Step 3a metadata format; #73 root cause 3 |
| F7 | Integrity rules forbid dropping or compressing `[NON-NEGOTIABLE]`, `[DIRECTIVE]` or safety-relevant entries for token reasons. Verbatim wording wins. | `distill-process.md` Step 5 "Economics accounting" |
| F8 | `archive/` is deliberately outside the SPINE and outside the orphan scan. The only way to discover an archived file is a cross-reference in a tier-2 file or the SPINE "mentioning" it, which the same rules forbid. Archived knowledge is therefore undiscoverable on a miss. | `distill-process.md` Step 0 "Knowledge integrity check" item 2; `knowledge-architecture.md` "When to read a Tier 3 file" |
| F9 | Retrieval has no batching instruction and discovers required reading hop by hop through arrows inside tier-2 files. | `distill-monitor.md`; #63 and #64 baselines |
| F10 | Concurrency is a single `.status` lock with checkpoints. Any new maintenance operation must run under it. | `distill-process.md` Step 0 "Concurrency & Status" |
| F11 | The shared sync set (owned by #61) is knowledge `*.md` plus `inbox/`; `data/` is local diagnostics and never synced. New directories must declare which side they fall on. | #61 "Sync set" |
| F12 | Three clients read the same `{DISTILL_DIR}` files: Claude Code (`commands/distill.md`, `rules/distill.md`), Codex (managed `AGENTS.md` block) and Antigravity (plugin rules and skill). All defer to `distill-monitor.md` and `distill-process.md`. | `AGENTS.md` Architecture; `plugins/aura-distill/rules/AGENTS.md` |
| F13 | The harness cannot observe reads. The only per-file activity signal that exists today is the `last_validated` stamp written by validate-on-read. `last_updated` is a write stamp, not a use stamp. | `knowledge-architecture.md` "Memory Recall Protocol" |
| F14 | Existing developer checks are deterministic shell and PowerShell suites (`tests/test-codex.ps1`, `tests/antigravity/run-parity-test.sh`, `test-version-bump.sh`) plus the API-backed `test-sandbox.sh`. They run in CI; they are not user dependencies. | `AGENTS.md` Testing; `.github/workflows/installer-tests.yml` |

## 2. Decisions

### D1. Budgets are bytes, checked at write time, with lines as a secondary cap

The SPINE gets a byte budget in addition to its line budget, and each entry gets its own byte cap. A distillation may not finish with the SPINE over budget: the same run must shorten entries, and the removed wording is appended verbatim to the target file's evidence twin (D2) as a dated `spine-detail:` line, so nothing the index once said is lost. "Flag" is no longer a terminal state for the index.

| Surface | Hard cap | Compact at | Why |
|---|---|---|---|
| `SPINE.md` | 80 lines and 16,000 bytes | 60 lines or 12,000 bytes | 12 KB is F3's implied ceiling; 16 KB (~4K tokens) leaves 30% headroom before the run must act |
| One SPINE entry | 400 bytes | 300 bytes | Title, path and up to five trigger nouns fit; a digest does not |
| One tier-2 file | 60 lines and 6,000 bytes | 45 lines or 4,500 bytes | Keeps the existing line cap and adds the byte cap that makes it meaningful |

Entry hooks must keep the **distinctive nouns** that make retrieval fire (project names, tool names, error strings). Compression removes explanation, never triggers. The measurement is `wc -c`; the distiller reports the three numbers in its Economics line. A byte cap is checkable by the harness with one command, which is what makes it enforceable in a files-only edition (see section 6).

### D2. Evidence moves to a parallel tree; the principle file keeps only the principle

New directory `evidence/`, mirroring the tier tree: `craft/review-protocol.md` pairs with `evidence/craft/review-protocol.md`. The evidence file is **append-only**, never compacted, never listed in the SPINE, and holds the dated record: confirmations, corrections, observations, superseded findings, session pointers. The principle file keeps the principle, its `confidence:` line with counts, its `last_validated:` date and a one-line citation ("evidence: 2026-08-10, 2026-08-12").

Format of an evidence file:

```markdown
---
evidence_for: craft/review-protocol.md
---
- 2026-07-12 confirm: reviewer caught a numeric-range crash both twins missed (PR #39)
- 2026-08-10 correct: relayed root-cause was wrong; observation right, diagnosis reproduced
```

Consequences: the tier-2 cap becomes satisfiable by construction (F6 dissolves), validation history stays intact and cheap, and "why do we believe this?" has a place to look. Evidence is knowledge and belongs to the shared sync set (F11). Old clients that do not know `evidence/` simply never read it; the orphan scan in the current process globs only tier directories, so it does not misreport evidence files.

### D3. Archive is a byte-identical move, catalogued, never a rewrite

Archiving `projects/atlas.md` means `mv projects/atlas.md archive/projects/atlas.md`. Nothing inside the file changes, so the move is verifiable by checksum and reversible by one move back. Its evidence file stays where it is. The facts about the move (date, reason, source path) live in the catalog (D4), not in the file, which is what keeps the file byte-identical.

The compression pass that F5 required is gone. A file that comes back is restored, not rewritten. If someone later wants a denser archived version, that is a normal edit of an archived file, not a precondition of archiving.

### D4. A complete catalog replaces "the SPINE mentions it"

New file `CATALOG.md` at the store root, **not auto-loaded**, rebuilt by the distiller at the end of every run from frontmatter. One line per file under `craft/ ops/ profile/ projects/ feedback/ archive/ evidence/`, sorted by path, grouped by status:

```markdown
# Knowledge catalog
<!-- Complete inventory, rebuilt by /distill from frontmatter. Not loaded at session start. rebuilt: 2026-09-11 -->
## active
- craft/testing.md | testing philosophy for Noor's services | validated 2026-08-30
## archived
- archive/projects/atlas.md | Atlas data-platform migration | archived 2026-09-11 | reason: past threshold, no validation observed | from projects/atlas.md
## evidence
- evidence/craft/testing.md | for craft/testing.md | 14 entries
```

The rebuild is mechanical (read `scope:` and `last_validated:` from each file; count evidence lines) so a developer check can assert it matches the tree. The SPINE carries exactly one fixed line pointing at the catalog. No list of archived names ever enters the SPINE; this supersedes the shared "Archived projects: a, b, c" line proposed in #73.

The catalog gives the files-only edition what F8 lacks: a bounded, complete place to look on a miss, and an enumeration surface for integrity checks (orphans, broken pointers, files missing from the catalog).

### D5. Scoped misses: the catalog bounds what "not found" means

Retrieval protocol on a miss, added to `distill-monitor.md`:

1. No SPINE hook matches the topic. Search `CATALOG.md` for the topic's distinctive words.
2. An archived match: read it, state "found in the archive (archived on DATE, reason R)". Increment nothing; reads are unobserved (F13).
3. No catalog match: say **"No SPINE entry or catalog line (rebuilt DATE) names X. It may still sit inside a broader file. This is not proof X was never distilled."** Never convert a miss into "we never distilled X".
4. Catalog older than the SPINE's `last_updated`: report the catalog as stale and say so in the answer.

This is the files-only shape of #66. The model is instructed; nothing enforces the wording at runtime (section 6).

### D6. Required reading is declared, and reads are batched

Tier-2 files may declare `read_with:` in frontmatter, a list of paths that must be read alongside them. `distill-monitor.md` gains two rules:

- After reading the SPINE, issue **all** matched tier-2 reads in one batch (parallel tool calls) when the client supports it; serialize only when a file's content decides what to read next.
- After that batch, read the union of their `read_with:` lists in one more batch. Depth is one; no transitive closure. A file that needs a deeper chain lists the deeper file directly.

Old arrow-style cross-references in prose stay as navigation hints. This is the files-only shape of #63 and #64 and it fattens nothing in the SPINE. Which clients honour parallel tool calls is verified per client in #78, and a client that cannot batch is told so explicitly rather than assumed.

### D7. Lifecycle: an enabled policy acts on eligible files without per-item questions

The policy is **opt-in** (release frame: a behaviour change ships as a knob). It is persisted in `{DISTILL_DIR}/.lifecycle` (`enabled` or `disabled`; absent means disabled). When disabled, the distiller reports debt and asks nothing, which is strictly less noise than today.

When enabled, at Step 5 of every distillation and on the standalone invocation `/distill gc`:

| Rule | Detail |
|---|---|
| Eligible | A file under `projects/` whose `last_validated` (fallback `last_updated`) is older than its `staleness_threshold` (default 90 days) |
| Exempt | Frontmatter `lifecycle: pinned`; any file outside `projects/` (craft, ops, profile, feedback keep ask-first, because a stale principle is not a finished project) |
| Action | Byte-identical move to `archive/projects/<name>.md` (D3); catalog line written with reason `past threshold, no validation observed`; SPINE entry removed; the run's report lists every move |
| Ambiguous | A file referenced by another active file's `read_with:` is not moved; the reason is recorded durably in `data/lifecycle.jsonl` and in the report |
| Interrupted | A manifest `data/lifecycle/<ts>.json` (src, dst, sha256 per planned move) is written before the first move and marked done per move; a later run finds an unfinished manifest and completes or reverts it |
| Restore | `/distill restore <path>` moves the file back, checks the sha256 from the manifest or catalog, rewrites the catalog and re-adds a SPINE entry |
| Preview | `/distill gc --preview` prints the plan and changes nothing; `--apply` executes it. Preview is the default |

Demotion is not a claim that the project ended. Age alone never means that; the move only says "not validated within threshold, kept whole in cold storage, findable through the catalog". Maintenance writes never bump `last_validated` or `last_updated`, so maintenance cannot look like use. Reads without validation stay unobserved and count as unknown, not as inactivity; that is why only `projects/` files are eligible and the threshold is per file.

`[NON-NEGOTIABLE]` and `[DIRECTIVE]` markers do not block a move, because a move preserves wording verbatim (F7 forbids dropping or compressing, not relocating). They do appear in the report line for that move, and a directive-bearing file is retrievable through D5 the next time the project comes up.

### D8. Version line: additive, stays on 1.x

Everything above adds files, directories and frontmatter fields. No existing file format changes, no existing path moves except through the explicit lifecycle action, and the SPINE format is unchanged apart from being shorter and carrying one catalog line. A client running the current instructions against a redesigned store keeps working: it ignores `evidence/`, `CATALOG.md` and `.lifecycle`, its orphan scan still globs only tier directories, and its compaction rules still only flag.

Therefore this ships in the files-only compatibility line, not as a major. Recorded consequence: a **mixed-version store** (one machine on old instructions, one on new, sharing through #61) drifts in one visible way, the catalog's `rebuilt:` date falls behind the SPINE, which D5 step 4 reports. If implementation in #78 finds it must change an existing format after all, the major-review gate from #76/#79 applies to it as well.

### D9. Sync classification of new paths

| Path | Sync set (#61) | Reason |
|---|---|---|
| `evidence/**` | shared | knowledge |
| `archive/**` | shared | knowledge (already the case) |
| `CATALOG.md` | shared | derived, but cheap and useful offline; rebuilt on conflict |
| `.lifecycle` | local | per-machine choice, like `.token-saver` |
| `data/lifecycle.jsonl`, `data/lifecycle/*.json`, `data/migration/**` | local | diagnostics and recovery manifests |

## 3. Migration of an existing store

Run once by the distiller as `/distill migrate-store`, under the `.status` lock. Preview is the default; `--apply` executes.

1. **Preview.** Write `data/migration/<ts>/PLAN.md`: proposed SPINE (every entry within D1 caps), the list of lines per tier-2 file that would move to its evidence twin, the lifecycle plan if `.lifecycle` is enabled, and the three budget numbers before and after. Nothing else changes.
2. **Backup.** On `--apply`, copy `SPINE.md` and every tier-2 file into `data/migration/<ts>/backup/` and write `PENDING`. Only then edit.
3. **Apply.** Rewrite the SPINE from the plan; for each tier-2 file, move the planned lines to `evidence/<tier>/<name>.md` (append) and keep the principle file; create `CATALOG.md`; perform lifecycle moves only if enabled. Delete `PENDING`, write `DONE` with the same three numbers.
4. **Interrupted.** A later run that finds `PENDING` offers two mechanical choices: finish the plan, or roll back by copying `backup/` over the store. Both are copies, not judgement.
5. **Repeated.** Running migration on a migrated store is a no-op plan (no entry over cap, no evidence lines left in principle files) and says so.
6. **Manual edits.** Users may edit any file at any time. The next distillation re-validates budgets and rebuilds the catalog. A user-edited SPINE over budget is reported and compacted like any other over-budget write; original wording goes to the target's evidence twin, never dropped.

Which lines are evidence is a **judgement the distiller makes** (dated observations, confirmation counts, session anecdotes, superseded findings). The migration therefore cannot be proven correct by the agent; it is proven **lossless** by a mechanical check: every non-blank line of every pre-migration tier-2 file must appear verbatim in its principle file, its evidence twin, or the archive after migration. `tests/files-only/check-store.sh` implements exactly that check on the synthetic fixture (section 5) and is the model for the real run's self-check, which the distiller runs before deleting `PENDING`.

## 4. What the running harness must do (instruction changes)

| File | Change |
|---|---|
| `distill-monitor.md` | Batch reads (D6), `read_with` closure (D6), scoped-miss wording (D5), one sentence that the catalog exists and is not loaded at start |
| `distill-process.md` | Step 0: integrity check includes catalog freshness and evidence files; Step 3: write principle to the tier file, evidence lines to the twin; Step 4: byte-budget check with `wc -c` and forced same-run compaction; Step 5: replace "flag" and "ask" for `projects/` with D7 when enabled, rebuild catalog, report debt with a sign; new `gc`, `restore` and `migrate-store` sub-procedures |
| `distill.md` | Dispatcher accepts `gc [--preview|--apply]`, `restore <path>`, `migrate-store [--preview|--apply]`; passes them to the sub-agent without a harvest |
| `knowledge-architecture.md` | Document `evidence/`, `CATALOG.md`, byte budgets, move-not-rewrite, the lifecycle table |
| Client adapters (Claude rules, Codex block, Antigravity rules) | No change needed; they defer to the two files above (F12). Verified per client in #78 |
| Installers | Nothing new to download for runtime use. `.lifecycle` gets `--lifecycle / --no-lifecycle / --remove-lifecycle` and `$env:DISTILL_LIFECYCLE`, the same contract as Token Saver, in #78 |

## 5. Synthetic fixture and deterministic checks

`tests/files-only/store-before/` is a mature synthetic store for a fictional persona (Noor, platform engineer) that reproduces every diagnosed failure: SPINE entries over 400 bytes, a tier-2 file over 60 lines because it carries 30 dated observations, two `projects/` files past threshold (one pinned), a file with `[NON-NEGOTIABLE]` wording, an evidence-free file that must survive untouched. `tests/files-only/store-after/` is the same store after migration and one lifecycle pass with the policy enabled.

`tests/files-only/check-store.sh <store-dir> [--before <original-dir>]` asserts, deterministically and offline:

1. SPINE within D1 caps (lines, bytes, per-entry bytes); one catalog line present.
2. Every SPINE pointer resolves; every active tier-2 file has a SPINE pointer and a catalog line; every archived and evidence file has a catalog line; no catalog line points at a missing file.
3. Every tier-2 file within D1 caps; every `read_with:` target exists.
4. With `--before`: every non-blank line of every original tier-2 file appears verbatim in the after store (principle file, evidence twin, or archive); every archived file is byte-identical (sha256) to its original; every line carrying `[NON-NEGOTIABLE]` or `[DIRECTIVE]` still exists in an active or archived file; a pinned file was not moved.

Run against `store-before` it must FAIL on checks 1 to 3 (that is the regression test for the diagnosis: fat index, no catalog, evidence inflating a tier file); against `store-after --before store-before` it must PASS. `tests/files-only/run-files-only-tests.sh` asserts both, plus two tamper cases (a modified archived file, a dropped protected line) that C4 must catch. No live profile is read; no network.

## 6. Honest guarantees of this edition

| Property | Files-only edition | Enforced by |
|---|---|---|
| SPINE and tier-2 byte budgets | Checked by the distiller with `wc -c` at Step 4 and reported; CI checks the fixture | Instruction plus developer test. A distiller that skips the check is not stopped |
| Lossless migration and archive | Lossless by line-conservation and checksum checks the distiller runs before clearing `PENDING` | Instruction plus developer test on the fixture; the real run's check is agent-executed |
| Catalog completeness | Deterministic rebuild recipe; CI asserts catalog equals tree on the fixture | Same |
| Scoped-miss wording | Instruction only | Nothing at runtime; measured by #62 fresh-agent runs |
| Batching and `read_with` | Instruction only; client capability verified in #78 | Nothing at runtime; measured by #62 |
| Lifecycle atomicity | Manifest-before-move plus per-move completion marks; recovery is mechanical | Not transactional. A crash between two moves leaves a manifest a later run can finish or revert |
| Activity observation | Only `last_validated` from validate-on-read. Reads without validation are unknown | Cannot be improved without software (#83) |
| Concurrent distillations | Existing `.status` lock | Same as today |

Nothing here observes every read, guarantees a transaction, or enforces a budget against a distiller that ignores its instructions. Those are the Track B deliverables (#82, #83, #85, #86). What this edition guarantees is that the **checks exist, are one command each, and the fixture proves they catch the failures we diagnosed**.

## 7. Mapping to #75 acceptance criteria

| Criterion | Where |
|---|---|
| Reviewed design and synthetic before/after store establish file format, routing, evidence preservation, migration/recovery and scoped-miss semantics | Sections 2, 3, 5; `tests/files-only/` |
| Dependency inventory proves no new end-user executable/service/account/connector | Section 4 last two rows; the only new artefacts are markdown files, frontmatter fields and dispatcher arguments; the check script is developer-side |
| Agent-managed limitations explicit | Section 6 |
| Correctness-blocking format and compatibility questions resolved before implementation | D1 to D9; section 8 lists what remains and who owns it |
| Design maps first-release work to #41, #64, #73 and #78 | Section 4 and the decision headers |

## 8. Open questions (none blocking implementation)

| Question | Owner | Exit |
|---|---|---|
| Are 16 KB / 400 B / 6 KB the right numbers? | #62 measurement on the redesigned files edition | Adjust caps from measured coverage and latency; the check script takes them as parameters |
| Does `read_with` depth one cover real fan-out scenarios? | #62 | Fan-out scenarios keep required-fact coverage with two read rounds |
| Default for `.lifecycle` at install | Ivan | Off is the release-frame default; on requires a documented-consequences line in the installer |
| Heuristics for classifying evidence lines during migration | #78 | Fixture plan matches what a fresh agent produces on the before store |
| Whether Codex and Antigravity honour parallel reads | #78 | Verified per client, wording adjusted where they cannot |

## 9. Review record

Adversarial review (clean-context agent instructed to attack the design) and the independent PR review per `REVIEW-PROTOCOL.md` are recorded on the pull request. Decision-changing findings were folded into the sections above; accepted risks are named in section 6.
