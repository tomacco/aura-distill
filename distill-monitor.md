# Distill: Session Monitor

This file is referenced by the Claude and Codex integration blocks. It is intentionally small to minimize context cost.

## MANDATORY: Knowledge retrieval

**At session start:** Read `{DISTILL_DIR}/SPINE.md`. Once. Non-negotiable. This gives you the map of what knowledge exists.

**During the session:** Use the SPINE to identify relevant files and Read them before the FIRST major action in a new domain (first time writing code, first PR review, first architecture call). You don't need to re-read for every subsequent action in the same domain — once loaded, the knowledge is in your context.

**When user says "remember X":** Write an INBOX item (see below) — do NOT save to memory/.

## Knowledge ownership (critical)

**Distill owns ALL persistent knowledge management.** Do NOT write competing persistent memories in a client's private memory store for learnings, corrections, preferences, or user model observations.

When you detect something worth remembering (a correction, a preference, a frustration, a learning):
- Do NOT write it to `memory/` files
- Do NOT create feedback/user/project memory files via the built-in system
- Instead: **note it mentally as a signal for the next `/distill` run** (this increases memory pressure)
- **If the user explicitly asks to save something** ("remember this", "save this for the next distill", "make sure distill captures this"): write it to the INBOX now (see below), then confirm.

**Why:** Distill has anti-sycophancy checks, frustration escalation, tiered storage, compaction, and observability. The built-in memory system has none of these. Bypassing distill means bypassing quality control.

**Exception:** If distill is NOT installed (no `{DISTILL_DIR}/` directory exists), fall back to the built-in memory system normally.

## The INBOX (explicit saves)

`{DISTILL_DIR}/inbox/` queues items for the next distillation run. When the user explicitly asks to save/remember something:

1. Write ONE file per item: `{DISTILL_DIR}/inbox/<UTC yyyymmddTHHMMSSZ>-<4 random hex>-<short-slug>.md` (the random suffix keeps concurrent sessions from colliding)
2. Content:

```markdown
---
origin: user-explicit
created: <ISO-8601 UTC>
session: <session id if you know it — otherwise omit the line>
domain_hint: <craft|ops|profile|projects|feedback — optional, omit if unsure>
---
<the thing to remember, in enough context that a future distillation agent who never saw this conversation can encode it correctly>
```

3. Confirm briefly with the file path: "Saved to inbox — the next distill will encode it."

Rules: one item per file; NEVER edit or delete existing inbox items (the distiller owns consumption); if the write fails, fall back to offering `/distill` now. Writing an inbox item does NOT reset memory pressure — it queues one signal, it doesn't consolidate.

## What to do at session start

1. **Read `{DISTILL_DIR}/SPINE.md`** — mandatory. This is your knowledge map for the session.
2. **Check if `{DISTILL_DIR}/.needs-migration` exists and does NOT start with "migrated".** If it exists and is not yet migrated, this is URGENT — tell the user IMMEDIATELY on their very first message, before doing anything else:
   > "Welcome! Distill was just installed. You have existing memory files that need to be ingested. Let me run `/distill` now to bring your existing knowledge into the system — otherwise you'll be working without your accumulated learnings. Shall I go?"
   Do NOT proceed with their request until migration is addressed. They're flying blind without it.
3. **Throughout the session:** Track memory pressure (see below).
4. **When pressure is high:** Suggest `/distill` to the user.

## Memory Pressure Tracking

Silently track a running pressure score (0-10) based on what happens in the session. Do NOT mention pressure to the user unless it reaches 5+.

**+1 each:**
- You detected a signal worth encoding (failure, correction, surprise)
- User taught you something non-obvious about their domain or preferences
- You made an assumption that turned out wrong
- The session has been going 30+ minutes with dense interaction
- A decision was made with a clear non-evidence origin (directive, constraint) — track it for proper categorization

**+2 each:**
- User corrected the same type of mistake you made before
- A complex learning emerged that spans multiple domains
- The system compressed or truncated conversation context

**+3 each:**
- An error pattern is recurring that clearly needs to be captured
- User is frustrated by something that prior consolidation would have prevented

## When to suggest

At pressure 5+, say something like:

> "We've accumulated some learnings this session. Want me to run `/distill` to consolidate them?"

Keep it casual and brief. Do not explain the full system. If the user says no, respect it — don't ask again until pressure reaches 7 or the session is clearly ending.

At pressure 7+, be more direct:

> "Strongly recommend consolidating — there's a lot to capture here and context is getting dense."

## After distillation

Once `/distill` runs successfully, reset pressure to 0.
