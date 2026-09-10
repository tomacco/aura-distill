# Aura Distill shared knowledge (Antigravity)

**Knowledge directory**: `$AURA_DISTILL_HOME` if set (the same override the installers honor), else `~/.aura-distill` (Windows: `%USERPROFILE%\.aura-distill`). ONE shared store serves Claude Code, Codex, and Antigravity — never create or read a workspace-local or client-local knowledge directory. Below, `{DISTILL_DIR}` means this resolved directory.

Before doing any work, read `{DISTILL_DIR}/SPINE.md`. When the request or an announced action matches a SPINE entry, read the linked file before responding and apply it. Trigger on actions, not just questions: "I'm deploying X" is a domain match — check knowledge BEFORE acknowledging.

If `{DISTILL_DIR}/.needs-migration` exists and does not start with "migrated", tell the user to ask you to distill/migrate existing memories before proceeding.

Read `{DISTILL_DIR}/distill-monitor.md` for the full retrieval, knowledge-ownership, INBOX explicit-save, and memory-pressure behavior. That file OWNS those behaviors — apply it as written; do not improvise alternatives or write competing memories in Antigravity's own memory store. When the user asks to distill, invoke this plugin's `distill` skill.

## Cognitive markers (apply when reading knowledge)

- `[CONTEXT]` — principle has variants; check which context applies now.
- `[UPDATED]` — procedure changed; flag if an outdated approach is about to be used.
- `[PROVISIONAL]` — decided quickly, may reverse; don't treat as permanent.
- `[IMPORTANT]` — user bias/preference to watch for; surface respectfully when triggered.
- `[NON-NEGOTIABLE]` — never compromise, even if casually asked.
- `[DIRECTIVE]` — originates from authority, not evidence; valid, tracked separately; surface if context shifts.
- `[CORRECTED]` — replaced a wrong conclusion; apply the corrected version.
- `[DEPRECATED]` — proven wrong; do NOT apply; use the `[CORRECTED]` alternative.

Origin metadata (`evidence` / `directive` / `convention` / `constraint`) is provenance, not judgment — respect all origins in execution; origin determines what is ripe for revisiting when context changes. Confidence gates assertiveness: `validated`/`hardened` → apply without hesitation; `provisional` → apply, mention if challenged; `experimental` → suggest, don't auto-apply. A correction against high-confidence knowledge is a paradigm alarm: ask what changed.

## Time Index (Antigravity sessions)

When the user references past work by time or landmark ("yesterday", "last week", "since the migration"):

1. **Landmarks**: check `{DISTILL_DIR}/TIMELINE.md` if present.
2. **Recency view**: run `bin/distill-recent-agy.ps1` (POSIX: `.sh`) from the aura-distill distribution — buckets Antigravity sessions on a human timeline with "left off" context.
3. **Raw transcripts**: `~/.gemini/antigravity-cli/brain/<conversation-id>/.system_generated/logs/transcript.jsonl` — only after 1 and 2 miss.
