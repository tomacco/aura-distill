# Decisions

A log of decisions that shape how aura-distill is built and released. Newest first.
Each entry names who decided and on what basis, so it can be revisited when the context changes.

Origin tags: `directive` (decided by the maintainer), `evidence` (decided by measurement or review),
`convention` (arbitrary but agreed), `constraint` (forced by something outside the project).
Status: `active`, `provisional` (made by an agent during an autonomous run — reversible, flag it if it looks wrong), `superseded`.

Issues own live status and blockers. `ROADMAP.md` owns scope and sequence. This file owns *why*.

---

## 2026-09-23 — Release channels (#79)

**D-2026-09-23-8 · Beta installs and updates come from a tag named by a manifest on `beta/1.2`.** `provisional` (authoring agent, #79; ADR 0002)
The beta payload is always a pinned prerelease tag; the moving branch only hosts the one-line pointer. Rejected: raw files from the branch (every merge would ship), the Releases API (rate limits, "latest" could be a v2), Pages (served from `main`). Consequence: `beta/1.2` must never be deleted or renamed while beta installs exist.

**D-2026-09-23-9 · Updating is a script; the dispatcher prose only runs it.** `provisional` (authoring agent, #79; ADR 0002)
`bin/distill-update.sh` makes every safety decision from fetched content and its own line major, never from `.version` or from model judgement. The prose forbids improvised downloads, but no guarantee depends on the prose.

**D-2026-09-23-10 · The manifest never carries `software.base`, and `main/VERSION` is the only stable version.** `provisional` (authoring agent, #79; amends ADR 0001)
The files-only line only ever learns a software edition's version, requirements and guide.

---

## 2026-09-23 — Review convergence

**D-2026-09-23-7 · Reviews converge in at most three rounds, reviewers differ from the author's model, resolutions are traceable, and the reviewer's environment carries no author context.** `evidence` · provisional (agent proposal under D-6, adopted through a reviewed PR)
REVIEW-PROTOCOL.md rules 6–9. Evidence: PR #93 had six review rounds, each REQUEST CHANGES with new blocks. PR #92 needed three rounds, and one of them caught a finding that had been "routed" only in a PR comment and never reached the target issue. The round-two reviewer of #104 disclosed that its session had auto-loaded the maintainer's knowledge store, which held the proposal under review. Revisit if a capped round ships a defect that a fourth round would have caught.


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

**D-2026-09-23-3 · Docs-only changes may go to `main` to publish Pages.** `provisional` (agent reading of D-2 plus the maintainer's request to publish research and release pages)
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
