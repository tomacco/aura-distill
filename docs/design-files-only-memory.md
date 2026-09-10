# Files-only memory redesign

Discovery deliverable for [#75](https://github.com/tomacco/aura-distill/issues/75), part of program [#74](https://github.com/tomacco/aura-distill/issues/74). Status: **proposed**, revised after an adversarial clean-context review (section 9). Implementation is [#78](https://github.com/tomacco/aura-distill/issues/78); lifecycle is [#73](https://github.com/tomacco/aura-distill/issues/73); thin-index enforcement is [#41](https://github.com/tomacco/aura-distill/issues/41); read batching is [#64](https://github.com/tomacco/aura-distill/issues/64).

The problem in one line: the knowledge base only grows, every limit ends in "ask the user", and the one file loaded on every session start has become a digest instead of an index. This document decides the file layout, the budgets, the lifecycle policy, the retrieval protocol, the migration path and the honest guarantees of an edition that runs on files plus the harness the user already has. No new executable, daemon, service, connector, account or network dependency.

## 1. Foundations (verified in the current code)

Each fact is observed in the repository at `main` (v1.1.17). Proposals start in section 2.

| # | Fact | Evidence |
|---|---|---|
| F1 | Two files are loaded on every session start: `SPINE.md` (via the monitor) and the client's `rules/distill.md` (installed as an always-loading rules file; its preferences block is capped at 15 lines but the whole file, ~78 lines, is loaded). Tier-2 files are read on demand. | `distill-monitor.md` "MANDATORY: Knowledge retrieval"; `install.sh` "auto-loads every session"; `distill-process.md` Step 3c |
| F2 | Caps are counted in **lines**: SPINE 80 (compact at 60), tier-2 60 (compact at 45). Nothing bounds bytes per entry or per file. | `distill-process.md` "The Tier System", Step 5; `knowledge-architecture.md` |
| F3 | The SPINE format implies ~150 characters per line ("Each line must fit in ~150 characters"), i.e. an intended ceiling near 12 KB, but that ceiling is never checked. A real profile reached 80 lines and 39 KB. | `knowledge-architecture.md` Tier 1 rules; #73 evidence table |
| F4 | Spine compaction and the staleness review end in "ask the user". File compaction does **not** ask: it may split a file and "move superseded content to `archive/`", which produces rewritten, flat archive files (`archive/<name>.md`, not under a tier directory). | `distill-process.md` Step 5 "Spine compaction", "File compaction", "Staleness review" |
| F5 | Archiving is defined as a **rewrite** ("denser expression, not deletion"), so it costs a compression pass per file. Observed result: 5 archived files in three months, all flat and rewritten. | `distill-process.md` Step 3 "General encoding rules"; `knowledge-architecture.md` Tier 3; #73 |
| F6 | Principles and their dated evidence (confirmations, corrections, observations) live in the same file under the same cap. Compaction may drop neither, so the cap cannot be met once a principle accumulates history. | `distill-process.md` Step 3a metadata format; #73 root cause 3 |
| F7 | Integrity rules forbid dropping or compressing `[NON-NEGOTIABLE]`, `[DIRECTIVE]` or safety-relevant entries for token reasons. Verbatim wording wins. | `distill-process.md` Step 5 "Economics accounting" |
| F8 | `archive/` is outside the SPINE and outside the orphan scan. `knowledge-architecture.md` allows the SPINE to "mention" an archived topic, but nothing maintains such mentions, so in practice an archived file is discoverable only through a cross-reference inside a tier-2 file. | `distill-process.md` Step 0 "Knowledge integrity check" item 2; `knowledge-architecture.md` "When to read a Tier 3 file" |
| F9 | Retrieval has no batching instruction and discovers required reading hop by hop through arrows inside tier-2 files. | `distill-monitor.md`; #63 and #64 baselines |
| F10 | Concurrency is a single `.status` lock with checkpoints; a `running` status older than 5 minutes is treated as stale. | `distill-process.md` Step 0 "Concurrency & Status"; `distill.md` Step 0 |
| F11 | The shared sync set (owned by #61) is knowledge `*.md` plus `inbox/`; `data/` is local diagnostics and never synced. #61 also specifies a machine-local `local/` overlay with its own `local/SPINE.md` that is structurally never synced. New directories must declare which side they fall on. | #61 "Sync set", "Machine-local overlay" |
| F12 | Three clients read the same `{DISTILL_DIR}` files: Claude Code (`commands/distill.md`, `rules/distill.md`), Codex (managed `AGENTS.md` block) and Antigravity (plugin rules and skill). All defer to `distill-monitor.md` and `distill-process.md`. | `AGENTS.md` Architecture; `plugins/aura-distill/rules/AGENTS.md` |
| F13 | The harness cannot observe reads. The tier-2 template in `distill-process.md` has no file-level `last_validated`, while `knowledge-architecture.md` "Validation metadata" specifies one in frontmatter, so real stores carry either or both; per-principle `last_validated` lines are bumped on confirmation, and the old staleness review bumps `last_updated` when the user answers "still relevant". Validate-on-read also bumps `last_validated`. None of these is a read count. | `distill-process.md` Step 3a, Step 5 "Staleness review", "Tier 2 file format"; `knowledge-architecture.md` "Memory Recall Protocol" |
| F14 | Existing developer checks are deterministic shell and PowerShell suites (`tests/test-codex.ps1`, `tests/antigravity/run-parity-test.sh`, `test-version-bump.sh`) plus the API-backed `test-sandbox.sh`. They run in CI; they are not user dependencies. Codex on Windows runs PowerShell; the repo ships `.ps1` twins for that reason. | `AGENTS.md` Testing; `.github/workflows/installer-tests.yml` |

## 2. Decisions

### D1. Budgets are bytes and lines together; the first cap hit binds; checked at write time

The SPINE gets a byte budget in addition to its line budget, and each entry gets its own byte cap. A distillation may not finish with the SPINE over budget: the same run must shorten entries. "Flag" is no longer a terminal state for the index.

| Surface | Hard cap | Compact at | Note |
|---|---|---|---|
| `SPINE.md` | 80 lines and 16,000 bytes | 60 lines or 12,000 bytes | 12 KB is F3's implied ceiling; 16 KB (~4K tokens) is 30% headroom |
| One SPINE entry | 400 bytes | 300 bytes | Room for a title, a path and up to five trigger nouns; 40 such entries fill the byte cap, 80 thin ones fill the line cap |
| One tier-2 file | 60 lines and 6,000 bytes | 45 lines or 4,500 bytes | Keeps the existing line cap and adds the byte cap that makes it meaningful |

These numbers are **provisional**. The line caps are the shipped ones; the byte caps are set from F3 and headroom, not measured. #62 measures the redesigned files edition and owns adjustments; the checker takes every cap as a parameter.

**Where removed SPINE wording goes.** Wording cut from an over-cap entry is not evidence, it is index detail that may contain principles nobody wrote elsewhere (the fixture's original testing entry names three rules absent from the file). It is appended **verbatim to the target tier-2 file** under `## Index detail (moved from SPINE <date>)`, where the next distillation of that domain folds it into proper principles. It never goes to the evidence twin, which retrieval does not read. Order of operations: append, re-check the target against its own caps, split if the append pushed it over (the fixture's `craft/testing-2.md` is exactly this case). Entry hooks keep the **distinctive nouns** that make retrieval fire (project names, tool names, error strings); compression removes explanation, never triggers.

**Oversize files.** A tier-2 file that legitimately needs more than the cap (for example a file of twenty protected `[NON-NEGOTIABLE]` lines) is **split**: `craft/x.md` keeps the first part, `craft/x-2.md` carries the rest with frontmatter `split_from: craft/x.md`, both get SPINE entries, and the checker treats the split family as one unit for conservation. Splitting relocates wording verbatim, so F7 is respected. A file that cannot be split without breaking one atomic block may carry `oversize: <reason>` in frontmatter; it is then exempt from the byte cap and listed as such in the catalog, and the exemption is reported at every run.

Client rules files (F1) are a fixed recurring cost outside this design; the always-on block is governed by `distill-process.md` Step 3c and is not changed here.

### D2. Evidence moves to a parallel tree; the principle file keeps only the principle

New directory `evidence/`, mirroring the tier tree: `craft/review-protocol.md` pairs with `evidence/craft/review-protocol.md`. The evidence file is **append-only**, never compacted, never listed in the SPINE, and holds the dated record: confirmations, corrections, observations, superseded findings, session pointers. The principle file keeps the principle, its `confidence:` line with counts, its `last_validated:` date and a one-line citation ("Evidence: 2026-04-18 to 2026-08-30 in `evidence/craft/testing.md`").

Format of an evidence file (an **entry** is a line beginning with `- `):

```markdown
---
evidence_for: craft/review-protocol.md
---
- 2026-07-12 confirm: reviewer caught a numeric-range crash both twins missed (PR #39)
- 2026-08-10 correct: relayed root-cause was wrong; observation right, diagnosis reproduced
```

`evidence_for` names the tier path the twin belongs to and is that file's **identity for the files-only edition**; it does not change when the file is archived (the archived copy lives at `archive/<same path>`). An evidence file whose `evidence_for` names neither an active nor an archived file is an orphan and fails the checker. Track B (#82) introduces stable IDs; until then a path plus the no-collision rule in D3 is the reference.

A protected bullet (`[NON-NEGOTIABLE]`, `[DIRECTIVE]`) and its **indented continuation lines** (`confidence:`, `origin:`, `Why:`) stay together in the principle file; the checker protects the block, not just the first line.

Consequences: the tier-2 cap becomes satisfiable by construction (F6 dissolves), validation history stays intact and cheap, and "why do we believe this?" has a place to look. Evidence is knowledge and belongs to the shared sync set (F11). Old clients never read `evidence/`; their orphan scan globs only tier directories, so they do not misreport evidence files.

### D3. Archive is a byte-identical move, recorded in a synced ledger, never a rewrite

Archiving `projects/atlas.md` means `mv projects/atlas.md archive/projects/atlas.md`. Nothing inside the file changes, so the move is verifiable by checksum and reversible by one move back. Its evidence file stays where it is.

Provenance is written **at move time** to `archive/LEDGER.md`, an append-only, synced file with one line per move or restore:

```markdown
- 2026-09-11 archive | from: projects/atlas.md | to: archive/projects/atlas.md | sha256: 12c18385… | reason: past threshold, no validation observed | spine-entry: - [Atlas](projects/atlas.md) — Atlas data-platform migration …
```

The ledger line carries everything a restore or a second machine needs: the checksum, the reason, and the **full removed SPINE line**, so restore re-adds the entry that was removed (trimmed to the D1 entry cap if it predates compaction, with the cut wording going to the restored file) and nothing has to be invented. Restore-on-request also replaces the old `recall_count` promotion rule: when a miss resolves to an archived file the user then works on, the next distillation restores it. The catalog (D4) derives its archived rows from the ledger; a rebuilt catalog therefore never loses provenance, and a machine that receives the archive through sync receives the ledger with it.

**Ledger events.** Four event kinds, one line each, always appended, never edited:

| Event | Line shape | Written |
|---|---|---|
| `archive` | `- DATE archive \| from: X \| to: archive/X \| sha256: H \| reason: R \| spine-entry: LINE` | before the move |
| `restore` | `- DATE restore \| from: archive/X \| to: X \| sha256: H \| reason: R` | before the move back (`reason: user request`, or `reason: revert <manifest>` when a migration or gc plan is reverted, one line per reversed move) |
| `restore (modified)` | same shape, event text `restore (modified)`, `sha256:` = the checksum actually observed | when the archived file no longer matches its `archive` checksum |
| `move never completed` | `- DATE restore \| from: archive/X \| to: X \| reason: move never completed` | by a recovery run that finds an `archive` line whose move did not happen |

**State is the last event per path.** For every path X, the newest line whose `to:` or `from:` names `archive/X` decides: last event `archive` means X is archived (`archive/X` exists, X does not); any `restore` event means X is active (X exists, `archive/X` does not). A ledger that disagrees with the tree is an inconsistency the checker reports (C2), the migration self-check catches before clearing `PENDING`, and a recovery run repairs by completing the move or appending a `move never completed` line. Because the ledger is written before the move, a crash in that window is exactly this case and is repaired, not hidden.

**Byte identity means bytes.** Checksums and identity checks hash raw bytes; only line comparisons and counts ignore carriage returns. Consequently `archive/**` and `archive/LEDGER.md` must cross machines byte-exact: the sync protocol (#61) and any backup plugin must not normalise line endings for them. A git-backed backup with `autocrlf` on would break every ledger checksum on the receiving machine; D9 records this as a constraint on #61.

**Archived files are read-only for every client.** Validate-on-read and `recall_count` bumps do not apply under `archive/`; a session that reads an archived file on a miss changes nothing. Restore verifies the file against the ledger checksum; on mismatch it restores anyway, reports the difference, and appends a `restore (modified)` ledger line.

**No collision.** A path may not exist both as `X` and `archive/X`. A project that comes back is **restored**, not re-created; gc and the distiller refuse to write `projects/atlas.md` while `archive/projects/atlas.md` exists and report the collision. The checker enforces it.

**Legacy archives.** Files produced by the old rewrite-style compaction (F4, F5) sit flat under `archive/` with no ledger line. They are kept as they are, labelled `legacy` in the catalog, and never checked for identity against a source that no longer exists.

### D4. A complete catalog replaces "the SPINE mentions it"

New file `CATALOG.md` at the store root, **not auto-loaded**, rebuilt by the distiller at the end of every run. One line per file under `craft/ ops/ profile/ projects/ feedback/ archive/ evidence/`, sorted by path, grouped by status:

```markdown
# Knowledge catalog
<!-- Complete inventory, rebuilt by /distill. Not loaded at session start. rebuilt: 2026-09-11 -->
## active
- craft/testing.md | Testing philosophy for Noor's services … | validated 2026-08-30
- projects/comet.md | Comet billing reconciliation — on hold, retention rules | validated 2026-05-06 | pinned
## archived
- archive/projects/atlas.md | Atlas data-platform migration … | archived 2026-09-11 | reason: past threshold, no validation observed | from projects/atlas.md | hook: Atlas data-platform migration from the legacy warehouse …
- archive/old-warehouse-notes.md | Superseded warehouse notes | legacy
## evidence
- evidence/craft/testing.md | for craft/testing.md | 30 entries
```

Every field is derived: `scope:` from frontmatter; `validated DATE` = the newest of every date stamp in the file (frontmatter `last_validated`, `last_updated`, per-principle `last_validated`); `pinned` from `lifecycle: pinned`; archived rows from the ledger's last event per path (the `hook:` field is the removed SPINE line's hook text, which is what a miss search needs to match); evidence counts by counting `- ` lines. The rebuild is therefore mechanical and the checker (C2) asserts the catalog equals the tree: presence of every file, evidence counts, the `pinned` flag, the `validated` date, `from` and `hook` on archived rows with the hook equal to the ledger's `spine-entry` hook, ledger last-event agreement with the tree, and a `rebuilt:` stamp no older than the newest ledger event.

The SPINE carries exactly one fixed line pointing at the catalog. No list of archived names ever enters the SPINE; this supersedes the shared "Archived projects: a, b, c" line proposed in #73.

### D5. Scoped misses: the catalog bounds what "not found" means

Retrieval protocol on a miss, added to `distill-monitor.md`:

1. No SPINE hook matches the topic. Search `CATALOG.md` for the topic's distinctive words (archived rows carry the original hook, so a project archived last month still matches on its own nouns).
2. An archived match: read it, state "found in the archive (archived on DATE, reason R)". Read-only; no stamps change (D3).
3. No catalog match: say **"No SPINE entry or catalog line (rebuilt DATE) names X. It may still sit inside a broader file. This is not proof X was never distilled."** Never convert a miss into "we never distilled X".
4. The catalog is **stale** when any catalog line points at a missing file, when a file under the tier directories, `archive/` or `evidence/` has no catalog line, or when the newest ledger event date is later than the catalog's `rebuilt:` stamp. All three are content checks that work after a sync, a copy or a checkout (modification times are not preserved by those and are never used). A stale catalog is named as such in the answer.

This is the files-only shape of #66. The model is instructed; nothing enforces the wording at runtime (section 6).

### D6. Required reading is declared, and reads are batched

Tier-2 files may declare `read_with:` in frontmatter as an **inline list** (`read_with: [ops/deploy.md, craft/testing.md]`; the block-list form is rejected by the checker so there is one shape to parse). `distill-monitor.md` gains two rules:

- After reading the SPINE, issue **all** matched tier-2 reads in one batch (parallel tool calls) when the client supports it; serialize only when a file's content decides what to read next.
- After that batch, read the union of their `read_with:` lists in one more batch. Depth is one; no transitive closure. A file that needs a deeper chain lists the deeper file directly.

A synced file may not `read_with` a path under `local/` (D9). Old arrow-style cross-references in prose stay as navigation hints. Which clients honour parallel tool calls is verified per client in #78.

### D7. Lifecycle: an enabled policy acts on eligible files without per-item questions

The policy is **opt-in** (release frame: a behaviour change ships as a knob). It is persisted in `{DISTILL_DIR}/.lifecycle` (`enabled` or `disabled`; absent means disabled), a local dotfile like `.token-saver`. When disabled, the distiller reports debt and asks nothing, which is strictly less noise than today.

When enabled, at Step 5 of every distillation and on the standalone invocation `/distill gc`:

| Rule | Detail |
|---|---|
| Activity stamp | The newest of: frontmatter `last_validated`, frontmatter `last_updated`, and every per-principle `last_validated` line in the file. A file with **no date stamp at all is ineligible** and reported |
| Eligible | A file under `projects/` whose activity stamp is older than its `staleness_threshold` (default 90 days) |
| Exempt | Frontmatter `lifecycle: pinned` (also echoed as the word "pinned" in the SPINE hook so old clients' staleness review sees it); any file carrying a `[NON-NEGOTIABLE]` marker (treated as pinned and reported as such, because a safety rule must stay in the retrieval path even when its project is quiet); any file outside `projects/` (craft, ops, profile, feedback keep ask-first, because a stale principle is not a finished project). Users pin before the first pass by adding `lifecycle: pinned` to a file; the policy is off by default and previews before applying, so there is always a run to read the plan and pin |
| Blocked | A file named in another active file's `read_with:`, or whose path appears in the prose of any active file (arrow references, F9). The reason is recorded in `data/lifecycle.jsonl` and in the report; nothing moves |
| Action | Ledger line first (D3, including the full SPINE entry), then the byte-identical move, then the SPINE entry removal, then the catalog rebuild. The report lists every move; a move of a file carrying `[NON-NEGOTIABLE]` or `[DIRECTIVE]` markers is listed with the marker count |
| Manifest | `data/lifecycle/<ts>.json` lists every planned move with its source sha256 and a per-move `done` flag; it is written before the first move. A later run that finds an unfinished manifest **verifies each remaining source against its recorded sha256** and completes only exact matches; a mismatch (for example a stub an old client re-created at the source path) stops the run and is reported. Reverting uses the ledger line to re-add the SPINE entry |
| Concurrency | gc runs under the `.status` lock, refreshes it after every move (F10's 5-minute staleness), and refuses to start while another unfinished manifest exists |
| Restore | `/distill restore <path>` appends a `restore` ledger line, moves the file back, checks the ledger checksum (restore anyway on mismatch, report it), re-adds the saved SPINE entry **subject to D1**: if the saved entry is over the entry cap (an entry archived during migration was saved before compaction), it is cut to the cap and the cut wording is appended to the restored file under `## Index detail`, then the catalog is rebuilt. A restore never finishes with the SPINE over budget |
| Preview | `/distill gc --preview` prints the plan and changes nothing; `--apply` executes it. Preview is the default |

Demotion is not a claim that the project ended. Age alone never means that; the move only says "not validated within threshold, kept whole in cold storage, findable through the catalog". **Maintenance reads are exempt from validate-on-recall**: eligibility scans, migration and gc read files without bumping any stamp, otherwise a migration would reset every clock on the same day. Reads without validation stay unobserved and count as unknown, not as inactivity; that is why only `projects/` files are eligible and the threshold is per file.

`[DIRECTIVE]` markers do not block a move, because a move preserves wording verbatim (F7 forbids dropping or compressing, not relocating), and a directive-bearing project file is retrievable through D5 the next time its project comes up; the move is listed with its marker count in the report. `[NON-NEGOTIABLE]` markers exempt the file (row above): that is the one place where an archive would weaken a safety property rather than a budget, so it is not automated. **Directive applicability** (who issued it, whether it has expired) is preserved as the existing `origin: directive (who, when)` wording and is otherwise deferred to Track B (#82), see section 8.

### D8. Version line: additive, stays on 1.x, with named mixed-version outcomes

Everything above adds files, directories and frontmatter fields. No existing file format changes, no existing path moves except through the explicit lifecycle action, and the SPINE format is unchanged apart from being shorter and carrying one catalog line. This ships in the files-only compatibility line, not as a major. If #78 finds it must change an existing format after all, the major-review gate from #76/#79 applies.

A client on the **current** instructions against a redesigned store keeps working, with these named outcomes:

| Old-client behaviour | Outcome on a redesigned store | Handled by |
|---|---|---|
| Ignores `evidence/`, `CATALOG.md`, `archive/LEDGER.md`, `.lifecycle` | Nothing breaks; the catalog goes stale until the next new-client run | D5 step 4 reports staleness |
| File compaction rewrites content into a flat `archive/<name>.md` (F4) | A `legacy` archive file appears | D3 legacy rule; catalog labels it |
| Staleness review archives a pinned file after a "no" | The pin is visible in the SPINE hook, so the question shows it; if the user still says no, the old client rewrites the file into a flat archive (legacy) | Documented; restore is manual for legacy files |
| Integrity check sees a dangling SPINE pointer left by an interrupted gc and re-creates a stub at the source path | The new client's recovery finds a sha256 mismatch, stops, reports | D7 manifest rule |
| Bumps `last_updated` after "still relevant" | Counts as activity (the stamp rule takes the newest of all stamps) | D7 |
| Validate-on-read bumps a stamp inside an archived file | Restore reports a checksum mismatch and restores anyway | D3 |

### D9. Sync classification of new and existing paths

| Path | Sync set (#61) | Reason |
|---|---|---|
| `evidence/**` | shared | knowledge |
| `archive/**` including `archive/LEDGER.md` | shared, **byte-exact** | knowledge and its provenance; checksums are over raw bytes, so #61 and every backup plugin must transfer these without line-ending normalisation |
| `CATALOG.md` | shared | derived, cheap, useful offline; on conflict, rebuilt from the tree and the ledger |
| `local/**` | never (structural, per #61) | machine-local overlay with its own `local/SPINE.md`; **excluded from the catalog and from gc**; a synced file may not `read_with` into it; a miss answer that consulted `local/SPINE.md` says so |
| `.lifecycle` | local | per-machine choice, like `.token-saver` |
| `data/lifecycle.jsonl`, `data/lifecycle/*.json`, `data/migration/**` | local | diagnostics and recovery manifests |

## 3. Migration of an existing store

Run once by the distiller as `/distill migrate-store`, under the `.status` lock. Preview is the default; `--apply` executes.

1. **Preview.** Write `data/migration/<ts>/PLAN.md`: proposed SPINE (every entry within D1 caps, with the wording each cut entry will append to its target file), the list of lines per tier-2 file that would move to its evidence twin, the lifecycle plan if `.lifecycle` is enabled, and the three budget numbers before and after. The plan also lists **every path it will create or move**. Nothing else changes.
2. **Backup.** On `--apply`, copy `SPINE.md` and every tier-2 file into `data/migration/<ts>/backup/` and write `PENDING`. Only then edit.
3. **Apply, per file, marking each file `done` in the plan as it completes.** For each tier-2 file: append the planned lines to `evidence/<tier>/<name>.md`, skipping any line already present verbatim (idempotent append), then rewrite the principle file, then mark done. Rewrite the SPINE from the plan and append cut wording to the target files. Create `CATALOG.md`. Perform lifecycle moves only if enabled (D7 rules, ledger first). Run the lossless self-check (section 5) and, only if it passes, delete `PENDING` and write `DONE` with the three numbers.
4. **Interrupted.** A later run that finds `PENDING` offers two mechanical choices. **Finish**: resume at the first file not marked done (the idempotent append makes a half-done file safe). **Revert**: append one `restore` ledger line (`reason: revert <manifest>`) per move being reversed, reverse every move listed in the plan, delete every path the plan created (the ledger is never deleted, only appended to), then copy `backup/` over the store. Both are copies, appends and deletions from the plan, not judgement.
5. **Repeated.** Running migration on a migrated store is a no-op plan (no entry over cap, no evidence lines left in principle files) and says so.
6. **Manual edits.** Users may edit any file at any time. The next distillation re-validates budgets and rebuilds the catalog. A user-edited SPINE over budget is compacted like any other over-budget write; cut wording goes to the target file, never dropped.
7. **Line endings.** The harness strips carriage returns when comparing and writes files with the line ending the file already had; the checker ignores `\r` everywhere.

Which lines are evidence is a **judgement the distiller makes** (dated observations, confirmation counts, session anecdotes, superseded findings). The migration therefore cannot be proven correct by the agent; it is proven **lossless** by a mechanical check: every non-blank line of every pre-migration tier-2 file must appear, **as many times as it appeared**, in its principle file, its evidence twin, its split children, or its archived copy. `tests/files-only/check-store.sh` implements exactly that check and the distiller runs the same checks before clearing `PENDING`. On Windows harnesses without a POSIX toolset the self-check needs the PowerShell twin (`check-store.ps1`, owned by #78, mandatory before #78 ships); until it exists the self-check is bash-only and the design says so.

## 4. What the running harness must do (instruction changes)

| File | Change |
|---|---|
| `distill-monitor.md` | Batch reads (D6), `read_with` closure (D6), scoped-miss wording and catalog-staleness rule (D5), archived files are read-only (D3), one sentence that the catalog exists and is not loaded at start, `local/SPINE.md` consulted alongside |
| `distill-process.md` | Step 0: integrity check includes catalog freshness, evidence orphans, active/archive collisions; Step 3: write principle to the tier file, evidence lines to the twin, protected blocks kept whole; Step 4: byte-budget check with `wc -c` (or the PowerShell equivalent) and forced same-run compaction with cut wording appended to the target file; Step 5: replace "flag" and "ask" for `projects/` with D7 when enabled, ledger before move, rebuild catalog, report debt with a sign; maintenance reads exempt from validate-on-recall; new `gc`, `restore` and `migrate-store` sub-procedures |
| `distill.md` | Dispatcher accepts `gc [--preview|--apply]`, `restore <path>`, `migrate-store [--preview|--apply]`; passes them to the sub-agent without a harvest |
| `knowledge-architecture.md` | Document `evidence/`, `CATALOG.md`, `archive/LEDGER.md`, byte budgets, split and oversize, move-not-rewrite, read-only archive, the lifecycle table, the `local/` overlay |
| Client adapters (Claude rules, Codex block, Antigravity rules) | No change needed; they defer to the two files above (F12). Verified per client in #78 |
| Installers | Nothing new to download for runtime use. `.lifecycle` gets `--lifecycle / --no-lifecycle / --remove-lifecycle` and `$env:DISTILL_LIFECYCLE`, the same contract as Token Saver, in #78 |
| CI | `installer-tests.yml` runs `tests/files-only/run-files-only-tests.sh` on Linux and macOS (this PR) |

## 5. Synthetic fixture and deterministic checks

`tests/files-only/store-before/` is a mature synthetic store for a fictional persona (Noor, platform engineer) that reproduces every diagnosed failure: SPINE entries over 400 bytes that carry principles found nowhere else, a tier-2 file over 60 lines because it holds 30 dated observations, two `projects/` files past threshold (one pinned), files with `[NON-NEGOTIABLE]` and `[DIRECTIVE]` wording, a legacy flat archive file, an evidence-free file that must survive untouched. `tests/files-only/store-after/` is the same store after migration and one lifecycle pass with the policy enabled.

`tests/files-only/check-store.sh <store-dir> [--before <original-dir>]` asserts, deterministically and offline, ignoring carriage returns:

1. **C1** SPINE within D1 caps (lines, bytes, per-entry bytes); one catalog line present.
2. **C2** Every SPINE pointer resolves; every active tier-2 file has a SPINE pointer; a catalog exists and lists every active, archived and evidence file with no line pointing at a missing file; each active row's `validated` date equals the file's newest stamp and its `pinned` flag equals `lifecycle: pinned`; evidence counts in the catalog equal the `- ` lines in each twin; every `evidence_for` names an active or archived file; no path exists both active and archived; for every path named in the ledger the last event agrees with the tree; every non-legacy archived file's last `archive` event carries its sha256; archived catalog rows carry `from` and a `hook` equal to the ledger's `spine-entry` hook.
3. **C3** Every tier-2 file within D1 caps unless `oversize:`; `read_with` is an inline list whose targets exist and are not under `local/`; `split_from` targets exist.
4. **C4** (with `--before`) Every non-blank line of every original tier-2 file appears **at least as many times** in the after store (principle file, evidence twin, split children, archived copy); every protected bullet **and its indented block** still exists in an active or archived file; every archived file that is not legacy is byte-identical (sha256) to its original, and every legacy file is byte-identical to its own pre-migration copy; a pinned file was not moved; every original SPINE hook survives as a substring in `SPINE.md`, a tier file, an archived knowledge file or the catalog (never counting `data/`, evidence, or the ledger itself).

The after store exercises a **split** (`craft/testing-2.md` with `split_from: craft/testing.md` carries the index detail cut from the SPINE) so the split-family logic has a positive fixture, and the runner exercises a **restore** (atlas moved back with a `restore` ledger line, its saved entry trimmed to the cap, the cut wording appended under `## Index detail`, catalog row moved to active) for both the plain and the `restore (modified)` event, and asserts that a file carrying `[NON-NEGOTIABLE]` cannot be archived. `tests/files-only/run-files-only-tests.sh` asserts that `store-before` FAILS C1 to C3 (the diagnosis), that `store-after --before store-before` PASSES, that twelve tamper cases are caught (a modified archived file, a ledger checksum mismatch, a ledger `archive` event for a file that is still active, a dropped protected line, a protected block demoted to evidence, a lost SPINE hook, a dropped duplicate line, a lost split child, a dangling `read_with`, a block-list `read_with`, an orphan evidence file, an active/archived collision) and that an `oversize:` exemption is honoured. It runs in CI on Linux and macOS (GNU and BSD toolchains).

C4 is a **migration-time oracle**: once a later distillation folds the "Index detail" wording into proper principles, the verbatim hook no longer exists anywhere, which is intended. Without `--before` the checker has no loss oracle; steady-state loss protection is the ledger (for archives) and the evidence twins (for history), not the checker.

## 6. Honest guarantees of this edition

| Property | Files-only edition | Enforced by |
|---|---|---|
| SPINE and tier-2 budgets | Checked by the distiller at Step 4 and reported; CI checks the fixture | Instruction plus developer test. A distiller that skips the check is not stopped |
| Lossless migration and archive | Multiset line conservation and checksums the distiller runs before clearing `PENDING` | Instruction plus developer test on the fixture; the real run's check is agent-executed and bash-only until the PowerShell twin ships (#78) |
| Archive provenance survives rebuilds and sync | Written to the synced ledger at move time; catalog derives from it; last event per path must agree with the tree | File convention; verified by C2. Requires byte-exact transfer of `archive/**` (constraint on #61) |
| Catalog completeness | Deterministic rebuild recipe; C2 asserts catalog equals tree including counts | Same |
| Scoped-miss wording, read-only archive | Instruction only | Nothing at runtime; measured by #62 fresh-agent runs |
| Batching and `read_with` | Instruction only; client capability verified in #78 | Nothing at runtime; measured by #62 |
| Lifecycle atomicity | Ledger-before-move, manifest with per-move sha256 and done flags; recovery verifies before acting | Not transactional. A crash between two moves leaves a manifest a later run can finish or revert; an old client interfering is detected, not prevented |
| Activity observation | Newest of the stamps the shipped format carries; reads without validation are unknown | Cannot be improved without software (#83) |
| Concurrent distillations | Existing `.status` lock, refreshed per move by gc | Same as today |

Nothing here observes every read, guarantees a transaction, or enforces a budget against a distiller that ignores its instructions. Those are the Track B deliverables (#82, #83, #85, #86). What this edition guarantees is that the **checks exist, are one command each, and the fixture proves they catch the failures we diagnosed and the tampers the review constructed**.

## 7. Mapping to #75 acceptance criteria

| Criterion | Where |
|---|---|
| Reviewed design and synthetic before/after store establish file format, routing, evidence preservation, migration/recovery and scoped miss semantics | Sections 2, 3, 5; `tests/files-only/` |
| Dependency inventory proves no new end-user executable/service/account/connector | Section 4 last rows; the only new artefacts are markdown files, frontmatter fields and dispatcher arguments; the check scripts are developer-side |
| Agent-managed limitations explicit | Section 6 |
| Correctness-blocking format and compatibility questions resolved before implementation | D1 to D9 and D8's outcome table; section 8 lists what remains and who owns it |
| Design maps first-release work to #41, #64, #73 and #78 | Section 4 and the decision headers |

## 8. Open questions (none blocking implementation)

| Question | Owner | Exit |
|---|---|---|
| Final cap values (16 KB / 400 B / 6 KB) | #62 | Adjusted from measured coverage and latency; the checker takes them as parameters |
| Does `read_with` depth one cover real fan-out scenarios? | #62 | Fan-out scenarios keep required-fact coverage with two read rounds |
| Default for `.lifecycle` at install | Ivan | Off is the release-frame default; on requires a documented-consequences line in the installer |
| Heuristics for classifying evidence lines during migration | #78 | Fixture plan matches what a fresh agent produces on the before store |
| PowerShell twin of the self-check | #78 | `check-store.ps1` byte-parity with the bash checker on the fixture |
| Whether Codex and Antigravity honour parallel reads | #78 | Verified per client, wording adjusted where they cannot |
| Directive applicability and expiry beyond `origin: directive (who, when)` | #82 (Track B) | Stable IDs and applicability fields; files-only preserves wording and origin only |

## 9. Review record

An adversarial clean-context review of the first draft returned 1 FATAL, 11 BLOCK, 14 FLAG and 3 NOTE findings. All were folded in: the synced ledger (D3) replaces catalog-only provenance and saves the removed SPINE line; the activity stamp is the newest of the stamps the shipped format carries (D7); cut SPINE wording goes to the target file, not to evidence (D1); migration keeps a plan of created and moved paths so revert is a real revert and finish is idempotent (section 3); recovery verifies sources by checksum (D7); archives are read-only and legacy flat archives are labelled (D3); references are validated and collisions forbidden (D2, D3); oversize files split (D1); F1, F4, F8 and D8 were corrected against the code; the checker gained multiset conservation, protected-block protection, a scoped hook search, CRLF and BSD-sed tolerance, `evidence_for` and collision checks, count checks and legacy handling, and is now in CI. Accepted and named risks are in section 6.

The independent PR review per `REVIEW-PROTOCOL.md` (clean worktree, no shared context) returned REQUEST CHANGES with one BLOCK: ledger event semantics were unspecified (revert and restore line formats, last-event derivation, no ledger-to-tree check), so a crash between the ledger write and the move, or a revert, produced a state the checker blessed. Resolved in D3 (event table, last-event rule, `move never completed` repair), D4 and C2 (catalog fields and ledger agreement checked), a new tamper case, and the byte-exactness constraint on #61. Its flags were also applied: content-based catalog staleness (D5), the stray `evidence:` frontmatter key removed from the fixture, a positive split fixture and an oversize exemption case, the ledger hash derived at runtime in the runner, the hook search no longer counting the ledger, and the steady-state limitation stated in section 5. The review text is recorded on the pull request. The second round returned REQUEST CHANGES on one composition gap: restore re-added the saved SPINE entry verbatim, which for an entry archived during migration is over the D1 cap, so the checker rejected the documented procedure. Resolved by making restore subject to D1 (D3, D7) with positive restore fixtures for two ledger events, plus its flags: catalog `rebuilt:` checked against the newest ledger event, append-then-split ordering stated (D1), how to pin before the first pass, F13 corrected, restore-on-request named as the successor of `recall_count` promotion, and `[NON-NEGOTIABLE]` files exempted from automatic demotion (D7).
