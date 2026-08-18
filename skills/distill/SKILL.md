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
     1. Environment variable `$env:AURA_DISTILL_DIR`
     2. Workspace directory `.agents/distill` (if present)
     3. User home directory: `~/.aura-distill` (Windows: `$env:USERPROFILE\.aura-distill`, POSIX: `$HOME/.aura-distill`)
     4. Antigravity profile: `~/.gemini/antigravity-cli/distill`
2. **Check Lock / Status (`{DISTILL_DIR}/.status`):**
   - If `.status` begins with `running` and timestamp is < 5 minutes old:
     Notify user: *"Another distillation is in progress. Would you like to wait or proceed later?"*
   - If `.status` indicates an interrupted run (`running step: ...`):
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

Spawn an isolated sub-agent using `invoke_subagent` (with `TypeName: 'self'` or `Role: 'Distillation Sub-Agent'`) or execute the distillation pipeline against `{DISTILL_DIR}`:

Provide the sub-agent with:
1. The harvested signals payload from Step 1.
2. The full process specification (`{DISTILL_DIR}/distill-process.md`).
3. The absolute path to `{DISTILL_DIR}`.

The sub-agent executes:
- **Phase 1: Ingestion & Deduplication** against existing Tier 2 files (`craft/`, `ops/`, `profile/`, `projects/`, `feedback/`).
- **Phase 2: Tier 2 Knowledge Updates** (max 60 lines per file, structured with confidence tags `[validated]`, `[provisional]`, `[experimental]` and origins).
- **Phase 3: Tier 1 Index Update (`SPINE.md`)** (max 80 lines, pointer index).
- **Phase 4: Always-On Preferences Sync** (`profile/user-preferences.md` synced to rules).
- **Phase 5: Status Reset** (set `{DISTILL_DIR}/.status` to `idle`).

---

### Step 3: Report Summary to User

Upon completion, output a concise distillation report:
- **Signals captured:** Count of friction points, decisions, and preferences.
- **Knowledge files updated:** Specific markdown files modified in `{DISTILL_DIR}`.
- **SPINE changes:** Any new pointers added to `SPINE.md`.
