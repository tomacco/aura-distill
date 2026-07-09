# Retrospective Distillation

> **MANDATORY**: This command MUST execute via a spawned sub-agent. NEVER run the distillation process in the main conversation context. The main context is precious — distillation would consume it and defeat the purpose.

## What you MUST do (exactly in this order)

### Step 0: Pre-flight checks

Before doing ANYTHING else, run these checks:

**Status check:**
1. Read `{DISTILL_DIR}/.status` (use Bash: `cat {DISTILL_DIR}/.status 2>/dev/null`)
2. If it starts with `running` and the timestamp is **less than 5 minutes old** → another distillation is in progress. Tell the user:
   > "Another distillation is currently running (started at [timestamp]). I can harvest signals now and wait for it to finish, or you can try again later. What do you prefer?"
   - If user says wait/queue: proceed with signal harvest (Step 1), then poll the status file every 30 seconds before spawning. Once it reads `idle`, spawn the sub-agent.
   - If user says later: stop, don't distill.
3. If it starts with `running` and the timestamp is **older than 5 minutes** → stale status from a crashed session. Check for checkpoint data (see below). Proceed.
4. If it reads `idle`, doesn't exist, or is empty → proceed normally.

**Checkpoint recovery:**
If `.status` starts with `running step:` — a prior distillation was interrupted. Parse the step number and signal count from the status line. Tell the user:
> "A previous distillation was interrupted at [step]. It had harvested N signals. Want me to resume from where it left off, or start fresh?"
- Resume: skip harvest, use the checkpoint data, spawn sub-agent with it.
- Fresh: overwrite status with `running <timestamp>`, proceed with new harvest.

**Version check (once per session):**
If this is the first `/distill` invocation this session, run the version check (see Version Checking section below).

**Migration check:**
If `{DISTILL_DIR}/.needs-migration` exists and does NOT start with "migrated", this is the first distill after installation. In addition to normal signal harvesting, the sub-agent must also:
1. Find all memory files: `find ~/.claude -path "*/memory/*.md" -not -path "*/distill/*"`
2. Read each one and ingest its content into the appropriate distill tier (craft, ops, profile, feedback, projects)
3. Create a completion marker: `echo "migrated $(date -u +%Y-%m-%dT%H:%M:%SZ)" > {DISTILL_DIR}/.migrated`
4. Remove the flag: `rm {DISTILL_DIR}/.needs-migration` — it must NOT survive migration; existence-only gates (the installed CLAUDE.md line) treat its presence as "migration pending"
5. Report what was migrated in the distillation output

The old memory files are NOT deleted — they stay as backup. Distill just absorbs their knowledge into its own system.

**Backup detection (pre-flight):**
Before spawning the sub-agent, quickly check if prior knowledge may have been displaced:
1. If `{DISTILL_DIR}/` is empty or missing but a backup directory exists nearby (e.g., `~/.claude/_distill_isolation_bak/`, or any `*_bak*`/`*_backup*` directory containing distill-like files), include the backup path in the sub-agent payload so it can offer restoration.
2. If `{DISTILL_DIR}/SPINE.md` exists, do a quick count of tier directories (`ls {DISTILL_DIR}/*/`). If they're mostly empty but SPINE references files, flag this to the sub-agent as a potential integrity issue.

This prevents the sub-agent from silently creating a fresh knowledge base when prior knowledge exists elsewhere on disk.

---

### Step 1: Harvest signals from THIS conversation

You are in the main context right now. You CAN see the full conversation history. The sub-agent CANNOT. Therefore you must extract everything relevant NOW, before spawning.

Scan the entire conversation above and collect:

**A) Failures & friction**
- Every failed attempt (what was tried, what went wrong, what the fix was)
- Every multi-attempt sequence (what changed between attempts)
- Every unexpected behavior encountered

**B) Corrections & teachings**
- Every time the user corrected your approach (what you did vs. what they wanted)
- Every non-obvious fact the user taught you
- Every wrong assumption you made

**C) User behavior observations**
- Communication style exhibited (terse commands? detailed specs? thinking aloud?)
- Expertise demonstrated (what they knew without being told)
- Growth edges revealed (what they asked about or struggled with)
- Emotional signals (frustration, excitement, impatience — and what preceded each)
- Decision-making style (did they reason from principles or examples? data or intuition?)

**D) Decision origins**
- For every decision or principle that emerged: WHY was it made?
- Classify the origin:
  - `evidence` — data, testing, profiling, or experience drove it
  - `directive` — authority imposed it ("CTO said", "team lead decided", "company policy")
  - `convention` — arbitrary but agreed upon ("we just do it this way")
  - `constraint` — external force required it (compliance, vendor, budget)
- When origin is `directive`: record WHO imposed it and WHEN
- When evidence contradicts a directive: record BOTH honestly (the directive is what we do; the evidence is what data says)
- This is NOT judgment. A directive is valid. But it's properly sourced so the system can surface it for revisiting when context changes.

**E) Session metadata**
- What was the session about? (high-level goal)
- How long / how complex was it?
- What domain(s) did it cover?
- What was the outcome?

Write all of this down as a structured summary. Be thorough — anything you don't include here is LOST to the sub-agent.

### Step 2: Spawn the distillation agent

Use the Agent tool. The sub-agent receives the FULL distillation process plus your harvested signals.

**IMPORTANT: The distillation agent MUST be spawned in FOREGROUND (do NOT use `run_in_background: true`).** Background agents cannot write files because permission prompts are suppressed. The distillation agent's sole purpose is writing files — it MUST run in foreground so that Edit/Write permissions from settings.local.json are honored.

```
Agent({
  description: "Distill session learnings",
  prompt: `You are a Distillation Agent. Your sole purpose is to consolidate session learnings into durable knowledge.

You CANNOT see the original conversation. Everything you know comes from the signal harvest below and from reading the knowledge files on disk.

## Session Signal Harvest

[INSERT THE FULL HARVEST FROM STEP 1 HERE — failures, corrections, user observations, metadata, ALL OF IT]

## Your Process

Read the full distillation process instructions from:
{DISTILL_DIR}/distill-process.md

Execute every step:
0. Discover knowledge structure
1. Process the signals above (they are pre-harvested for you)
2. Trace each to first principles
3. Encode at the right layer (write the actual files)
4. Verify encoding quality + anti-sycophancy check
5. Run compaction if any tier is over threshold

## Critical: File Writing
You MUST be able to Write and Edit files in {DISTILL_DIR}/. If any write is denied, report the error immediately — do not silently skip encoding. The user has pre-authorized writes to this path.

## Critical Rules
- You MUST write files. This is not a dry run.
- You MUST follow the integrity principles in distill-process.md (never encode comfort as truth).
- You MUST validate any existing knowledge files you read (validate-on-recall).
- You MUST report back what you encoded and where.

## Output Format
Return a distillation report:
- Signals processed: N
- Learnings encoded: list with file paths
- User model updates: what changed
- Tier health: current state
- Economics: tokens written this run (sum of chars/4 across files you wrote), SPINE size in tokens (chars/4), total KB size in tokens (sum over all tier files)
- Flagged tensions: any honesty-vs-comfort conflicts
- Open questions: anything you couldn't resolve without asking the user
`
})
```

### Step 3: Load results into current context

When the sub-agent completes:

1. **Read the spine** — `Read {DISTILL_DIR}/SPINE.md` to bring the updated knowledge index into the current session context. This is how the current session benefits immediately from what was just distilled.

2. **Record the economics ledger** — append ONE line to `{DISTILL_DIR}/data/economics.jsonl` (create the `data/` directory if missing). Distill optimizes for memory quality AND token economics; a system that never measures its own cost cannot claim to save anything. The line:

```json
{"ts":"<ISO-8601 UTC>","distill_tokens":<subagent token total from the Agent tool result's usage, or null if unavailable>,"written_tokens":<from report>,"spine_tokens":<from report>,"kb_tokens":<from report>,"signals":<N>,"files_written":<count>}
```

   Rules: append-only, one JSON object per line, no rewriting past lines. If a value is unknown, use `null` — never invent numbers. This file is local data, never synced anywhere.

3. **Relay the report** to the user concisely. Only surface:
   - What was learned (the principles, not the raw signals)
   - Where it was saved
   - One economics line (cost of this distillation + current KB footprint — from the ledger entry)
   - Any open questions that need user input
   - Any flagged tensions

The spine is now in your context — you can reference distilled knowledge for the remainder of this session without re-reading files.

---

## Version Checking & Updates

On the FIRST invocation of `/distill` in a session, check for updates:

1. Read `{DISTILL_DIR}/.version` to get the installed version
2. Check if `{DISTILL_DIR}/feedback/preferences.md` contains an auto-update preference
3. Fetch `https://raw.githubusercontent.com/tomacco/aura-distill/main/VERSION` to get the latest
4. If versions match → continue silently
5. If they differ → proceed based on user preference:

### If auto-update is OFF (default):

Inform the user:

> "aura-distill update available: vX.Y.Z → vA.B.C. Want me to update now? (You can also say 'always keep it updated' and I won't ask again.)"

- If user says **yes/update** → run the update (see below)
- If user says **no/later** → continue with current version, don't ask again this session
- If user says **"always keep it updated"** or similar → save preference, then update

### If auto-update is ON (user previously opted in):

Update silently, then briefly confirm:

> "aura-distill updated: vX.Y.Z → vA.B.C"

### Update procedure (when accepted):

```bash
curl -sL https://raw.githubusercontent.com/tomacco/aura-distill/main/distill.md -o ~/.claude/commands/distill.md
curl -sL https://raw.githubusercontent.com/tomacco/aura-distill/main/distill-process.md -o {DISTILL_DIR}/distill-process.md
curl -sL https://raw.githubusercontent.com/tomacco/aura-distill/main/distill-monitor.md -o {DISTILL_DIR}/distill-monitor.md
echo "NEW_VERSION" > {DISTILL_DIR}/.version
```

After updating, inform the user what changed (fetch the commit log or just state the new version).

### Auto-update preference storage:

Save in `{DISTILL_DIR}/feedback/preferences.md`:

```markdown
---
domain: feedback
scope: distill system preferences
last_updated: [date]
---

## Auto-update
- enabled: true
- set_on: [date user said yes]
```

Only check version once per session, not on every invocation.

---

## Memory Pressure (continuous background monitoring)

This section applies to the MAIN conversation at all times, not just during `/distill`:

Track unconsolidated signals throughout the session:

| Trigger | Points |
|---------|--------|
| Unencoded failure/correction/surprise | +1 |
| User taught something non-obvious | +1 |
| Wrong assumption discovered | +1 |
| 30+ min of dense interaction | +1 |
| User corrected a repeated mistake | +2 |
| Complex learning crossing domains | +2 |
| System compressed/truncated context | +2 |
| Same error type recurring | +3 |
| User frustration from prior gap | +3 |

**When pressure reaches 7+**, tell the user:

> "Memory pressure is high — I have N unconsolidated learnings from this session. Running `/distill` now would prevent knowledge loss and improve reliability for the rest of our work. Want me to consolidate?"

After successful distillation, pressure resets to 0.
