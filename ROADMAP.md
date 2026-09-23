# Aura Distill roadmap

Execution plan agreed 2026-09-10, refreshed 2026-09-23. Program: [#74](https://github.com/tomacco/aura-distill/issues/74).

This document describes planned work. It does not describe shipped behavior or measured speedups, and it promises no dates or speed multipliers.

Three places hold the plan, each with one job:

- **This roadmap** owns scope, release order, decision gates and what happens to the existing backlog.
- **GitHub issues** own live status, acceptance criteria and the native "blocked by" links.
- **[DECISIONS.md](DECISIONS.md)** owns why: who decided what, and on what basis.

A PR that changes scope or dependencies updates the roadmap and the affected issues together. [NEXT-STEPS.md](NEXT-STEPS.md) is an older plan (2026-06-03), kept as history; this roadmap supersedes it.

## Release contract

1. **Deliver a files-only redesign first.** At runtime, Aura keeps working through plain files and the capabilities the user's harness already supports. The redesign adds no new required executable, runtime, daemon, database, background process, MCP connection, cloud account or network dependency. Tools that only developers use for testing are not user requirements.
2. **Keep a supported files-only channel.** Some users are on managed laptops where they cannot install unapproved software, and we do not know how many installations exist. Staying on files-only remains a supported choice after the software edition ships.
3. **The software layer is a semver major.** From the current 1.x line the next major is expected to be 2.0.0; verify at release time. If discovery finds that the files-only format change is itself incompatible, it follows the same major-release rules. An incompatible change is never shipped as a minor release.
4. **Warn before side effects and require explicit adoption of a major.** Users are asked to read and understand the requirements and migration guide first. Having enabled auto-update does not count as approval of a new runtime, service, permission or data flow. Declining, deferring, pinning files-only, or not answering all keep the user on files-only. An unattended run cannot give consent.
5. **Protect the updaters already installed.** Today, when auto-update is on, installed copies fetch `main/VERSION` and the updater-owned files from `main`. A gate that ships only in a new installer cannot protect old clients that never run it. Before any software payload is published at a historical URL, the released update paths are audited, safe endpoints and publication order are chosen, and clients that skipped releases are tested.

This is a compatibility requirement. It does not claim that any company permits or forbids Aura. Do not bypass company controls. Honoring the requirement does not need install telemetry.

## Release frame (2026-09-23)

The maintainer set how the files-only edition ships ([DECISIONS.md](DECISIONS.md), D-2026-09-23-1 to -5):

- **Track A ships first as an opt-in prerelease**, `1.2.0-beta.N`, built from the `beta/1.2` branch. It installs only with an explicit beta opt-in.
- **`main`, the Homebrew tap and every existing auto-updater stay on 1.1.x** until the maintainer promotes the beta. Legacy updaters fetch fixed URLs on `main`, so merging to `main` is a release to every installed user.
- **Agents merge reviewed PRs into `beta/1.2`** once they pass the independent review in [REVIEW-PROTOCOL.md](REVIEW-PROTOCOL.md) and their test suites. Only the maintainer merges `beta/1.2` into `main`.
- **Every version gets its own release page** under `docs/releases/<version>/`, starting with 1.2.0-beta.1.
- **[#80](https://github.com/tomacco/aura-distill/issues/80) is the promotion gate.** Promoting the beta to a stable release on `main` requires #80's evidence.

## Evidence since planning

A measurement on copies of one real knowledge store (aggregate numbers only, per D-2026-09-23-4) supports the Track A direction:

- The auto-loaded index is 49–51 KB, 3.1–3.2× its 16 KB budget. 44 of 65 index entries are over 400 bytes.
- Index bytes grew 57% in seven weeks while the number of entries stayed flat. Entries are growing into digests, not multiplying.
- Dated observations are about 6.5% of tier-file content. Splitting oversized entries, not adding separate evidence copies, is the main remedy.
- The lifecycle rules as drafted would archive 2 files. Cross-reference blocking protects 18 of 23 project files.
- 18 nested legacy archives have no ledger entry. As things stand they would block migration, so migration needs a path for them.

Details: [files-only redesign research](docs/research/files-only-redesign.html) (being published).

## Start here

- [#75](https://github.com/tomacco/aura-distill/issues/75): decide the files-only structure, migration and honest guarantees. Delivered for review as PR #93 (review requested changes; not yet merged).
- [#76](https://github.com/tomacco/aura-distill/issues/76): audit legacy updater paths and choose safe release channels. Delivered as PR #94 and [ADR 0001](docs/adr/0001-legacy-updater-compatibility.md); merged into `beta/1.2`, and PR #94 stays open against `main` until promotion.
- [#77](https://github.com/tomacco/aura-distill/issues/77): review the latency and quality protocol. [#62](https://github.com/tomacco/aura-distill/issues/62) then builds the harness and a fresh baseline.
- [#65](https://github.com/tomacco/aura-distill/issues/65): diagnose, as independent work, whether the shared corpus and scopes really diverge. Knowledge intentionally kept local-only must stay excluded.
- [#41](https://github.com/tomacco/aura-distill/issues/41): thin-index work can start now; agree the final format with #75. Batching reads ([#64](https://github.com/tomacco/aura-distill/issues/64)) follows the file contract and the benchmark baseline.

Service discovery ([#81](https://github.com/tomacco/aura-distill/issues/81)) may proceed once the file contract is decided. Every service implementation story is blocked, directly or indirectly, by the files-only release gate [#80](https://github.com/tomacco/aura-distill/issues/80). The first deliverable does not wait for a database, service, connector or automatic statistics.

## Track A: files-only architecture

Keep durable evidence (dated observations, sources) apart from the short operational knowledge an agent reads every session, using files and references between them. Give archived knowledge a place where agents can still find it. Keep startup navigation within a size budget. Keep directives attached to the context they apply to. Define lifecycle actions (demote, archive, restore) that can be reversed and that run only when the user's policy enables them. When activity data is missing, it is recorded as unknown, not guessed.

The user's harness still runs the procedure, so this edition cannot promise transactions, enforced budgets or automatic tracking of every read. Developer checks and fresh-agent tests validate what actually happens. [#75](https://github.com/tomacco/aura-distill/issues/75) and [#78](https://github.com/tomacco/aura-distill/issues/78) state these limits.

Order of work:

1. Decide the file contract (#75), then implement the redesign (#78) together with lifecycle ([#73](https://github.com/tomacco/aura-distill/issues/73)), the thin index (#41) and batched reads (#64).
2. In parallel, the updater audit (#76) leads to the upgrade guard ([#79](https://github.com/tomacco/aura-distill/issues/79)).
3. Both lines end at the release gate #80. It requires an actual supported release, recovery guidance, measured retrieval behavior and verified protection for legacy upgrades.

### Upgrade safety and distribution channels

#79 must cover every way Aura reaches users, not just `install.sh`:

- `install.sh` (macOS/Linux) and `install.ps1` (Windows).
- The Homebrew tap, repository [tomacco/homebrew-aura-distill](https://github.com/tomacco/homebrew-aura-distill). It is still pinned to 1.0.0, whose installer writes to the legacy `~/.claude/distill` while the in-place updater reports 1.1.x ([#95](https://github.com/tomacco/aura-distill/issues/95)). This is the kind of drift #76 and #79 exist to prevent.
- The in-place `/distill` updater, which fetches from `main`.

## Track B: software layer, separate major

This design brings back a local service, which [ARCHITECTURE-V2.md](ARCHITECTURE-V2.md) records as abandoned in v0.6.0 (2026-05) because files were simpler, sufficient and easier to test. [#81](https://github.com/tomacco/aura-distill/issues/81) must state what has changed since then, with evidence, before any Track B implementation starts.

The service receives the task's intent and returns the knowledge that applies, with source and version references, scope, freshness, and whether the size budget was met. It owns indexing, following dependencies between files, validating proposed changes, keeping stored data intact, and operation statistics. The working model still interprets knowledge and proposes learnings. A bounded synthesis step answers semantic questions. Ordinary retrieval does not need a second model call.

The ADR in #81 decides runtime, storage, what is canonical versus derived, deployment and offline behavior. No database or ranking technology is chosen in advance. It reuses the shared-server authority and compare-and-swap writes (CAS: a write succeeds only if the stored version is still the one the writer read) from [#61](https://github.com/tomacco/aura-distill/issues/61); git stays an optional backup. Local-only knowledge stays local everywhere: data, queries, metadata, traces, caches and exports.

After Track A releases, the order is: storage and telemetry, then the read and write contracts, then compact views, lifecycle and the CLI/MCP transports, then client rollout, then migration, then the release gate [#90](https://github.com/tomacco/aura-distill/issues/90). The write path (#85) builds the simplest view builder it needs to finish on its own: deterministic and lossless. The later compactor (#86) builds on that same interface. Transport contract tests pass before interactive rollout. Users can always inspect the exact source files.

Users are offered the software major only through #79. The guard closes in Track A, tested against a complete synthetic manifest and guide for a future major. Client rollout ([#88](https://github.com/tomacco/aura-distill/issues/88)) and final verification must check the real, final requirements and guide before offering the major. Client rollout can close using a stub of the migration interface. The real cutover, export after cutover, and rollback belong to [#89](https://github.com/tomacco/aura-distill/issues/89). A backup taken before migration cannot preserve writes made after it.

## Execution graph

"Blocked by" means the prerequisite is delivered before implementation of that story starts. Read-only planning may happen earlier. Stages are numbered in dependency order: every blocker sits in an earlier stage.

- [#62](https://github.com/tomacco/aura-distill/issues/62) closes on the harness and a fresh baseline with a stub where the service will plug in; the final service comparison belongs to #90.
- [#63](https://github.com/tomacco/aura-distill/issues/63) and [#66](https://github.com/tomacco/aura-distill/issues/66) close on contract and stub tests, so the stories that use them can follow without circular dependencies.
- Optional research [#91](https://github.com/tomacco/aura-distill/issues/91) blocks neither release.

| Stage | Work | Blocked by |
|---|---|---|
| A0 Discovery | [#75](https://github.com/tomacco/aura-distill/issues/75) Files-only memory redesign for restricted environments (PR #93) | Ready |
| A0 Discovery | [#76](https://github.com/tomacco/aura-distill/issues/76) Audit legacy auto-updaters (PR #94, in `beta/1.2`) | Ready |
| A0 Discovery | [#77](https://github.com/tomacco/aura-distill/issues/77) Preregister retrieval latency and quality comparisons | Ready |
| A1 Foundations | [#41](https://github.com/tomacco/aura-distill/issues/41) Thin legacy SPINE | Ready; agree format with #75 |
| A1 Foundations | [#62](https://github.com/tomacco/aura-distill/issues/62) Retrieval benchmark: natural-batching baseline | #77 |
| A1 Foundations | [#73](https://github.com/tomacco/aura-distill/issues/73) Files-only reversible demotion and evidence preservation | #75 |
| A1 Foundations | [#79](https://github.com/tomacco/aura-distill/issues/79) Legacy-safe channels and explicit review before a major | #76 |
| A2 Implementation | [#64](https://github.com/tomacco/aura-distill/issues/64) Batch applicable reads in files-only clients | #75, #62 |
| A2 Implementation | [#78](https://github.com/tomacco/aura-distill/issues/78) Ship the files-only redesign | #75, #62 |
| A3 Release gate | [#80](https://github.com/tomacco/aura-distill/issues/80) Files-only release; beta promotion gate | #78, #73, #41, #64, #79 |
| B0 Discovery | [#81](https://github.com/tomacco/aura-distill/issues/81) Memory-service boundary, authority, read/write contracts | #75 |
| B1 Foundations | [#82](https://github.com/tomacco/aura-distill/issues/82) Versioned storage and a rebuildable complete catalog | #81, #77, #80 |
| B1 Foundations | [#83](https://github.com/tomacco/aura-distill/issues/83) Local retrieval traces and honest usage statistics | #81, #77, #80 |
| B2 Core contracts | [#63](https://github.com/tomacco/aura-distill/issues/63) Resolve required-reading dependencies in the service | #82, #62 |
| B2 Core contracts | [#66](https://github.com/tomacco/aura-distill/issues/66) Scoped retrieval misses | #82, #62 |
| B2 Core contracts | [#85](https://github.com/tomacco/aura-distill/issues/85) Atomic writes with validation, provenance and conflict recovery | #82, #83 |
| B3 Read path and views | [#84](https://github.com/tomacco/aura-distill/issues/84) Budgeted knowledge bundle in one operation | #82, #83, #62, #63, #66 |
| B3 Read path and views | [#86](https://github.com/tomacco/aura-distill/issues/86) Compact views that keep evidence and directive context | #85, #63 |
| B4 Transports | [#87](https://github.com/tomacco/aura-distill/issues/87) CLI and MCP transports with scope/version parity | #84, #85, #63, #66, #61, #65 |
| B5 Client rollout | [#88](https://github.com/tomacco/aura-distill/issues/88) Service adapters and installers with opt-in adoption | #87, #79 |
| B6 Migration | [#89](https://github.com/tomacco/aura-distill/issues/89) Migrate Markdown stores with dry run and rollback | #86, #88, #73 |
| B7 Release gate | [#90](https://github.com/tomacco/aura-distill/issues/90) Speed, quality and lifecycle safety end to end | #62, #84, #85, #86, #87, #88, #89, #73 |
| Later | [#91](https://github.com/tomacco/aura-distill/issues/91) Smarter retrieval routing, only against measured misses | #90 |
| Independent | [#65](https://github.com/tomacco/aura-distill/issues/65) Corpus/scope divergence across local and MCP retrieval | Ready |

The existing productization gate in #61 also blocks the service transports. Files-only use does not need it.

## Decisions before implementation

| Uncertainty | Decision owner | Evidence and exit condition |
|---|---|---|
| Files-only structure and guarantees | #75 | Synthetic before/after stores, fresh-agent interpretation, and reviewed format, lifecycle and recovery decisions. |
| Old auto-updaters bypassing a future major gate | #76 | Matrix of released update paths, reproductions of skipped releases, and an ADR on safe channels and publication order. Delivered as ADR 0001 in `beta/1.2`. |
| Retrieval speed in practice | #77, #62 | Calibrated traces, a natural-batching baseline, endpoints and thresholds fixed in advance, and an independently reviewed experiment. |
| Runtime, storage, local versus server authority | #81 | Evidence from real clients and protocols, dependency and startup tradeoffs, reviewed versioned contracts, and what changed since ARCHITECTURE-V2. |
| Pending evidence versus published memory | #81, #85 | An explicit state machine for acknowledgement, visibility and retry; crash and concurrency fixtures. |
| Complete catalog versus "nothing is known" | #66 | Exact, scoped and partial outcomes; tests for aliases, broad domains, archives and excluded scopes. |
| More sophisticated ranking | #91 | A miss class observed on held-out cases, and a full cost/quality comparison. Reject or defer if the gain is not material. |

An experiment plan does not resolve a correctness blocker. Discovery closes only when the blocking decisions are made and written into the downstream issues. Non-blocking questions may stay open as follow-ups.

## Measurement contract

Measure three editions separately: current files, redesigned files, and the later service. Earlier #62 measurements read files one at a time on purpose; keep them as historical diagnostics. The realistic baseline lets the agent batch reads naturally. Use equivalent source content and requirements, with separate experiments for transport, selection and compaction effects.

- Measure time from request to usable knowledge in the harness, whether the task was completed correctly, engine and transport time, startup and tool discovery, the number of sequential model/tool turns, context returned, retries and failures, where observable.
- Split results by cold/warm cache and local/remote transport. Pin corpus hashes, code/harness/model versions, injected instructions and cache state. Never subtract clocks from different hosts that are not synchronized.
- Before scored runs, fix in advance: quality coverage, harmful extras, what latency gain counts as practical, repetitions and sample size, uncertainty and run budget. Run a separate cheap pilot, get an independent review, and use held-out cases. Do not claim p95 precision without enough observations.
- Quality means the required facts and constraints were used, not that the same filenames were read. Rare directives, exceptions, corrections, archive recall and scoped misses must survive. A faster but incomplete answer fails.
- Use isolated synthetic personas for public fixtures; never copy live knowledge or transcripts into them. Measurements on copies of real stores publish aggregates only (D-2026-09-23-4).
- Service telemetry (#83) separates "delivered" from "shown to be useful", and maintenance or prefetch from task use. Direct file reads are not observed unless instrumented. Local diagnostics stay bounded; sharing them is a separate opt-in.
- Footprint, returned size, real model usage and billing are separate measures ([#40](https://github.com/tomacco/aura-distill/issues/40)). `kb_tokens` is the economics ledger's size estimate of all non-archived tier files (characters ÷ 4). Archiving lowers it mechanically; that alone is not a retrieval or quality win.

## Existing backlog disposition

Status as of 2026-09-23. No issue is closed just because the mechanism it proposed has changed. Original reports in reframed issues stay as history; the current execution contract takes precedence.

| Existing issue(s) | Disposition |
|---|---|
| #41, #64, #73 | Track A: thin SPINE, natural batching and files-only lifecycle. Later software enforcement belongs to #86. |
| #62 | Owns the executable benchmark and fresh baseline; the final service verdict is #90. |
| #63, #66 | Service dependency resolution and scoped misses. Files-only equivalents are part of #78. |
| #65 | Independent correctness bug. Establish the intended scope before calling anything divergent or syncing excluded data. |
| #61 | Keeps shared sync, CAS, scopes and its existing field-test gate; prerequisite for service transports. |
| [#28](https://github.com/tomacco/aura-distill/issues/28) | Separate private-tier product. Core isolation informs both designs; full classification and encryption UX does not block a release. |
| [#32](https://github.com/tomacco/aura-distill/issues/32), [#31](https://github.com/tomacco/aura-distill/issues/31), [#55](https://github.com/tomacco/aura-distill/issues/55) | Reuse the dashboard, user-reviewed diagnostics and distillation report; consume #83 when available. #55 stays under [#53](https://github.com/tomacco/aura-distill/issues/53). |
| #40 | Owns real usage and cost accounting. Missing usage data cannot block latency measurement or be replaced by footprint estimates. |
| #53, [#51](https://github.com/tomacco/aura-distill/issues/51) | Separate auto-distillation program. Service mode reuses writes and lifecycle; scheduling is not needed for either release. |
| [#56](https://github.com/tomacco/aura-distill/issues/56) | Optional session-identity optimization; coordinate hook and installer ownership. Never invent a missing session identity. |
| [#69](https://github.com/tomacco/aura-distill/issues/69), [#70](https://github.com/tomacco/aura-distill/issues/70), [#72](https://github.com/tomacco/aura-distill/issues/72), [#6](https://github.com/tomacco/aura-distill/issues/6) | Later synthesis, recurrence, absence-audit and confidence work. Keep metadata compatible; do not hide these mechanisms inside ranking. |
| [#71](https://github.com/tomacco/aura-distill/issues/71) | Separate output-enforcement boundary. Returning references to tools never authorizes running instructions embedded in them. |
| [#50](https://github.com/tomacco/aura-distill/issues/50) | Separate model-routing work; not a prerequisite for basic retrieval. Existing capability and approval controls still apply to model-based synthesis. |
| [#30](https://github.com/tomacco/aura-distill/issues/30), [#33](https://github.com/tomacco/aura-distill/issues/33) | Independent distribution metrics and last-resort telemetry. Protect unknown users without collecting install telemetry. |
| [#34](https://github.com/tomacco/aura-distill/issues/34) | Independent docs, accessibility and upstream follow-ups; token instrumentation overlaps #40, #83 and #62. |
| [#95](https://github.com/tomacco/aura-distill/issues/95) | Homebrew tap pinned to 1.0.0. Fix as part of the channel audit and upgrade guard (#76/#79): the tap is a distribution channel and must not drift from the release it claims to install. |
| [#98](https://github.com/tomacco/aura-distill/issues/98) | AGENTS.md branch convention contradicts practice for `research/` folders. Maintainer decision; independent of both tracks. |
| [#99](https://github.com/tomacco/aura-distill/issues/99) | Model-routing playbook versus new extraction evidence. Belongs with #50; not a prerequisite for either release. |
| [#102](https://github.com/tomacco/aura-distill/issues/102) / PR #103 | Worktree isolation for concurrent agents. Process safety for the autonomous runs that build this roadmap; PR #103 is open. |

Resolved since 2026-09-10:

- [#67](https://github.com/tomacco/aura-distill/issues/67) / PR #68, the Antigravity connector, merged on 2026-09-10. It is now a supported client, so installer and adapter changes in both tracks must include it.
- #48 and #49 (pre-distill marks and their benchmark) were closed as not planned.
- PR #38 (capabilities calibration) was closed without merging.
- #75 and #76 were delivered as PRs #93 and #94 (see Start here).

Open PR #39 (Time Index) is still reviewed and gated on its own. This roadmap neither merges nor requires it.

## Release decisions and maintenance

Track A closes at #80, which also gates promotion of `beta/1.2` to `main`. Track B closes at #90 with an explicit go/no-go decision, backed by quality and performance criteria fixed in advance, upgrade protection, migration, offline and rollback evidence. If a gate fails, keep the supported files-only path and open a follow-up based on the measurement. A no-go result can close an experiment; it does not complete the implementation program.

Every implementation PR references its issue and follows [AGENTS.md](AGENTS.md) and [REVIEW-PROTOCOL.md](REVIEW-PROTOCOL.md). The files-only and software-major release channels are maintained independently. Release notes say what is shipped, what is measured, what is optional and what is deferred. Never put software-major payloads on legacy endpoints before the skipped-release protection passes.
