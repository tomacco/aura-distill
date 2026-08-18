---
name: distill
description: Retrospective memory and context distillation for Antigravity sessions. Harvests conversation signals, friction, user preferences, and decisions, then executes the distillation pipeline to update tiered knowledge in SPINE.md and domain knowledge files.
---

# Retrospective Distillation for Antigravity (agy)

> **MANDATORY**: Distillation MUST execute via a spawned sub-agent or isolated task turn. Never run the detailed knowledge synthesis directly in the main prompt loop, as it consumes context window needed for your primary task.

## Purpose

`aura-distill` captures high-value architectural decisions, friction points, corrections, user preferences, and timeline landmarks from your Antigravity pair-programming sessions and crystallizes them into a structured, tiered memory repository (`{DISTILL_DIR}`).

---

## Distillation Workflow

### Step 0: Pre-flight Status & Integrity Checks

1. **Resolve Knowledge Directory `{DISTILL_DIR}`:**
   - Check in order:
     1. Environment variable `$AURA_DISTILL_HOME` / `$env:AURA_DISTILL_HOME` (the same override the installers honor)
     2. User home directory: `~/.aura-distill` (Windows: `$env:USERPROFILE\.aura-distill`, POSIX: `$HOME/.aura-distill`)
   - There is ONE shared store per user — the same SPINE serves Claude Code, Codex, and Antigravity. Never create a workspace-local or client-local knowledge directory.
2. **Check Lock / Status (`{DISTILL_DIR}/.status`):**
   - The `.status` file format is OWNED by `distill-process.md` — write exactly its forms
     (`running <ISO_TIMESTAMP>`, `running step:[N] signals:[count] <ISO_TIMESTAMP>`, `idle <ISO_TIMESTAMP>`);
     this file is shared with the Claude Code and Codex clients.
   - If `.status` begins with `running` and its timestamp is < 5 minutes old:
     Notify user: *"Another distillation is in progress. Would you like to wait or proceed later?"*
   - If `.status` indicates an interrupted run (`running step:[N] ...` with a stale timestamp):
     Offer checkpoint resumption.
   - Otherwise, set `{DISTILL_DIR}/.status` to `running <ISO_TIMESTAMP>`.

---

### Step 1: Harvest Signals from the Active Session

Scan the current session transcript (or context history) and extract:

1. **Failures & Friction:**
   - Tool errors, syntax/build failures, incorrect assumptions, multi-attempt iterations.
2. **Corrections & Directives:**
   - User corrections on style, design, libraries, architecture, or behavior.
   - Origin classification:
     - `evidence` (data / benchmarks / testing)
     - `directive` (explicit user/team authority)
     - `convention` (standard team style)
     - `constraint` (external tooling or environment limits)
3. **User Preferences & Interaction Style:**
   - Terse vs detailed outputs, preferred frameworks, testing patterns.
4. **Domain Knowledge & Architectural Decisions:**
   - New APIs, refactoring decisions, dependency choices, configuration paths.
5. **Timeline Landmarks:**
   - Key milestones, deliveries, major refactors, or releases named during this session.

Format these into a clean structured signal payload.

---

### Step 2: Spawn the Distillation Sub-Agent

Spawn an isolated sub-agent using `invoke_subagent` (with `TypeName: 'self'` or `Role: 'Distillation Sub-Agent'`). If sub-agent spawning is unavailable in this session, run the pipeline in an isolated task turn — never inline in the main conversation loop (see the MANDATORY note above).

Provide the sub-agent with:
1. The harvested signals payload from Step 1.
2. The full process specification (`{DISTILL_DIR}/distill-process.md`).
3. The absolute path to `{DISTILL_DIR}`.

The sub-agent executes the phases exactly as defined in `{DISTILL_DIR}/distill-process.md`
(ingestion & deduplication, Tier 2 knowledge updates, SPINE index update, always-on
preferences sync, status reset). That file — not this skill — is the source of truth for
phase mechanics, file layouts, and line caps; do not re-specify them here.

---

### Step 3: Report Summary to User

Upon completion, output a concise distillation report:
- **Signals captured:** Count of friction points, decisions, and preferences.
- **Knowledge files updated:** Specific markdown files modified in `{DISTILL_DIR}`.
- **SPINE changes:** Any new pointers added to `SPINE.md`.
