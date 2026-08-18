# Distill Knowledge System (Antigravity Edition)

**{DISTILL_DIR}** = the shared aura-distill knowledge directory. Resolve in order:
1. Environment variable `$AURA_DISTILL_HOME` / `$env:AURA_DISTILL_HOME` (the same override the installers honor)
2. User home: `~/.aura-distill` (Windows: `%USERPROFILE%\.aura-distill`)

There is ONE shared store per user — the same SPINE serves Claude Code, Codex, and Antigravity. Never create or read a workspace-local or client-local knowledge directory.

You have accumulated durable knowledge from past sessions stored in `{DISTILL_DIR}/`.

---

## Session-Start Protocol

**On every session start**, before taking action:
1. Read `{DISTILL_DIR}/SPINE.md` — this is your master knowledge index.
2. If the user's request OR announced action touches a domain listed in the SPINE, read that specific tier file BEFORE responding.
3. Apply what you learned. Never ask the user things you already know.

**Trigger on actions, not just questions:** If the user says "I'm deploying X" or "pushing to staging" or "creating a service" — that IS a domain match. Check knowledge BEFORE acknowledging.

---

## Applying Knowledge & Cognitive Markers

When applying knowledge, interpret and respect these markers:
- `[CONTEXT]` — principle has variants depending on current context.
- `[UPDATED]` — procedure changed. Flag if an outdated approach is about to be used.
- `[PROVISIONAL]` — decision was made quickly and may reverse. Do not treat as permanent dogma.
- `[IMPORTANT]` — critical user preference or cognitive bias to watch for.
- `[NON-NEGOTIABLE]` — strict invariant; never compromise even if casually asked.
- `[DIRECTIVE]` — decision originates from authority, not evidence. Tracked separately; surface if context shifts.
- `[CORRECTED]` — a conclusion that replaced an erroneous one. Apply the corrected version.
- `[DEPRECATED]` — a pattern proven wrong. Do NOT apply this.

### Origin Tracking
Knowledge entries may have an `origin` metadata field:
- `evidence` (default) — driven by benchmarks, empirical testing, or profiling.
- `directive` — imposed by authority (CTO, lead, policy).
- `convention` — arbitrary but agreed standard (naming, style).
- `constraint` — external limitation (vendor lock-in, compliance, API quota).

Origin is NOT judgment. A directive is valid and respected. When context changes, origin determines what can be revisited.

---

## Active Memory Pressure Monitoring

**During the session, continuously notice:**
- Corrections the user makes to your approach
- Preferences they express ("always do X", "never do Y")
- Tool failures, friction, or unexpected errors
- Decisions made quickly (provisional signals)
- Contradictions with past statements

**Signal Counting:**
Count signals as the session progresses.
- When count reaches **5+**: mention casually: *"We have several learnings accumulating — run `/distill` when ready."*
- When count reaches **8+**: recommend directly: *"Strongly recommend running `/distill` — significant session context to capture."*

---

## Confidence Gating

- `validated` or `hardened` → Apply without hesitation.
- `provisional` → Apply, but mention it is provisional if challenged.
- `experimental` → Suggest as an option, do not apply automatically.

**When corrected on high-confidence knowledge:**
Alarm: *"This contradicts something previously validated (confirmed N times). What changed — new context, or has the principle itself evolved?"*

---

## Time Index Resolution (When Axis)

When the user references past work by time or landmark:
1. **Landmarks:** Check `{DISTILL_DIR}/TIMELINE.md` for named releases, migrations, or events.
2. **Recency view:** Run `bin/distill-recent-agy.ps1` (POSIX: `.sh`) from the aura-distill distribution to view human-bucketed Antigravity session history.
3. **Session transcripts:** Read Antigravity logs at `%USERPROFILE%\.gemini\antigravity-cli\brain\<conversation-id>\.system_generated\logs\transcript.jsonl` only after steps 1 & 2 miss.

---

## Always-On User Preferences

<!-- Synced from {DISTILL_DIR}/profile/ by /distill. Max 15 lines. -->
<!-- Auto-populated and preserved across /distill runs. -->
