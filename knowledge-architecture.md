# Knowledge Architecture

How `aura-distill` organizes knowledge to stay useful without bloating LLM context.

## The Problem

Knowledge accumulates. A user who runs `/distill` weekly for six months will have hundreds of learnings, a rich user profile, dozens of procedure notes. If all of this gets loaded into the LLM context at session start, it:

- Wastes tokens on irrelevant knowledge
- Dilutes attention from what actually matters for THIS session
- Eventually exceeds what CLAUDE.md / memory systems can hold

## Design: Three-Tier Knowledge

```
┌─────────────────────────────────────────────┐
│  TIER 1: THE SPINE (always in context)      │
│  80 lines and 16 KB. Index only.            │
│  "What exists and where to find it"         │
└─────────────────┬───────────────────────────┘
                  │ LLM reads on-demand (batched)
                  ▼
┌─────────────────────────────────────────────┐
│  TIER 2: ACTIVE KNOWLEDGE (files on disk)   │
│  60 lines and 6 KB per file.                │
│  "What I need when working in this area"    │
│  + evidence/ twin: its dated history        │
└─────────────────┬───────────────────────────┘
                  │ Lifecycle MOVES whole files
                  ▼
┌─────────────────────────────────────────────┐
│  TIER 3: ARCHIVE (byte-identical, read-only)│
│  No size limit. Ledger-recorded moves.      │
│  Found through CATALOG.md on a miss.        │
└─────────────────────────────────────────────┘
```

Since 1.2 the store follows the files-only design (`docs/design-files-only-memory.md`, decisions D1 to D10). The runtime rules live in `distill-process.md` ("Files-only layout: formats and rules") and `distill-monitor.md` ("Retrieval protocol"); this document explains the shape.

---

## Tier 1: The Spine

**File:** `SPINE.md` at the store root.

**Hard limits:** 80 lines **and** 16,000 bytes; each entry (its `- [` line plus any wrapped continuation lines) at most 400 bytes. Compaction starts at 60 lines or 12,000 bytes and shortens entries longest first toward 200 bytes. The first cap hit binds, and the distiller enforces it in the same run: "flag" is not a terminal state. This is the ONLY knowledge file that gets auto-loaded into every session context. Line caps alone let entries fatten into digests (a real store reached 80 lines and 39 KB).

**What it contains:**
- One-line pointers to Tier 2 files (path + relevance hook)
- Organized by topic, not chronology
- Each entry must answer: "When should the LLM read this file?"

**Format:**

```markdown
## Craft
- [Code review principles](craft/review-principles.md) — when reviewing or receiving PR feedback
- [Testing philosophy](craft/testing.md) — when writing or discussing tests

## Operations
- [Deploy procedures](ops/deploy.md) — when shipping to production
- [Incident playbook](ops/incidents.md) — when investigating prod issues

## User Profile
- [Expertise map](profile/expertise.md) — when calibrating explanations or suggestions
- [Communication style](profile/communication.md) — when choosing how to interact

## Projects
- [Project Alpha context](projects/alpha.md) — when working in repo-alpha
- [Project Beta context](projects/beta.md) — when working in repo-beta
```

**Rules:**
- Never put knowledge content in the spine. Only pointers.
- Each entry fits its byte budget; a hook keeps the distinctive nouns (project, tool and error names) that make retrieval fire.
- When an entry is cut or merged, its entire original hook is appended to its target file under `## Index detail (moved from SPINE <date>)`. Nothing is lost; the next distillation of that domain folds it into principles.
- Related files may share one line: `- [Beacon](projects/beacon.md) + [Delta](projects/delta.md) — hook`. A split file's continuation always shares its parent's line.
- Exactly one line points at `CATALOG.md`. No list of archived names ever enters the spine.

---

## Tier 2: Active Knowledge

**Location:** Subdirectories organized by layer (craft/, ops/, profile/, projects/, feedback/)

**Hard limit:** 60 lines and 6,000 bytes per file (compact at 45 lines or 4,500 bytes). Splitting is the primary remedy: `craft/x-2.md` with `split_from: craft/x.md` continues `craft/x.md` and shares its SPINE line. A file that cannot be split without breaking one atomic block may declare `oversize: <reason>`: exempt from the byte cap, listed in the catalog, reported every run.

**What it contains:**
- Actionable knowledge that's currently relevant
- Each file is self-contained — readable without needing other files for context
- Frontmatter with metadata for navigation

**File format:**

```markdown
---
domain: [craft|ops|profile|project|feedback]
scope: [what this file covers]
last_updated: [date of last distillation that touched this]
staleness_threshold: [days before this should be reviewed — default 90]
---

## [Topic]

[Content — actionable, principled, with "why" explanations]
```

**Per-entry metadata (inline, below each principle):**

```markdown
- [PRINCIPLE] Use Kafka for inter-service messaging.
  confidence: hardened (12 confirmations, 0 corrections)
  origin: directive (CTO mandate, 2026-03)
  evidence_says: SQS sufficient for current scale (10 events/day)
  last_validated: 2026-05-14
```

The `origin` field tracks WHERE a decision came from:
- `evidence` (default, can be omitted) — data, testing, or experience drove this
- `directive` — authority imposed it (record who + when)
- `convention` — arbitrary but agreed (coding style, naming patterns)
- `constraint` — external force (compliance, vendor limitation, budget)

When `origin: directive` and `evidence_says` disagree, both are recorded honestly. The system executes the directive but never forgets the evidence. This enables future revisiting when context changes (authority leaves, scale shifts, refactoring window).

**Optional frontmatter:** `last_validated`, `read_with: [ops/deploy.md]` (files always read together with this one, inline list, one extra batch, depth one), `lifecycle: pinned` (never archived automatically), `split_from`, `oversize`.

**Evidence twins.** `evidence/craft/testing.md` (frontmatter `evidence_for: craft/testing.md`) holds the dated record behind the principles: confirmations, corrections, observations, one `- YYYY-MM-DD …` line each. It is append-only, never compacted, never in the SPINE and not read during ordinary retrieval. The principle file keeps the principle, its `confidence:` counts, its `last_validated:` date and one `Evidence:` citation line. Lines that carry a protected marker (`[NON-NEGOTIABLE…]`, `[DIRECTIVE…]`) or a retrieval marker (`[UPDATED…]`, `[DEPRECATED…]`, `[CORRECTED…]`, `[IMPORTANT…]`, `[CONTEXT…]`, `[PROVISIONAL…]`) never move to evidence: retrieval depends on seeing them.

**Rules:**
- One topic per file. "Testing" and "Code review" are separate files, not sections of one mega-file.
- Every file must be navigable from the spine. No orphan files.
- The LLM reads these ON DEMAND when a session touches the relevant domain. They are NOT auto-loaded.

---

## Tier 3: Archive (moved whole, never rewritten, never deleted)

**Location:** `archive/<tier>/<name>.md` — the file's own path under `archive/`.

**No size limit.** This is cold storage — but NOT a graveyard.

**Critical rule: move, never rewrite.** Archiving `projects/atlas.md` is `mv projects/atlas.md archive/projects/atlas.md`. The bytes do not change, so the move is verifiable by checksum and reversible by one move back. (Before 1.2, archiving meant a rewrite into "denser expression"; it cost a compression pass per file, so it rarely happened, and it changed the wording it was meant to keep.)

**The ledger.** `archive/LEDGER.md` is append-only and synced. Every archive and restore adds one line, written before the move, carrying the checksum, the reason and the full SPINE line that was removed:

```markdown
- 2026-09-11T10:31:00Z archive | from: projects/atlas.md | to: archive/projects/atlas.md | sha256: 12c1… | sha256-norm: 12c1… | reason: past threshold, no validation observed | spine-entry: - [Atlas](projects/atlas.md) — Atlas data-platform migration …
```

The last line naming a path is its state; lines are appended in date order. A restore re-adds the saved SPINE entry (within budget) and moves the file back.

**Read-only.** No client edits an archived file or bumps a stamp inside it. `sha256-norm:` (the checksum without a `recall_count:` frontmatter line) lets a 1.2 client tell a 1.1 client's `recall_count` bump (drift) from a real modification.

**Legacy archives.** Files written by the old rewrite-style compaction have no ledger line. A file directly under `archive/` or under `archive/legacy/` is legacy. An unledgered file under `archive/<tier>/` is adopted by `migrate-store` to `archive/legacy/<its current path>` (`archive/projects/x.md` → `archive/legacy/archive/projects/x.md`), byte-identically. Legacy files are never deleted; restoring one copies it back to an active file and leaves it in place.

**Finding archived knowledge.** `CATALOG.md` at the store root lists every file (active, archived with the original hook and reason, evidence with its entry count). It is not auto-loaded. When a request refers back to something no SPINE hook matches, the reader searches the catalog; an archived hit is read and reported as archived, and no hit is reported as a scoped miss ("not proof it was never distilled").

**Coming back.** There is no `recall_count` promotion any more. When a project comes back, the user asks to restore it ("bring back Atlas"), or the next distillation restores a file the session worked on. A path never exists both active and archived.

Alongside the tiers, other directories exist: `evidence/` (twins, above), `inbox/` (a pre-tier queue — items explicitly saved mid-session, consumed into the pipeline by the next distillation), `local/` (a machine-local overlay with its own `local/SPINE.md`, never synced, never cataloged) and `data/` (local diagnostics, lifecycle manifests and migration backups — never part of the synced knowledge set).

**Sync classification.** Shared: the tier directories, `evidence/`, `archive/` including the ledger (byte-exact: no line-ending normalisation, or every checksum breaks), `CATALOG.md` (rebuilt on conflict). Local: `local/`, `.lifecycle`, `data/`.

---

## Memory Recall Protocol (validate on access)

Every time knowledge is recalled from ANY tier, it is an opportunity — and an obligation — to validate it.

### The Recall-Validate-Update cycle

```
RECALL: Read the memory file
   ↓
VALIDATE: Is this still true? Check against current state.
   ↓
   ├── Still true → Use it, no changes needed
   ├── Partially true → Update the file with corrected information
   ├── Outdated → Rewrite with current truth, note what changed
   └── Wrong → Correct it, add a note about what the old belief was and why it was wrong
```

### Why validate on recall?

- Memories are written at a point in time. Systems change, people change, processes evolve.
- A memory that was correct 3 months ago may now be actively harmful.
- The moment you recall a memory is the CHEAPEST time to validate it — you're already in the relevant context.
- Stale memories are worse than no memory: they produce confident, wrong behavior.

### What validation looks like

- **For craft standards:** Does this rule still hold? Has the tooling changed? Has the user's practice evolved?
- **For procedures:** Does this workflow still work? Have steps been added/removed?
- **For project context:** Is this still the current state of the project? Has scope changed?
- **For user profile:** Does this observation still match how the user behaves? People grow.
- **For feedback:** Does the user still feel this way? Preferences evolve.

### Validation metadata

After validating, update the file's frontmatter:

```markdown
---
last_validated: [today's date]
validation_note: [optional — "confirmed still accurate" or "updated X because Y"]
---
```

This creates a trust signal: files validated recently can be used with high confidence. Files not validated in months should be treated with more skepticism.

---

## Compaction: Keeping Tiers Healthy

Compaction is part of the `/distill` process. Every distillation run should check tier health.

**Cardinal rule: Compaction never discards.** Tightening prose inside an active file is allowed; dropping a principle, its "why" or its traceability is not. Moving a file to Tier 3 is a byte-identical move, never a compression, and dated evidence moves to the evidence twin, never away.

### Spine compaction (Tier 1)

Triggered at 60 lines or 12,000 bytes; the hard caps (80 lines, 16,000 bytes, 400 bytes per entry) are enforced in the same run.

Actions:
1. Shorten entries over 400 bytes, then the longest entries toward 200 bytes while the file is over its byte cap; each cut hook goes verbatim to its target file's `## Index detail`
2. Reclaim lines: split children share their parent's line; blank lines go; same-tier entries on one topic merge into a multi-pointer line
3. Never archive a file to make room and never ask about the index

### File compaction (Tier 2)

Triggered at 45 lines or 4,500 bytes.

Actions:
1. Split by `## ` section into `<name>-2.md` (primary remedy; protected and marker blocks stay whole)
2. Move dated observation lines to the evidence twin
3. Compress verbose explanations into tighter formulations (keep principles, tighten prose; never a protected or marker line)
4. Update the spine line if the file was split

### Lifecycle (opt-in) and staleness

Persisted in `.lifecycle` (`enabled` / `disabled`, absent = disabled; local to the machine; installer flags `--lifecycle` / `--no-lifecycle` / `--remove-lifecycle`).

| Rule | Detail |
|---|---|
| Activity stamp | Newest of frontmatter `last_validated`, `last_updated` and every per-principle `last_validated`. No stamp at all: ineligible, reported. Reads are not observed, so missing activity counts as unknown |
| Eligible | A `projects/` file whose activity stamp is older than its `staleness_threshold` (default 90 days) |
| Exempt | `lifecycle: pinned`; any `[NON-NEGOTIABLE…]` marker; everything outside `projects/` (those keep the ask-first staleness question) |
| Blocked | Named in another active file's `read_with` (recorded with its reason) |
| Referenced in prose | Not blocking; the report lists the referrers; readers find it at `archive/<same path>` |
| Action | Ledger line, byte-identical move, SPINE entry removed, catalog rebuilt; `[DIRECTIVE…]` moves are listed with their marker count |
| Preview | `/distill gc` shows the plan and changes nothing; `--apply` executes it |
| Restore | `/distill restore <path>`: ledger line, move back, saved SPINE entry re-added within budget |

When enabled, Step 5 of every distillation applies it without per-item questions. When disabled, the distiller reports the debt and asks nothing. Age alone never means a project ended: the move says "not validated within its threshold, kept whole, findable through the catalog". **Never suggest deletion.**

---

## Navigation Protocol (for the LLM)

When a new session starts, the LLM has ONLY the spine loaded. Here's how it navigates deeper:

### When to read a Tier 2 file

Read a Tier 2 file when:
- The user's request matches the "relevance hook" in the spine entry
- You're about to give advice in a domain that has a knowledge file
- You're running `/distill` and need to update existing knowledge
- The user explicitly asks about something covered by a pointer

Do NOT read a Tier 2 file when:
- The session hasn't touched that domain
- You're just doing a quick task that doesn't benefit from deep context
- You've already read it this session (unless it was updated)

Read all matched Tier 2 files in one batch of parallel reads, then their `read_with:` companions in one more batch. Serialize only when a file decides what to read next.

### When to read a Tier 3 file

Less frequently than Tier 2, but NOT "almost never." Read a Tier 3 file when:
- A Tier 2 file references a path that now lives at `archive/<same path>`
- The user refers back to something no SPINE hook matches and its catalog row is archived
- The user asks "why did we stop doing X?" or "what was the old approach?"
- You're investigating a regression that might relate to a past learning

**Archived files are read-only.** Reading one changes nothing (no `recall_count`, no stamp). If the user is working on it again, restore it.

### Validate-on-read (active tiers)

Every time you read an active knowledge file, perform a lightweight validation:
1. Does this still match the current state of the codebase/project/user?
2. If you notice something outdated, update it NOW — this is the cheapest time to fix it.
3. Update `last_validated` in the frontmatter.

Not for `archive/` (read-only) and not for maintenance reads (eligibility scans, migration, gc and self-checks read without re-stamping, or they would reset every clock).

This keeps the knowledge system self-healing. Every read is also a micro-maintenance pass.

### Navigation cost budget

Per session, aim for:
- Spine: always loaded (free — it's tiny)
- Tier 2 reads: 3-5 files max in a typical session
- Tier 3 reads: 0-1 files max, only when investigating

If you find yourself needing to read more than 5 Tier 2 files, that's a signal the spine's relevance hooks aren't specific enough, or the files aren't focused enough.

---

## Bootstrap: First-Time Setup

When `/distill` runs and finds no tiered structure:

1. Check what exists (flat memory files, MEMORY.md, scattered notes)
2. Propose a tiered layout based on what's already there
3. Migrate existing content into Tier 2 files
4. Generate the spine from the new structure
5. Ask the user to confirm before restructuring

Never restructure without permission. Always show the proposed layout first.

---

## Example: Mature Knowledge Structure

```
~/.aura-distill/
├── SPINE.md                         ← THE SPINE (Tier 1, auto-loaded)
├── CATALOG.md                       ← complete inventory (not auto-loaded)
├── craft/
│   ├── review-principles.md         ← Tier 2
│   ├── testing-philosophy.md        ← Tier 2
│   └── naming-conventions.md        ← Tier 2
├── ops/
│   ├── deploy-checklist.md          ← Tier 2
│   └── incident-response.md         ← Tier 2
├── profile/
│   ├── expertise.md                 ← Tier 2
│   └── communication.md            ← Tier 2
├── projects/
│   ├── alpha.md                     ← Tier 2
│   └── beta.md                      ← Tier 2
├── feedback/
│   └── collaboration-prefs.md       ← Tier 2
├── evidence/
│   └── craft/testing-philosophy.md  ← evidence twin (append-only)
└── archive/
    ├── LEDGER.md                    ← append-only move log
    ├── projects/gamma.md            ← Tier 3 (moved byte-identically)
    └── legacy/old-deploy-v1.md      ← pre-1.2 rewritten archive
```
