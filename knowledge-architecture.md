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
│  Max 80 lines. Index only. No content.      │
│  "What exists and where to find it"         │
└─────────────────┬───────────────────────────┘
                  │ LLM reads on-demand
                  ▼
┌─────────────────────────────────────────────┐
│  TIER 2: ACTIVE KNOWLEDGE (files on disk)   │
│  Max 60 lines per file. Current, relevant.  │
│  "What I need when working in this area"    │
└─────────────────┬───────────────────────────┘
                  │ Compaction promotes here
                  ▼
┌─────────────────────────────────────────────┐
│  TIER 3: ARCHIVE (compressed history)       │
│  No size limit. Summarized. Rarely read.    │
│  "What was true, for forensic reference"    │
└─────────────────────────────────────────────┘
```

---

## Tier 1: The Spine

**File:** `MEMORY.md` (or whatever the user's index file is called)

**Hard limit:** 80 lines maximum. This is the ONLY file that gets auto-loaded into every session context.

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
- Each line must fit in ~150 characters (path + hook)
- When the spine approaches 80 lines, trigger compaction (merge related entries, archive stale ones)

---

## Tier 2: Active Knowledge

**Location:** Subdirectories organized by layer (craft/, ops/, profile/, projects/, feedback/)

**Hard limit:** 60 lines per file. If a file grows beyond this, it must be split into focused sub-files or compacted.

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

**Rules:**
- One topic per file. "Testing" and "Code review" are separate files, not sections of one mega-file.
- Every file must be navigable from the spine. No orphan files.
- The LLM reads these ON DEMAND when a session touches the relevant domain. They are NOT auto-loaded.

---

## Tier 3: Archive (compressed, never deleted)

**Location:** `archive/` subdirectory

**No size limit.** This is cold storage — but NOT a graveyard.

**What it contains:**
- Knowledge that was once in Tier 2 but is no longer frequently accessed
- Historical context for forensic investigation
- Superseded learnings (kept for the "why did we change?" trail)

**File format:**

```markdown
---
archived_from: [original Tier 2 path]
archived_on: [date]
reason: [superseded|stale|merged|project-ended]
recall_count: [times this was accessed since archiving — starts at 0]
---

[Original content, possibly summarized]
```

**Critical rule: Compress, never discard.**

The goal is ZERO information loss. When moving knowledge from Tier 2 to Tier 3:
- Keep all principles intact
- Compress examples into shorter forms (remove context that's obvious from the principle)
- Preserve the "why" for every learning
- Maintain traceability (what was the original file, when was it active)

A Tier 3 file is not "less important" — it's "less frequently needed." The information hierarchy is:

```
Tier 1 (spine): WHAT exists and WHERE to find it
Tier 2 (active): Full detail for currently relevant knowledge
Tier 3 (archive): Full detail for rarely needed knowledge, more densely expressed
```

Alongside the tiers, two non-tier directories exist: `inbox/` (a pre-tier queue — items explicitly saved mid-session, consumed into the pipeline by the next distillation) and `data/` (local diagnostic ledgers — economics and distillation coverage — never part of the synced knowledge set).

**Promotion back to Tier 2:** If a Tier 3 file gets accessed 3+ times (`recall_count`), that's a signal it should be promoted back to Tier 2 — it's clearly still relevant.

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

**Cardinal rule: Compaction COMPRESSES — it never discards.** Moving knowledge to a lower tier means expressing it more densely, not deleting it. The principle, the "why," and the traceability must survive every compaction pass.

### Spine compaction (Tier 1)

Triggered when the spine exceeds 60 lines (giving 20 lines of headroom before hitting the 80-line hard cap).

Actions:
1. Merge entries that point to the same domain (e.g., three separate "testing" entries → one broader pointer)
2. Entries whose Tier 2 files haven't been validated in 3+ months → flag for staleness review (NOT auto-archive)
3. Group entries under fewer, broader headings

### File compaction (Tier 2)

Triggered when any Tier 2 file exceeds 45 lines (giving 15 lines of headroom before the 60-line cap).

Actions:
1. Split into focused sub-files if the file covers multiple distinct topics
2. Compress verbose explanations into tighter formulations (keep principles, tighten prose)
3. Move superseded content to Tier 3 (with full compression, never deletion)
4. Update the spine pointer if the file was split

### Staleness review

During each distillation, check `last_validated` on Tier 2 files:
- Files not validated in > `staleness_threshold` days get flagged
- The user is asked: "Is [file] still relevant? Should we compress it to Tier 3?"
- If yes → compress and archive. If still relevant → validate and bump `last_validated`
- **Never suggest deletion.** If something was true once, the compressed version belongs in Tier 3.

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

### When to read a Tier 3 file

Less frequently than Tier 2, but NOT "almost never." Read a Tier 3 file when:
- A Tier 2 file explicitly references archived context
- The user asks "why did we stop doing X?" or "what was the old approach?"
- You're investigating a regression that might relate to a past learning
- The spine mentions an archived topic that's now relevant again

**On every Tier 3 access:** Increment `recall_count` in the file's frontmatter. If it reaches 3, flag for promotion back to Tier 2.

### Validate-on-read (all tiers)

Every time you read a knowledge file, perform a lightweight validation:
1. Does this still match the current state of the codebase/project/user?
2. If you notice something outdated, update it NOW — this is the cheapest time to fix it.
3. Update `last_validated` in the frontmatter.

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
memory/
├── MEMORY.md                        ← THE SPINE (Tier 1, auto-loaded)
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
└── archive/
    ├── old-deploy-v1.md             ← Tier 3
    └── project-gamma-closed.md      ← Tier 3
```
