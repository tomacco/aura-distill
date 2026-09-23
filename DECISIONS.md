# Decisions

A log of decisions that shape how aura-distill is built and released. Newest first.
Each entry names who decided and on what basis, so it can be revisited when the context changes.

Origin tags: `directive` (decided by the maintainer), `evidence` (decided by measurement or review),
`convention` (arbitrary but agreed), `constraint` (forced by something outside the project).
Status: `active`, `provisional` (made by an agent during an autonomous run — reversible, flag it if it looks wrong), `superseded`.

Issues own live status and blockers. `ROADMAP.md` owns scope and sequence. This file owns *why*.

---

## 2026-09-23 — Release channels (#79)

**D-2026-09-23-9 · Beta installs and updates come from a tag named by a manifest on `beta/1.2`.** `provisional` (authoring agent, #79; ADR 0002)
The beta payload is always a pinned prerelease tag; the moving branch only hosts the one-line pointer. Rejected: raw files from the branch (every merge would ship), the Releases API (rate limits, "latest" could be a v2), Pages (served from `main`). Consequence: `beta/1.2` must never be deleted or renamed while beta installs exist.

**D-2026-09-23-10 · Updating is a script; the dispatcher prose only runs it.** `provisional` (authoring agent, #79; ADR 0002)
`bin/distill-update.sh` makes every safety decision from fetched content and its own line major, never from `.version` or from model judgement. The prose forbids improvised downloads, but no guarantee depends on the prose.

**D-2026-09-23-11 · The manifest never carries `software.base`, and `main/VERSION` is the only stable version.** `provisional` (authoring agent, #79; amends ADR 0001)
The files-only line only ever learns a software edition's version, requirements and guide.

---

## 2026-09-23 — Files-only memory design

**D-2026-09-23-8 · The files-only edition follows the design in `docs/design-files-only-memory.md`, decisions D1–D10.** `evidence` · provisional (agent design, reviewed on PR #93)
Byte and line budgets checked at write time (D1), evidence twins (D2), archive as a byte-identical move recorded in a synced ledger (D3), a complete catalog (D4), scoped misses (D5), `read_with` and batched reads (D6), an opt-in lifecycle policy (D7), the 1.x version line (D8), sync classification (D9) and contained paths (D10). The design doc owns the detail; this entry records that it is the adopted basis for #78. Evidence: the diagnosis in #73 and measured aggregates of real stores (design F15). Revisit if #62's measurements move the caps or #78 finds a decision it cannot implement without a format change.

**D-2026-09-23-12 · The store checker ships as an optional runtime helper; the model-executed checklist is the fallback.** `evidence` · provisional (authoring agent, #78)
The design had the checker stay developer-side and the runtime self-check be bash and PowerShell command blocks written into `distill-process.md`, proven equal to the checker on the fixture. #78 instead moves the checker to `bin/distill-check-store.sh`, has the installers copy it to `{DISTILL_DIR}/bin/`, and lets the distiller run it when bash is available (it also prints the catalog and the checksums, so those are mechanical too). One implementation means the runtime and CI check the same invariants by construction, where two hand-written command blocks would drift. It is optional: nothing requires bash, and without it the distiller follows the same invariants as a checklist and reports that it did. Cost: no PowerShell twin, so bash-less Windows gets the agent-executed path (a named known risk), and the #79 updater does not yet fetch the helper. The installer already needs bash or PowerShell; no new runtime, daemon or account is introduced. Revisit if the updater cannot carry the helper, or if #62 shows the checklist path is common.

**D-2026-09-23-13 · #78 resolutions of the #93 handoff.** `evidence` · provisional (authoring agent, #78)
(1) The ledger's "newest event decides" is the last line in the file, and the checker fails a line dated before the one above it, so append order and date order cannot disagree; a #61 merge must interleave by timestamp. (2) Lines carrying any retrieval marker (`[UPDATED…]`, `[DEPRECATED…]`, `[CORRECTED…]`, `[IMPORTANT…]`, `[CONTEXT…]`, `[PROVISIONAL…]`) are protected like `[NON-NEGOTIABLE…]` and `[DIRECTIVE…]`: never only in evidence. (3) Restoring a legacy archive copies it to its `archived_from:` path and leaves the legacy file in place; the existing "archive file deleted" check covers it. (4) `recall_count` bumps by 1.1 clients are tolerated through an additive `sha256-norm:` ledger field. (5) Installers create every new store in the files-only layout (an empty `CATALOG.md` and the SPINE's catalog line), so a new user is never "unmigrated". A store with no `CATALOG.md` but existing knowledge files predates 1.2: ordinary distillations report its budgets instead of compacting it, so its first large rewrite always goes through `migrate-store` with a preview and a backup. An empty store without a catalog (a manual install) is treated as new. (6) `restore` stamps `last_updated`, because a user asking for a file back is an activity observation and the next gc would otherwise re-archive it. (7) Round-one review (#114): signals harvested during an interrupted migration have one handler, the sub-agent, which queues them as one inbox item on every client; gc state lives in `data/gc-log.jsonl` and `data/gc-manifests/`; the SPINE compacts toward the 12,000-byte / 60-line target and must not finish above the 16,000-byte / 80-line caps; `local/SPINE.md` may point only inside `local/`; revert keeps files changed after the backup. Revisit (5) if users never run the migration.

## 2026-09-23 — Review convergence

**D-2026-09-23-7 · Reviews converge in at most three rounds, reviewers differ from the author's model, resolutions are traceable, and the reviewer's environment carries no author context.** `evidence` · provisional (agent proposal under D-6, adopted through a reviewed PR)
REVIEW-PROTOCOL.md rules 6–9; the review runs through `tests/review/run-clean-review.sh` in a separate reviewer profile, with the Agent tool as a disclosed fallback (#108). Evidence: PR #93 had six review rounds, each REQUEST CHANGES with new blocks. PR #92 needed three rounds, and one of them caught a finding that had been "routed" only in a PR comment and never reached the target issue. The round-two reviewer of #104 disclosed that its session had auto-loaded the maintainer's knowledge store, which held the proposal under review. Revisit if a capped round ships a defect that a fourth round would have caught.


## 2026-09-23 — Release and autonomy frame for the files-only edition

**D-2026-09-23-1 · Beta is an opt-in prerelease, not a merge to main.** `directive` · active
Track A ships first as `v1.2.0-beta.N`: a GitHub prerelease installable only with an explicit beta
opt-in. `main`, the Homebrew tap and every existing auto-updater stay on 1.1.x until the maintainer
promotes the beta. Reason: legacy updaters fetch fixed URLs on `main` (docs/adr, #76), so a merge to
`main` *is* a release to every installed user.

**D-2026-09-23-2 · Agents merge reviewed work into `beta/1.2`; only the maintainer merges to `main`.** `directive` · active
A PR may be merged into the `beta/1.2` integration branch by an agent once it has passed the
independent review in `REVIEW-PROTOCOL.md` and its test suites. Promotion of `beta/1.2` to `main`
is the maintainer's call.

**D-2026-09-23-3 · Docs-only changes may go to `main` to publish Pages.** `directive` · active (proposed by an agent; confirmed by the maintainer on 2026-09-23: "Docs only can be merged to main, makes sense")
GitHub Pages serves `main:/docs`, so a research or release page is only public once it is on `main`.
A PR that touches only `docs/**` and `CHANGELOG.md` changes nothing an updater fetches, so an agent
may merge it after review. It still triggers a patch version bump (bump-version.yml does not ignore
`docs/**`). Revisit if the maintainer wants Pages from a separate branch instead.

**D-2026-09-23-4 · Real data on public pages is aggregate only.** `directive` · active
Research may measure copies of real knowledge stores and transcripts. Published output contains only
counts, sizes, ratios and pass/fail — no file names, no content, no quotes, no project or session
identifiers. The same rule as the local-models study. Measurement always runs on copies; nothing
writes to a real store (AGENTS.md "Never touch real user data").

**D-2026-09-23-5 · Every version gets its own release page, in the NAST editorial style, EN + ES.** `directive` · active
Starting with 1.2.0-beta.1, each release publishes `docs/releases/<version>/` on GitHub Pages.
Visual system: the monochrome editorial style of nast.tomac.co (Unbounded + Archivo), read-only
reference, no NAST branding. Pages are mobile first, conclusion first, plain language, with a
Spanish version selected by browser locale. Existing research pages keep their current style.

**D-2026-09-23-6 · Autonomy grows with method, not with manual review.** `directive` · active
The maintainer no longer reviews every step. Quality comes from protocols that run on their own
(independent PR review, adversarial design review, measurement preregistration, release gates) and
from agents looking for gaps in the instructions and observations. Proposed changes to the method
are made as reviewed PRs, marked `provisional`, and reported on the run status page.
