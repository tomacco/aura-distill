---
id: task-45
title: "aura distill cloud: server-owned sync protocol (version + CAS); git becomes a backup plugin"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: []
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/61
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/61

## Directive (Ivan, 2026-08-10)

aura distill cloud: the **aura server owns sync as a product capability**. Clients speak aura's HTTP protocol — never git's. Git is demoted to (a) an optional internal storage detail of the server and (b) one backup *plugin* among several (git / iCloud / Google Drive / NAS) configured via a future web app. Target UX: create an account on the server, install the client with the server add-on, forget about it.

## Protocol (v1 sketch, field-testing now in `tomacco/distill-mcp`)

Optimistic concurrency (compare-and-swap), server-enforced — no locks, no lease liveness problems:

- `GET /sync/version` → current head `{ version, created }` (server-assigned monotonic id)
- `GET /sync/changes?since=<v>` → `{ head, files: { path: content | null } }` (null = deleted; `since=0` = full snapshot)
- `POST /sync/commit` `{ base_version, files: {...} }` → applies atomically iff `base_version == head`, else **409** `{ head, changed_since: [paths] }`

Client retry policy on 409: pull → overlap check (server-changed paths ∩ locally-changed paths) → disjoint: re-apply + retry; overlapping: the local synthesis was computed against a stale worldview — redo the affected domain (not a blind retry).

## Rules

- **Read path fails open**: session start checks the server version with a short timeout; offline ⇒ consume local knowledge with a staleness note. Reads never merge.
- **Write path**: the 409 IS the version check — atomic on the server, no TOCTOU.
- **Machine-local overlay**: `local/` inside the knowledge dir is *structurally unsynced* (never in the sync set), with its own `local/SPINE.md` consulted alongside the shared index. For company/machine data that must never leave the box. Absence beats filtering.
- **Sync set**: knowledge `*.md` + `inbox/`; excludes `data/` (local diagnostics per existing convention), `hooks/`, dotfiles, and updater-owned `distill-process.md` / `distill-monitor.md` (syncing those would fight per-machine installers).
- Auth: OAuth scopes split — `distill.read` (MCP/chat clients) vs `distill.sync` (the user's own machines); a chat client token can never write.
- v1 is last-writer-wins at file level under CAS ordering — no 3-way merge yet.

## Productization gate

Field-test at n=1 across ≥2 machines until the protocol survives real use **including at least one genuine 409**, then port here as a PR referencing this issue. Release-frame rules apply (read-path network check is a latency trade ⇒ opt-in knob, fail-open default).

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
