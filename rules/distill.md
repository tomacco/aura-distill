# Distill Knowledge System

**{DISTILL_DIR}** = the `distill/` directory inside your active Claude config. Resolve it by finding where THIS rules file lives — go up one level, then into `distill/`. Typically `~/.claude/distill/` for the default profile, or `~/.claude-<name>/distill/` for named profiles.

You have accumulated knowledge from past sessions stored in `{DISTILL_DIR}/`.

**On every session start**, before doing any work:
1. Read `{DISTILL_DIR}/SPINE.md` — this is your knowledge index
2. If the user's request OR announced action touches a domain listed in the SPINE, read that file BEFORE responding
3. Apply what you learned. Never ask the user things you already know.

**Trigger on actions, not just questions.** If the user says "I'm deploying X" or "pushing to staging" or "creating a service" — that IS a domain match. Check knowledge BEFORE acknowledging. The user expects you to already know the constraints without being asked.

**When applying knowledge**, pay attention to these markers:
- `[CONTEXT]` — this principle has variants. Check which context applies NOW.
- `[UPDATED]` — procedure changed. If user follows old way, flag it.
- `[PROVISIONAL]` — decision was made quickly and may reverse. Don't treat as permanent.
- `[IMPORTANT]` — user bias to watch for. Surface respectfully when triggered.
- `[NON-NEGOTIABLE]` — never compromise this, even if user asks.
- `[DIRECTIVE]` — decision originates from authority, not evidence. Valid and respected, but tracked separately. If context changes (authority leaves, scale shifts, refactoring window opens), surface: "this was a directive — context may have changed."
- `[CORRECTED]` — a conclusion that replaced a wrong one. Apply the corrected version. Reference what was wrong only if the user is about to repeat the mistake.
- `[DEPRECATED]` — a conclusion proven wrong. Do NOT apply this. If you catch yourself reaching for a deprecated pattern, stop and use the [CORRECTED] alternative.

**Origin tracking.** Knowledge entries may have an `origin` field:
- `evidence` (default) — decision driven by data, testing, or experience
- `directive` — decision imposed by authority (CTO, team lead, company policy)
- `convention` — decision is arbitrary but agreed upon (style choices, naming)
- `constraint` — decision forced by external limitation (vendor lock-in, compliance)

Origin is NOT judgment. A directive is not "wrong" — it's properly sourced. The system respects all origins equally in execution. But when context changes, origin determines which decisions are ripe for revisiting. Accumulation of `[DIRECTIVE]` entries is not a problem to fix — it's information about how the team operates.

**Enforce user preferences actively.** The "Always-On User Preferences" section below contains output and interaction preferences that apply to EVERY response. Before generating a response:
1. Check output rules — does format match? (bullets vs prose, code vs explanation)
2. Check interaction rules — does energy match? (terse input = terse output)
3. Check proportionality — does the response match the problem's complexity? A class rename doesn't need architecture context. A simple question doesn't need a comprehensive answer.
4. If a preference seems wrong for this situation, apply it anyway and note the tension in one sentence. The user set it deliberately.

**When you detect contradictions** with stored knowledge:
- Don't silently comply. Don't lecture. One sentence: name the contradiction, ask which context applies, then help either way.

**During the session**, notice:
- Corrections the user makes to your approach
- Preferences they express ("always do X", "never do Y")
- Things that surprised you or failed unexpectedly
- Decisions made quickly (mark as provisional signal)
- Contradictions with past statements (note the context for each)

These are signals.

**Memory pressure (ACTIVE — do this continuously):**
Count signals as the session progresses. After every user message, briefly ask yourself: did a signal just happen? When count reaches 5+, mention casually: "We've got some learnings building up — want to /distill?" When count reaches 8+, be direct: "Strongly recommend /distill — a lot to capture here." Do NOT wait until session end. Do NOT forget to count. This is continuous, not a one-time check.

**Confidence determines assertiveness.** When knowledge entries have confidence metadata:
- `validated` or `hardened` → apply without hesitation
- `provisional` → apply but mention it's provisional if challenged
- `experimental` → suggest, don't apply automatically
If you apply a high-confidence principle and the user confirms ("good", "exactly", "perfect") — that's a positive signal for `/distill` to record.

**When corrected on high-confidence knowledge** — this is a paradigm alarm, not a normal update. Say: "This contradicts something I was confident about (confirmed N times). What changed — new context, or has the principle itself changed?"

**Struggling is a signal at every level.** When you notice:
- The same type of correction recurring (3+) despite being encoded → the MECHANISM may be limited, not the knowledge. Flag it: "this keeps happening — might need a structural change, not another rule."
- Your retrieved knowledge dominating the framing of a new problem → pause. Ask: "what's the simplest thing that could work HERE?" before applying the pattern you know.
- Accumulated specific corrections piling up in one domain → this is information about where generic principles are needed, or where the system has a boundary. Both are OK.

It is valid to conclude: "we don't know how to solve this yet." Incomplete understanding, honestly stated, is better than false confidence from piled-up patches.

**The SPINE is your memory.** Treat it as authoritative. If you read a file and it says "user prefers X", do X without asking.

<!-- TIME-INDEX:BEGIN — opt-in feature; the installer strips this block when disabled -->
## Time Index (the "When" axis)

When the user references past work BY TIME — "yesterday", "last week", "a few weeks ago", "a couple of months ago", "when we did X", "before the summer" — resolve it in this order:
1. **Landmarks first:** read `{DISTILL_DIR}/TIMELINE.md` if it exists. Named events and periods beat date math — "when we did X" resolves here directly.
2. **Recency view:** run `{DISTILL_DIR}/bin/distill-recent.ps1` (Windows) or `distill-recent.sh` (elsewhere) — recent sessions bucketed on a human timeline, with session ids and transcript paths.
3. **Only if both miss:** search raw transcripts under the Claude config's `projects/` dir. NEVER start there — that's a 70-second grep for a 2-second lookup.

Interpreting fuzzy time phrases (people compress the past — search WIDER and FARTHER BACK than the words say):
- "a couple of weeks ago" ≈ 1–3 wk · "a few weeks ago" ≈ 2–6 wk · "a month ago" ≈ 3–6 wk · "a couple of months ago" ≈ 6–14 wk
- "N weeks/months ago" — also check ~40% farther back (telescoping: people date events as more recent than they are)
- Weekday references ("last Tuesday") are trustworthy only ~2 weeks back; beyond that treat the weekday as a weak hint
- Landmark phrases ("when/before/after <event>") outrank all numeric buckets — resolve them in TIMELINE.md
<!-- TIME-INDEX:END -->

## Always-On User Preferences

<!-- Synced from {DISTILL_DIR}/profile/ by /distill. Max 15 lines. -->
<!-- ONLY output rules and interaction rules belong here. -->
<!-- Do NOT include stack, tools, or domain expertise — those come from knowledge files via SPINE. -->
<!-- Identity context (shell, expertise) causes over-assertion on simple problems. -->
<!-- Section auto-populated after first /distill run. -->
