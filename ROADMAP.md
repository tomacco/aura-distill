# Aura Distill roadmap

Execution plan agreed 2026-09-10. Program: [#74](https://github.com/tomacco/aura-distill/issues/74).

This document describes planned work, not shipped behavior or measured speedups. GitHub issues own live status, acceptance criteria and native blocking relationships. This roadmap owns release order, decision gates and the disposition of the existing backlog. Update both in the PR that changes scope or dependencies. No dates or speed multipliers are promised.

## Release contract

1. **Deliver a files-only redesign first.** Runtime use continues through files and the user's existing supported harness capabilities. No new mandatory executable, runtime, daemon, database service, background process, MCP connection, cloud account or network dependency. Developer-side test tools are separate from user requirements.
2. **Keep a supported files-only channel.** Users on managed laptops may be unable to adopt unapproved software, and installation counts are unknown. Staying on files-only remains a useful supported choice after the software edition appears.
3. **The software layer is a semver major.** The next major is expected to be 2.0.0 from the current 1.x line; verify at release. A files-only format change must also follow major-review rules if discovery finds it incompatible. Do not disguise incompatible changes as a minor release.
4. **Warn before side effects and require explicit major adoption.** Ask users to read and understand the requirements/migration guide. Existing auto-update permission does not approve a new runtime, service, permission or data-flow model. Decline, defer, pinned files-only and no response remain on files-only. Unattended runs cannot supply consent.
5. **Protect already-installed updaters.** Current repository instructions fetch main/VERSION and updater-owned files from main when auto-update is enabled. A gate shipped only in a new installer cannot protect old clients that skip it. Audit released paths, choose safe compatibility endpoints/publication order, and test skipped-release clients before publishing software payloads to historical URLs.

This is a compatibility requirement, not a claim that any particular company permits or prohibits Aura. Do not bypass company controls. No install telemetry is required to honor the requirement.

## Start here

- [#75](https://github.com/tomacco/aura-distill/issues/75): decide the files-only structure, migration and honest guarantees.
- [#76](https://github.com/tomacco/aura-distill/issues/76): audit legacy updater paths and choose safe release channels.
- [#77](https://github.com/tomacco/aura-distill/issues/77): review the latency/quality protocol. [#62](https://github.com/tomacco/aura-distill/issues/62) then implements the harness and fresh baseline.
- [#65](https://github.com/tomacco/aura-distill/issues/65): diagnose actual shared-corpus/scope divergence independently. Intentional local-only exclusion must remain excluded.
- [#41](https://github.com/tomacco/aura-distill/issues/41): thin-index work can begin now; coordinate final format with files-only discovery. Batching [#64](https://github.com/tomacco/aura-distill/issues/64) follows the file contract and benchmark baseline.

Service discovery [#81](https://github.com/tomacco/aura-distill/issues/81) may proceed once the file contract is decided. Every service implementation path is blocked transitively by the actual files-only release [#80](https://github.com/tomacco/aura-distill/issues/80). The first deliverable does not wait on a database, service, connector or automatic statistics layer.

## Track A: files-only architecture

Separate durable evidence from concise operational knowledge using files and references. Give archived knowledge a discoverable home, bound startup navigation, preserve directive applicability, and define reversible lifecycle actions under an enabled policy. Missing activity data stays unknown.

The working harness still executes the procedure. This edition cannot claim guaranteed transactions, guaranteed budget enforcement or automatic observation of every read. Developer checks and fresh-agent tests validate actual behavior. Those limits are explicit in [#75](https://github.com/tomacco/aura-distill/issues/75) and [#78](https://github.com/tomacco/aura-distill/issues/78).

Sequence: file contract -> file redesign plus [#73](https://github.com/tomacco/aura-distill/issues/73)/[#41](https://github.com/tomacco/aura-distill/issues/41)/[#64](https://github.com/tomacco/aura-distill/issues/64); updater audit -> upgrade guard; then [#80](https://github.com/tomacco/aura-distill/issues/80). That gate requires an actual supported release, recovery guidance, measured retrieval behavior and verified legacy upgrade protection.

## Track B: software layer, separate major

The service takes task intent and returns applicable knowledge with source/version references, scope, freshness and budget outcomes. It owns indexing, dependency traversal, proposed-change validation, persistence integrity and operation statistics. The working model interprets knowledge and proposes learnings; bounded synthesis resolves semantic questions. Ordinary retrieval does not require a second model call.

The ADR [#81](https://github.com/tomacco/aura-distill/issues/81) decides runtime, storage, canonical/derived boundaries, deployment and offline behavior. No database or ranking technology is preselected. Reuse shared-server authority and CAS from [#61](https://github.com/tomacco/aura-distill/issues/61), with git remaining an optional backup. Local-only knowledge stays local across data, queries, metadata, traces, caches and exports.

After Track A releases: storage and telemetry -> read and write contracts -> compact views/lifecycle and CLI/MCP transports -> client rollout -> migration -> [#90](https://github.com/tomacco/aura-distill/issues/90). Writes own the minimal deterministic lossless view builder needed for independent completion; the later compactor consumes that interface. Transport contract tests complete before interactive rollout. Exact-source inspection stays available.

Software adoption is offered only through [#79](https://github.com/tomacco/aura-distill/issues/79). The guard closes in Track A using a complete synthetic future-major manifest/guide. Client rollout and final verification must check the real finalized requirements/guide before offering the major. Client rollout can close using a migration-interface stub; real cutover, post-cutover export and rollback belong to [#89](https://github.com/tomacco/aura-distill/issues/89). A pre-migration backup alone cannot preserve later writes.

## Execution graph

“Blocked by” means the prerequisite deliverable is complete before implementation of that story. Read-only planning may happen earlier. [#62](https://github.com/tomacco/aura-distill/issues/62) closes on the harness and fresh baseline with a service stub/extension point; final service comparisons belong to [#90](https://github.com/tomacco/aura-distill/issues/90). [#63](https://github.com/tomacco/aura-distill/issues/63)/[#66](https://github.com/tomacco/aura-distill/issues/66) close on contract/stub tests so their consumers can follow without cycles. Optional research [#91](https://github.com/tomacco/aura-distill/issues/91) does not block either initial release.

| Work | Stage | Blocked by |
|---|---|---|
| [#75](https://github.com/tomacco/aura-distill/issues/75) Discovery: specify a files-only memory redesign for restricted environments | A0 - Files-only discovery | Ready |
| [#76](https://github.com/tomacco/aura-distill/issues/76) Discovery: audit legacy auto-updaters before introducing a software major release | A0 - Upgrade discovery | Ready |
| [#77](https://github.com/tomacco/aura-distill/issues/77) Discovery: preregister retrieval latency and quality comparisons before optimization | 0 - Discovery | Ready |
| [#78](https://github.com/tomacco/aura-distill/issues/78) Ship the files-only redesign: thin catalogs, preserved evidence and recoverable migration | A1 - Files-only implementation | [#75](https://github.com/tomacco/aura-distill/issues/75), [#62](https://github.com/tomacco/aura-distill/issues/62) |
| [#79](https://github.com/tomacco/aura-distill/issues/79) Protect major upgrades with legacy-safe channels and explicit review before installation | A1 - Upgrade protection | [#76](https://github.com/tomacco/aura-distill/issues/76) |
| [#80](https://github.com/tomacco/aura-distill/issues/80) Release gate: deliver the files-only architecture before software-layer implementation | A2 - Files-only release | [#78](https://github.com/tomacco/aura-distill/issues/78), [#73](https://github.com/tomacco/aura-distill/issues/73), [#41](https://github.com/tomacco/aura-distill/issues/41), [#64](https://github.com/tomacco/aura-distill/issues/64), [#79](https://github.com/tomacco/aura-distill/issues/79) |
| [#81](https://github.com/tomacco/aura-distill/issues/81) Discovery: decide the memory-service boundary, authority, and read/write contracts | 0 - Discovery | [#75](https://github.com/tomacco/aura-distill/issues/75) |
| [#82](https://github.com/tomacco/aura-distill/issues/82) Build versioned memory storage and a rebuildable complete catalog | B1 - Foundations | [#81](https://github.com/tomacco/aura-distill/issues/81), [#77](https://github.com/tomacco/aura-distill/issues/77), [#80](https://github.com/tomacco/aura-distill/issues/80) |
| [#83](https://github.com/tomacco/aura-distill/issues/83) Instrument memory operations with local retrieval traces and honest usage statistics | B1 - Foundations | [#81](https://github.com/tomacco/aura-distill/issues/81), [#77](https://github.com/tomacco/aura-distill/issues/77), [#80](https://github.com/tomacco/aura-distill/issues/80) |
| [#84](https://github.com/tomacco/aura-distill/issues/84) Retrieve a budgeted knowledge bundle from task intent in one service operation | B2 - Read path | [#82](https://github.com/tomacco/aura-distill/issues/82), [#83](https://github.com/tomacco/aura-distill/issues/83), [#62](https://github.com/tomacco/aura-distill/issues/62), [#63](https://github.com/tomacco/aura-distill/issues/63), [#66](https://github.com/tomacco/aura-distill/issues/66) |
| [#85](https://github.com/tomacco/aura-distill/issues/85) Commit proposed memory changes atomically with validation, provenance and conflict recovery | B2 - Write path | [#82](https://github.com/tomacco/aura-distill/issues/82), [#83](https://github.com/tomacco/aura-distill/issues/83) |
| [#86](https://github.com/tomacco/aura-distill/issues/86) Build compact operational views while preserving evidence and directive applicability | B3 - Maintenance | [#85](https://github.com/tomacco/aura-distill/issues/85), [#63](https://github.com/tomacco/aura-distill/issues/63) |
| [#87](https://github.com/tomacco/aura-distill/issues/87) Expose the memory contract through CLI and MCP transports with scope/version parity | B2 - Client integration | [#84](https://github.com/tomacco/aura-distill/issues/84), [#85](https://github.com/tomacco/aura-distill/issues/85), [#63](https://github.com/tomacco/aura-distill/issues/63), [#66](https://github.com/tomacco/aura-distill/issues/66), [#61](https://github.com/tomacco/aura-distill/issues/61), [#65](https://github.com/tomacco/aura-distill/issues/65) |
| [#88](https://github.com/tomacco/aura-distill/issues/88) Roll out service adapters and installers with opt-in major adoption and files-only fallback | B2 - Major client rollout | [#87](https://github.com/tomacco/aura-distill/issues/87), [#79](https://github.com/tomacco/aura-distill/issues/79) |
| [#89](https://github.com/tomacco/aura-distill/issues/89) Migrate existing Markdown stores with a dry run, source preservation and rollback | B3 - Migration | [#86](https://github.com/tomacco/aura-distill/issues/86), [#88](https://github.com/tomacco/aura-distill/issues/88), [#73](https://github.com/tomacco/aura-distill/issues/73) |
| [#90](https://github.com/tomacco/aura-distill/issues/90) Release gate: demonstrate retrieval speed, knowledge quality and lifecycle safety end to end | B4 - Release evidence | [#62](https://github.com/tomacco/aura-distill/issues/62), [#84](https://github.com/tomacco/aura-distill/issues/84), [#85](https://github.com/tomacco/aura-distill/issues/85), [#87](https://github.com/tomacco/aura-distill/issues/87), [#86](https://github.com/tomacco/aura-distill/issues/86), [#73](https://github.com/tomacco/aura-distill/issues/73), [#89](https://github.com/tomacco/aura-distill/issues/89), [#88](https://github.com/tomacco/aura-distill/issues/88) |
| [#91](https://github.com/tomacco/aura-distill/issues/91) Research: evaluate smarter retrieval routing only against measured miss classes | Later - Evidence gated | [#90](https://github.com/tomacco/aura-distill/issues/90) |
| [#62](https://github.com/tomacco/aura-distill/issues/62) Retrieval benchmark: natural-batching baseline and repeatable end-to-end service comparison | A0 - Baseline | [#77](https://github.com/tomacco/aura-distill/issues/77) |
| [#63](https://github.com/tomacco/aura-distill/issues/63) Resolve required-reading dependencies in the service without inflating SPINE | B2 - Read path | [#82](https://github.com/tomacco/aura-distill/issues/82), [#62](https://github.com/tomacco/aura-distill/issues/62) |
| [#66](https://github.com/tomacco/aura-distill/issues/66) Return scoped retrieval misses without claiming global knowledge absence | B2 - Read path | [#82](https://github.com/tomacco/aura-distill/issues/82), [#62](https://github.com/tomacco/aura-distill/issues/62) |
| [#73](https://github.com/tomacco/aura-distill/issues/73) Lifecycle: files-only reversible demotion and evidence preservation | A1 - Files-only | [#75](https://github.com/tomacco/aura-distill/issues/75) |
| [#65](https://github.com/tomacco/aura-distill/issues/65) Bug: diagnose and expose corpus/scope divergence across local and MCP retrieval | Independent correctness | Ready |
| [#64](https://github.com/tomacco/aura-distill/issues/64) Batch applicable reads in files-only clients and measure realistic retrieval | A1 - Files-only | [#75](https://github.com/tomacco/aura-distill/issues/75), [#62](https://github.com/tomacco/aura-distill/issues/62) |
| [#41](https://github.com/tomacco/aura-distill/issues/41) Thin legacy SPINE | A1 - Files-only | Ready; coordinate with [#75](https://github.com/tomacco/aura-distill/issues/75) |

The existing [#61](https://github.com/tomacco/aura-distill/issues/61) productization gate also blocks service transports. It is not required for files-only use. [#67](https://github.com/tomacco/aura-distill/issues/67)/PR #68 remain separate connector work; discovery freezes the supported-client matrix rather than treating an unmerged connector as available.

## Decisions before implementation

| Uncertainty | Decision owner | Evidence and exit condition |
|---|---|---|
| Files-only structure and guarantees | [#75](https://github.com/tomacco/aura-distill/issues/75) | Synthetic before/after stores, fresh-agent interpretation and reviewed format/lifecycle/recovery decisions. |
| Old auto-updaters bypassing a future major gate | [#76](https://github.com/tomacco/aura-distill/issues/76) | Released-path matrix and skipped-release reproductions; safe channel/publication-order ADR. |
| Retrieval speed in practice | [#77](https://github.com/tomacco/aura-distill/issues/77), [#62](https://github.com/tomacco/aura-distill/issues/62) | Calibrated traces, natural-batching baseline, frozen endpoints/thresholds and independently reviewed experiment. |
| Runtime/storage and local/server authority | [#81](https://github.com/tomacco/aura-distill/issues/81) | Actual client/protocol evidence, dependency/startup tradeoffs and reviewed versioned contracts. |
| Pending evidence versus published memory | [#81](https://github.com/tomacco/aura-distill/issues/81), [#85](https://github.com/tomacco/aura-distill/issues/85) | Explicit acknowledgement/visibility/retry state machine; crash/concurrency fixtures. |
| Complete catalog versus semantic absence | [#66](https://github.com/tomacco/aura-distill/issues/66) | Exact/scoped/partial outcomes; alias, broad-domain, archive and excluded-scope tests. |
| More sophisticated ranking | [#91](https://github.com/tomacco/aura-distill/issues/91) | Observed held-out miss class and full cost/quality comparison; reject/defer without material gain. |

An experiment plan does not resolve a correctness blocker. Close discovery only when blocking decisions are made and reflected in downstream issues. Nonblocking questions may remain with follow-ups. Update native GitHub blockers and this table together when decisions change dependencies.

## Measurement contract

Measure current files, redesigned files and the later service as separate editions. Historical [#62](https://github.com/tomacco/aura-distill/issues/62) measurements serialized reads deliberately; preserve them as historical diagnostic data. The realistic incumbent allows natural batching. Use equivalent authorized source content and requirements, with separate experiments for transport, selection and compaction effects.

- Measure request to usable knowledge in the harness, completed correct task, engine/transport duration, startup/tool discovery, sequential model/tool turns, returned context, retries and failures where observable.
- Stratify cold/warm cache and local/remote transport; pin corpus hashes, code/harness/model versions, injected instructions and cache state. Never subtract unsynchronized host clocks.
- Preregister quality coverage, harmful extras, practical latency gain, repetitions/sample-size rule, uncertainty and run budget before scored runs. Use a separate cheap pilot, independent review and held-out cases. Do not promise p95 precision without enough observations.
- Quality means required facts/constraints, not identical filenames. Preserve rare directives, exceptions, corrections, archive recall and scoped misses. A faster incomplete answer fails.
- Use isolated synthetic personas. Do not copy live knowledge/transcripts into public fixtures. Optional private field validation is separately authorized; no scored runs are part of this planning change.
- Service telemetry [#83](https://github.com/tomacco/aura-distill/issues/83) distinguishes delivery from demonstrated usefulness and maintenance/prefetch from task use. Direct file access is unobserved unless instrumented. Keep local diagnostics bounded and sharing separately opt-in.
- Footprint, returned size, real model usage and billing are separate ([#40](https://github.com/tomacco/aura-distill/issues/40)). Archiving can reduce kb_tokens mechanically; that alone is not a retrieval or quality win.

## Existing backlog disposition

All 28 open issues inspected on 2026-09-10 are accounted for below. No issue is closed merely because its proposed mechanism changes. Original reports in reframed issues remain historical context; current execution contracts take precedence.

| Existing issue(s) | Disposition |
|---|---|
| [#41](https://github.com/tomacco/aura-distill/issues/41), [#64](https://github.com/tomacco/aura-distill/issues/64), [#73](https://github.com/tomacco/aura-distill/issues/73) | Track A thin SPINE, natural batching and files-only lifecycle. Later software enforcement belongs to [#86](https://github.com/tomacco/aura-distill/issues/86). |
| [#62](https://github.com/tomacco/aura-distill/issues/62) | Executable benchmark/fresh baseline owner; final service verdict is [#90](https://github.com/tomacco/aura-distill/issues/90). |
| [#63](https://github.com/tomacco/aura-distill/issues/63), [#66](https://github.com/tomacco/aura-distill/issues/66) | Service dependency closure/scoped misses. Files-only equivalents are included in [#78](https://github.com/tomacco/aura-distill/issues/78). |
| [#65](https://github.com/tomacco/aura-distill/issues/65) | Independent correctness bug; establish intended scope before declaring divergence or syncing excluded data. |
| [#61](https://github.com/tomacco/aura-distill/issues/61) | Retains shared sync/CAS/scopes and its existing field-test gate; service transport prerequisite. |
| [#28](https://github.com/tomacco/aura-distill/issues/28) | Separate private-tier product. Core isolation informs both designs; full classification/encryption UX is not a release blocker. |
| [#32](https://github.com/tomacco/aura-distill/issues/32), [#31](https://github.com/tomacco/aura-distill/issues/31), [#55](https://github.com/tomacco/aura-distill/issues/55) | Reuse dashboard, user-reviewed diagnostics and distillation report; consume [#83](https://github.com/tomacco/aura-distill/issues/83) when available. [#55](https://github.com/tomacco/aura-distill/issues/55) stays under [#53](https://github.com/tomacco/aura-distill/issues/53). |
| [#40](https://github.com/tomacco/aura-distill/issues/40) | Owns real usage/cost accounting. Missing usage cannot block latency measurement or be replaced with footprint estimates. |
| [#53](https://github.com/tomacco/aura-distill/issues/53), [#51](https://github.com/tomacco/aura-distill/issues/51) | Separate auto-distillation program. Service mode reuses writes/lifecycle; scheduling is not required for either initial release. |
| [#56](https://github.com/tomacco/aura-distill/issues/56) | Optional session-identity optimization; coordinate hook/installer ownership. Never invent missing session identity. |
| [#67](https://github.com/tomacco/aura-distill/issues/67) / PR #68 | Separate Antigravity connector work; coordinate support/installer changes without assuming it is merged. |
| [#69](https://github.com/tomacco/aura-distill/issues/69), [#70](https://github.com/tomacco/aura-distill/issues/70), [#72](https://github.com/tomacco/aura-distill/issues/72), [#6](https://github.com/tomacco/aura-distill/issues/6) | Downstream synthesis, recurrence, absence audit and confidence work. Preserve metadata compatibility; do not hide these mechanisms inside ranking. |
| [#71](https://github.com/tomacco/aura-distill/issues/71) | Separate output-enforcement boundary. Returning tool references never authorizes executing embedded instructions. |
| [#48](https://github.com/tomacco/aura-distill/issues/48), [#49](https://github.com/tomacco/aura-distill/issues/49), [#50](https://github.com/tomacco/aura-distill/issues/50) | Separate marks and model-routing program. Not prerequisites for basic retrieval; existing capability/approval controls still apply to model-based synthesis. |
| [#30](https://github.com/tomacco/aura-distill/issues/30), [#33](https://github.com/tomacco/aura-distill/issues/33) | Independent distribution metrics/last-resort telemetry. Protect unknown users without collecting install telemetry. |
| [#34](https://github.com/tomacco/aura-distill/issues/34) | Independent docs/accessibility/upstream follow-ups; token instrumentation overlaps [#40](https://github.com/tomacco/aura-distill/issues/40)/[#83](https://github.com/tomacco/aura-distill/issues/83)/[#62](https://github.com/tomacco/aura-distill/issues/62). |

Open PR #39 (Time Index) and PR #38 (capabilities calibration) remain separately reviewed/gated. Reuse capabilities only when actually available; this roadmap does not merge or require those PRs implicitly.

## Release decisions and maintenance

Track A closes at [#80](https://github.com/tomacco/aura-distill/issues/80). Track B closes at [#90](https://github.com/tomacco/aura-distill/issues/90) with an explicit go/no-go supported by frozen quality/performance criteria, upgrade protection, migration, offline and rollback evidence. If a gate fails, retain the supported files-only path and open the measured follow-up. A no-go result can close an experiment; it does not complete the implementation program.

Every implementation PR references its issue and follows [AGENTS.md](AGENTS.md) and [REVIEW-PROTOCOL.md](REVIEW-PROTOCOL.md). Maintain files-only and service-major release channels independently. Notices say what is shipped, measured, optional and deferred. Never expose software-major payloads on legacy endpoints before skipped-release protection passes.
