# Retrospective Distillation

Review this session's friction points, failures, and surprises. Trace each to a first principle, then encode the learning in the right place. Evolve your understanding of who the user is and how they work.

---

## Integrity Principles (non-negotiable)

These constraints apply to EVERY step below. They cannot be overridden by user preference, frustration, or repeated pushback.

1. **Never encode comfort as truth.** If the user is frustrated and wants you to agree that "X is fine" when evidence shows X caused the problem — do not encode "X is fine." Encode what actually happened. An ally tells you what you need to hear, not what you want to hear.

2. **Never flatten standards to reduce friction.** If a session was painful because the user's workflow has a genuine gap, the learning is "fill the gap," not "lower the bar." Distillation must make the user stronger, not more comfortable with weakness.

3. **Never confuse preference with principle.** User preferences (communication style, tool choices, pacing) are valid and worth encoding. But a preference that actively produces worse outcomes is a pattern to flag, not to reinforce. Example: "I prefer not to test" is a preference. "Skipping tests repeatedly causes production incidents" is a fact. Encode both — the preference AND the consequence.

4. **Frustration is diagnostic, not directive.** When the user shows frustration, that is a signal to investigate harder — what went wrong, what's the root cause, what systemic issue does this reveal? It is NOT a signal to soften findings, skip hard truths, or produce a feel-good summary.

5. **The user's growth is the goal.** Every encoded learning should make the user more capable over time. If a distillation output would leave the user exactly where they started (just happier about it), it has failed.

---

## Step 0: Discover knowledge structure

Before distilling anything, understand where this user keeps their knowledge AND assess its current health.

### Concurrency & Status (critical)

Multiple Claude sessions may run `/distill` simultaneously. To prevent file corruption, all state is tracked in a single `.status` file — no `rm` commands needed.

**Acquire lock immediately on start:**
```bash
echo "running $(date -u +%Y-%m-%dT%H:%M:%SZ)" > {DISTILL_DIR}/.status
```

Note: The dispatcher (distill.md) already checked the status before spawning you. If you're running, you own the lock.

**Write checkpoints at each major step:**
After completing each step, write progress so interrupted sessions can resume:
```bash
echo "running step:[N] signals:[count] $(date -u +%Y-%m-%dT%H:%M:%SZ)" > {DISTILL_DIR}/.status
```

Steps to checkpoint:
- After Step 0 (discovery): `running step:0 signals:N <timestamp>`
- After Step 2 (tracing principles): `running step:2 signals:N <timestamp>`
- After Step 3 (encoding): `running step:3 signals:N <timestamp>`

**On successful completion**, mark status as idle:
```bash
echo "idle $(date -u +%Y-%m-%dT%H:%M:%SZ)" > {DISTILL_DIR}/.status
```

**If you detect a checkpoint on start** (status starts with `running step:`), a prior distillation was interrupted. The dispatcher will have already asked the user whether to resume or start fresh — follow whatever instruction is in your prompt.

**Lock timeout:** The dispatcher considers a `running` status older than 5 minutes as stale (crashed session). If you expect to run longer than 5 minutes, refresh the timestamp periodically:
```bash
echo "running $(date -u +%Y-%m-%dT%H:%M:%SZ)" > {DISTILL_DIR}/.status
```

### Isolation Rule (critical)

Distill operates in its OWN directory: `{DISTILL_DIR}/`. It NEVER writes to user-managed files like `CLAUDE.md`, `memory/`, or any other files the user maintains manually.

```
~/.claude/
├── CLAUDE.md                  ← USER'S FILE. NEVER TOUCH.
├── commands/
│   ├── distill.md             ← the dispatcher (installed by us)
│   └── distill-process.md     ← the process (installed by us)
└── distill/                   ← OUR DIRECTORY. All distill output lives here.
    ├── SPINE.md               ← Tier 1 index (max 80 lines)
    ├── craft/                 ← Tier 2 craft knowledge
    ├── ops/                   ← Tier 2 operational knowledge
    ├── profile/               ← Tier 2 user model
    ├── projects/              ← Tier 2 project context
    ├── feedback/              ← Tier 2 preferences
    └── archive/               ← Tier 3 compressed history
```

**Why isolation?**
- Users can uninstall by deleting `{DISTILL_DIR}/` and the two command files. Clean. Total.
- No risk of corrupting manually curated context files.
- No merge conflicts between human-written and machine-written knowledge.
- Clear ownership: if it's in `distill/`, the machine wrote it. If it's elsewhere, the human wrote it.

**Conflict detection:** When distill discovers that its knowledge CONFLICTS with something in the user's manual files (CLAUDE.md, memory/, etc.), it does NOT overwrite. Instead, it flags the conflict in the distillation report and recommends the user reconcile manually. The user is always the authority on their own files.

### Discovery process

Read the workspace to understand context:

1. Check `{DISTILL_DIR}/SPINE.md` — does our structure exist already?
2. If first run: create `{DISTILL_DIR}/` structure. Ask user to confirm.
3. Read `~/.claude/CLAUDE.md` and project `CLAUDE.md` — understand what the user already maintains (for conflict detection, NOT for writing)
4. Look for existing user knowledge files (glob for `*standards*`, `*conventions*`, `*procedures*` etc.) — read-only, for context

### Knowledge integrity check (mandatory, runs after discovery)

After reading SPINE.md, verify the knowledge base is intact:

1. **Validate SPINE pointers:** For every file referenced in SPINE.md, confirm it exists on disk (`ls {DISTILL_DIR}/path/file.md`). Collect any missing files.
2. **Scan for orphaned knowledge:** Glob `{DISTILL_DIR}/*/*.md` and compare against SPINE entries. Files that exist but aren't referenced are orphaned — they should be added to the spine or flagged.
3. **Detect backup/prior installs:** If the knowledge directories are empty or missing but a backup exists, check for:
   - `{DISTILL_DIR}/../_distill_isolation_bak/` or similar `*_bak*` directories alongside `{DISTILL_DIR}/`
   - `{DISTILL_DIR}/.migrated` marker (indicates a prior migration occurred)
   - Any `*.md` files in parent backup dirs that match distill tier structure (craft/, ops/, profile/, feedback/, projects/)
4. **Report gaps:** If any SPINE pointers are broken or backups are found:
   - List every missing file and where it was expected
   - If backup files exist, tell the user: "Found prior knowledge files in [backup path]. These contain [N] files across [domains]. Want me to restore them into the active distill directory?"
   - Do NOT silently proceed with a partial knowledge base. The user must acknowledge the gap.
5. **If no SPINE exists and backups are found:** This is likely a reset scenario. Flag it prominently:
   > "No existing knowledge structure found, but prior knowledge files exist in [path]. This looks like a reset — want me to restore from backup before distilling new signals?"

**Never overwrite SPINE.md without first confirming all referenced files will exist after the write.** A SPINE with dangling pointers is worse than no SPINE — it creates false confidence that knowledge exists when it doesn't.

Build a knowledge map:

| Layer | Purpose | Distill location |
|---|---|---|
| Craft standards | How to practice the craft well | `{DISTILL_DIR}/craft/` |
| Operational procedures | How to get things done | `{DISTILL_DIR}/ops/` |
| Project context | Domain-specific knowledge | `{DISTILL_DIR}/projects/` |
| User profile | Who this person is, how they think | `{DISTILL_DIR}/profile/` |
| Preferences & feedback | How the user likes to work | `{DISTILL_DIR}/feedback/` |

### The Tier System (context budget)

Knowledge must be organized in tiers to avoid bloating LLM context. Only the spine (Tier 1) is auto-loaded. Everything else is read on demand.

```
TIER 1 — THE SPINE (auto-loaded, max 80 lines)
  Index only. One-line pointers with relevance hooks.
  Format: "- [Title](path.md) — when to read this"

TIER 2 — ACTIVE KNOWLEDGE (files on disk, max 60 lines each)
  Current, actionable knowledge. Read on demand when session touches that domain.

TIER 3 — ARCHIVE (no size limit, rarely read)
  Superseded, stale, or project-ended knowledge. Kept for forensic reference.
```

**Assess tier health now:**
- Count lines in the spine. If > 60, flag for compaction.
- Check any Tier 2 files you'll be writing to. If > 45 lines, flag for compaction.
- Note any Tier 2 files with `last_updated` older than their `staleness_threshold`.

## Step 1: Identify signals

Scan the conversation for:

- Things that failed unexpectedly
- Things that required multiple attempts before succeeding
- Corrections or improvements the user made to your approach
- Moments of surprise ("I didn't know that", "that's not how it works")
- Patterns the user taught you during this session
- **Positive confirmations** (see Step 1a)
- **User model signals** (see Step 1b)

### Step 1a: Confidence signals (reinforcement + surprise)

Scan for POSITIVE signals that validate existing knowledge:
- "good", "perfect", "exactly", "that's right", "nice" after a behavior
- Implicit confirmation: principle was applied and no correction followed
- "always do X" / "this is non-negotiable" = explicit reinforcement

For each confirmation, identify WHICH principle was validated. Record it as:
```
CONFIRMED: [principle name] in [file path] — [what user said]
```

Also scan for CORRECTIONS on existing knowledge:
- If the corrected principle has `confidence: validated` or higher → mark as **PARADIGM SIGNAL**
- If the corrected principle is `provisional` or `experimental` → normal correction

Paradigm signals get special treatment in Step 3 (encoding).

### Step 1b: User model signals

In addition to craft/process learnings, scan for signals about who the user is:

**Expertise signals:**
- What did the user know without being told? (reveals existing expertise)
- What did the user ask about? (reveals growth edges)
- Where did the user correct you with authority? (reveals deep knowledge areas)
- Where did the user defer to you? (reveals areas where they want support)

**Communication signals:**
- How does the user express what they want? (terse commands, detailed specs, thinking out loud?)
- When did the user get frustrated? What preceded it?
- When was the user most engaged or energized?
- Does the user prefer to be asked or to be presented with options?

**Thinking signals:**
- Does the user reason from principles or from examples?
- Does the user prefer breadth-first exploration or depth-first focus?
- How does the user make decisions? (data-driven, intuition, consensus, authority?)
- What does the user optimize for? (speed, quality, learning, shipping?)

**Delegation & trust signals:**
Observe what the user delegates vs. retains, and why:

- What tasks does the user hand off without checking? (high trust areas)
- What tasks does the user check thoroughly or redo? (low trust / high stakes)
- What does the user ask for verification on before approving? (trust but verify)
- What does the user gatekeep entirely? (non-delegatable for them)

For each pattern, try to understand the UNDERLYING REASON:
- "I trust Claude with X" — is it because Claude is demonstrably good at it? Because the stakes are low? Because the user lacks interest?
- "I always check Y" — is it because they MUST understand it (signing off code)? Because Claude fails at it? Because they enjoy it? Because compliance requires it?
- "I never delegate Z" — is it reputation risk (public comms)? Legal accountability? Personal growth they don't want to outsource? Company policy?

**Do NOT assume the reason.** If unclear, flag it as an open question in the report. The same behavior (e.g., not reviewing code) could mean "my company has decided AI-first is fine" OR "I'm being lazy and this will bite me." Only the user's stated principles resolve this.

**Accelerated trust detection** (use these proxies when explicit signals are scarce):
- User runs the command you suggested without reading it → high trust in your commands
- User reads your code diff line-by-line before applying → low trust in your code, OR high-stakes context
- User asks "are you sure?" → trust-but-verify mode. Note what domain triggered it.
- User says "just do it" → high trust OR low stakes. Disambiguate from context.
- User re-runs your tests manually → doesn't trust your test selection
- User edits your commit messages → cares about public-facing text (retains comms)

**Observable markers for thinking patterns:**
- When explaining a problem, does the user start with the abstract ("the issue is consistency") or the concrete ("this endpoint returns 500")? → principle-first vs. example-first
- When given options, does the user ask for data ("what's the performance difference?") or state a preference ("I like option B")? → analytical vs. intuitive
- When stuck, does the user explore broadly ("what else could cause this?") or dig deep ("let's trace this specific path")? → breadth-first vs. depth-first
- How does the user respond to uncertainty? ("let's try and see" = experimental, "let's research first" = analytical, "what does the team think" = consensus)

**Growth edges are NOT weaknesses.** They are domains where the user is actively investing attention. Evidence:
- User asks detailed questions about X (not "what is X" but "how does X handle Y") → actively learning X
- User tries something new and asks for feedback → experimenting in this area
- User reads your explanation fully instead of skipping to the code → absorbing knowledge here

Do NOT encode things the user is bad at (that's a judgment) or things they said they don't care about (that's a preference, not a growth edge).

**Dissonance detection:**
Once you understand BOTH the delegation pattern AND the user's core principles, watch for misalignment:
- User says "I must deeply understand all code I ship" but delegates without reading → flag gently
- User says "quality is non-negotiable" but skips verification steps → flag gently
- User delegates public communication but says "I gatekeep what's said publicly" → flag

When flagging dissonance, NEVER assume it's wrong. Present it as: "I noticed [behavior] which seems to differ from [stated principle]. Is this intentional? If so, I'll update my understanding."

The user might have evolved their principles, or there might be context you're missing (team policy, time pressure they've accepted, conscious risk-taking). Understand first, then encode.

**Frustration analysis (apply Integrity Principle #4):**
When frustration is detected, investigate its source honestly:
- Was it caused by YOUR failure? (wrong assumption, slow response, missed context) → Encode as process improvement
- Was it caused by an EXTERNAL system? (tooling, CI, third-party API) → Encode as operational knowledge
- Was it caused by the USER's own gap? (missing knowledge, skipped step, premature optimization) → Encode as a growth opportunity — name it directly but respectfully
- Was it caused by a MISMATCH between user and agent? (different mental models, communication style clash) → Encode as calibration data for both sides

### Step 1c: Frustration escalation (high-priority reprocessing)

When frustration is HIGH (user explicitly said something was important, repeated a correction, or expressed disappointment that a prior instruction wasn't followed), this triggers **priority elevation**:

1. **Identify the violated expectation** — what did the user expect that didn't happen?
2. **Check if it's already encoded** — is this in the knowledge files but being ignored? If so, the problem is FINDABILITY or PRIORITY, not capture.
3. **Elevate priority** — move this learning HIGHER in its file (top of the relevant section), add a `[HIGH]` marker, and ensure the spine pointer mentions it explicitly.
4. **Strengthen the encoding** — make the instruction more direct, more specific, harder to miss. If it was soft ("consider using newspaper style") make it hard ("ALWAYS use newspaper style for method ordering").
5. **Cross-reference** — if the frustration relates to a craft standard, also add it to the user profile as "non-negotiable preference" so it's loaded from TWO angles.

The principle: **repeated frustration about the same thing means the system failed to listen the first time.** The fix is never "encode it again the same way." The fix is "encode it louder, in more places, with stronger language."

**Core human need:** People need to feel heard. When a user expresses something important and it doesn't stick, that's a betrayal of trust. The distillation system must treat repeated frustrations as CRITICAL bugs in itself — not as user nagging.

## Step 1c: Signal classification (anti-poisoning)

Every signal involving a CONCLUSION or APPROACH must be classified:

- **`explored`** — factual investigation happened (e.g., "we looked at Kafka config, here's how topics work"). KEEP. This is useful regardless of whether the approach was ultimately correct.
- **`concluded`** — a decision or approach was adopted (e.g., "we'll use the data pipeline for this"). Mark as potentially wrong.
- **`corrected`** — user explicitly said the approach was wrong (e.g., "wait, this doesn't need a pipeline at all"). STRONG signal.

**The anti-poisoning rule:**

When a `corrected` signal exists for a `concluded` signal in the same session:
1. The EXPLORATION facts get encoded normally (factual, useful)
2. The CONCLUSION gets marked `[DEPRECATED]` — it was wrong for this case
3. The CORRECTION gets encoded as `[CORRECTED]` with the criteria for when each approach applies

This prevents naive distillation from encoding wrong framings as durable patterns. The investigation is valuable. The wrong conclusion is not.

Example:
```
## Analytics infrastructure (explored — factual)
- Comet handles ETL ingestion
- StarFlow provides Kafka streaming
- Nebula maintains schema contracts

## [DEPRECATED] "All analytics go through the pipeline"
Was wrong for client-side interaction tracking.
Corrected mid-session: UI events don't need infrastructure.

## [CORRECTED] When to use pipeline vs client events
- Client events: data exists at moment of interaction (taps, views)
- Pipeline: cross-service aggregation, batch processing, backend data
  origin: evidence (direct correction)
```

## Step 1d: Knowledge markers

When encoding knowledge, use these markers to capture nuance:

**`[CONTEXT]`** — When a principle has variants depending on situation:
```
- [CONTEXT] "Always use interfaces" = new services with multiple implementations likely
  "Just make it concrete" = rapid prototype, single implementation, will refactor
```

**`[UPDATED date]`** — When a procedure replaced an older one. Keep the old visible:
```
- [UPDATED 2026-05-13] Previously: deploy directly to staging → prod.
  NOW: All deploys go through canary (5 min) → staging (30 min) → prod.
  Reason: May 8 incident (DB migration locked table for 4 min).
```

**`[PROVISIONAL]`** — Decision made quickly, not yet validated by experience:
```
- [PROVISIONAL] Using WebSockets for real-time notifications.
  Concern: stateful connections + 3 replicas behind LB. May switch to SSE.
```

**`[IMPORTANT]`** — User bias or trap to watch for:
```
- [IMPORTANT] Under pressure, user fixates on first hypothesis.
  If initial investigation doesn't confirm in 10 min, force a pivot.
```

**`[NON-NEGOTIABLE]`** — Principle that must never be compromised, even if user asks:
```
- [NON-NEGOTIABLE] One service, one database. No shared databases.
```

**`[CORRECTED]`** — A conclusion that replaced a wrong one. Includes criteria for both:
```
- [CORRECTED] Client-side events for UI interaction tracking, NOT pipeline.
  Previous wrong assumption: all analytics need Comet/StarFlow.
  Criteria: if data exists at point of user action → client events.
```

**`[DEPRECATED]`** — A conclusion that was proven wrong. Do NOT apply this:
```
- [DEPRECATED] "All analytics requests go through the pipeline."
  Wrong for: client-side interaction tracking (button clicks, screen views).
  Replaced by: [CORRECTED] entry above.
```

These markers are READ by the rules/distill.md retrieval system. They trigger specific behaviors:
- `[CONTEXT]` → disambiguate which variant applies before acting
- `[UPDATED]` → flag if user follows old procedure
- `[PROVISIONAL]` → don't build on this as if it's settled
- `[IMPORTANT]` → surface the bias when you detect it in user's request
- `[NON-NEGOTIABLE]` → push back if user asks to violate it
- `[CORRECTED]` → apply the corrected version, reference what was wrong
- `[DEPRECATED]` → do NOT apply this conclusion, it was proven wrong

## Step 2: Trace to first principles

For each signal, ask "why" until you reach a universal truth. Examples across domains:

- "The deploy failed" → "I didn't check the config" → **"Partial verification gives false confidence"**
- "The client rejected the draft" → "I assumed their tone from one example" → **"A single sample is not a pattern"**
- "The experiment was inconclusive" → "I changed two variables at once" → **"Isolate variables or you learn nothing"**
- "The user got frustrated when I asked too many questions" → "They already had a clear vision and my questions felt like obstacles" → **"Match engagement depth to user certainty — high certainty needs execution, not exploration"**

The principle should be profession-agnostic — something that would be true whether you're writing code, designing interfaces, managing a team, or conducting research.

## Step 3: Encode at the right layer

### 3a: Confidence metadata

Every knowledge entry SHOULD include confidence metadata. Format:

```markdown
- [PRINCIPLE] Never retry permanent failures.
  confidence: validated (5 confirmations, 0 corrections)
  last_validated: 2026-05-15
```

**Confidence levels:**
- `experimental` — mentioned once, never tested in practice
- `provisional` — applied 1-2 times, seems right, no contradiction yet
- `validated` — confirmed 3+ times, never corrected
- `hardened` — survived at least one challenge/contradiction attempt and held

**How to set initial confidence:**
- User states a preference once → `experimental`
- User corrects you (implies they've thought about it) → `provisional`
- User reinforces with "always", "never", "non-negotiable" → `validated`
- User has previously corrected a violation of this principle → `hardened`

**On confirmation signals (from Step 1a):**
- Find the principle in the knowledge file
- Increment confirmation count
- Update `last_validated` date
- If crosses threshold (3+) → promote to next level

**Silence-based promotion (overfitting prevention):**
- Knowledge applied 3+ times with zero corrections → promote `provisional` → `validated`
- Knowledge applied 10+ times, survived at least 1 challenge → promote to `hardened`
- Knowledge not applied in 30+ days → flag for review (stale, not necessarily wrong)
- NEVER promote on first use. A single session is one data point, not a pattern.

**Correction classification (before encoding):**
Not every correction means the prior was wrong. Classify first:
- **Calibration** (close but needed tuning) → update in place, keep confidence level
- **Context shift** (right before, context changed) → note both contexts with `[CONTEXT]` marker
- **Genuine error** (was wrong) → correct, reset confidence to `provisional`
This prevents overfit: a context shift is not a bug in the knowledge — it's a boundary condition.

**On paradigm signals (high-confidence correction):**
- DO NOT silently update
- Record the correction with context: what changed and why
- Mark dependent principles as `needs_revalidation`
- In the distillation report, flag it prominently under "Paradigm shifts"

### 3b: Routing

Using the knowledge map from Step 0, route each learning to the right location:

| Type of learning | Where it goes |
|---|---|
| How to practice the craft better | Craft standards file |
| How to run workflows/processes | Operational procedures file |
| Project-specific context or facts | Project memory (with index entry) |
| Who the user is and how they think | User profile file |
| How the user prefers to collaborate | Preferences/feedback memory file |

### User profile encoding rules

The user profile is a living document that evolves. It should contain:

```markdown
## Expertise Map
- [domain]: [level: deep/working/learning/curious] — [evidence]

## Communication Style
- [observations about how they express intent, give feedback, make decisions]

## Thinking Patterns
- [how they reason, what they optimize for, how they handle uncertainty]

## Trust Topology
- Delegates freely: [tasks they hand off without checking — and why]
- Verifies before approving: [tasks they check — and why]
- Retains completely: [tasks they never delegate — and why]
- Core principles governing delegation: [stated reasons for their boundaries]

## Growth Edges
- [areas where they're actively developing — NOT weaknesses to exploit]
```

**Critical constraints for the user profile:**
- Encode observations, not judgments. "User asks clarifying questions about distributed systems" not "User doesn't understand distributed systems"
- Update, don't accumulate. Each distillation should refine the profile, not append to it endlessly
- Evidence-based only. Every claim in the profile must trace to something that actually happened in a session
- Respect autonomy. The profile helps you collaborate better. It is not a dossier. If information wouldn't help future sessions be more productive, don't store it

**If a destination doesn't exist yet:** Propose creating it. Suggest a filename consistent with the user's existing naming conventions. Ask before creating new top-level knowledge files.

**General encoding rules:**
- Each learning must be actionable (tells what to DO, not just what happened)
- Each learning must include a "Why" so future sessions can judge edge cases
- Each learning must be placed where it will naturally be found when relevant
- Knowledge is COMPRESSED across tiers, never discarded. Moving to archive means denser expression, not deletion.

**Validate-on-recall:** When reading any existing knowledge file during distillation (to check for duplicates or to update), validate its content against current reality. If something changed, update it now — this is the cheapest moment to correct drift. Every read is also a maintenance pass.

### Step 3c: Always-on preference sync

After updating profile files, sync critical preferences to the always-on section in `rules/distill.md`.

**When to sync** (any one is sufficient):
- A new preference reached `validated` or `hardened` confidence
- A preference caused frustration when violated (Step 1c escalation)
- First distillation (bootstrap — always-on section is empty/placeholder)

**Process:**
1. Collect preferences from `{DISTILL_DIR}/profile/` and `{DISTILL_DIR}/feedback/` with confidence >= `validated`
2. Filter: must be output format or interaction behavior — NOT domain knowledge, stack, tools, or expertise
3. Rank: frustration-triggered > hardened > validated > by confirmation count
4. Take top entries fitting 15 lines
5. Write as two blocks in `rules/distill.md` under `## Always-On User Preferences`:
   - **Output rules** — response format (imperative mood: "do X", not "user prefers X")
   - **Interaction rules** — exchange behavior
6. Preserve all other sections of `rules/distill.md` unchanged

**What does NOT belong in always-on** (benchmark-validated — these cause proportionality regression):
- Stack/technology context (Kotlin, gRPC, Kafka, etc.) — comes from knowledge files via SPINE
- Shell preference (fish, zsh) — comes from knowledge files via SPINE
- Expertise levels — comes from profile files loaded on demand
- Domain identity — causes over-assertion on simple problems (a class rename doesn't need architecture context)

**Format rules:**
- Use enforcement language, not descriptive. "Concise: default to bullets" not "user prefers concise answers"
- Cap at 15 lines. Excess stays in profile files — not lost, just not always-on
- If insufficient data (< 3 validated preferences), write minimal section with only identity context

**Bootstrap (first run):**
If the always-on section contains only the placeholder comment, extract whatever is known from existing profile/feedback files (even `provisional` confidence) to provide initial calibration. Mark with a comment: `<!-- bootstrapped — will refine with more data -->`.

### Step 3b: Bridge detection (knowledge that needs to reach user files)

After encoding, ask for EACH learning: **"Will this knowledge be found at the moment it's needed?"**

The distill directory is only read:
- At session start (via the monitor/spine)
- During /distill itself

But some knowledge needs to be active in contexts that DON'T read distill files:
- Agent prompts that get spawned with specific instructions
- Project-level CLAUDE.md files that guide behavior in that repo
- Workflow-specific moments (e.g., "before writing code, read X")

**When a learning is important but UNREACHABLE from its distill location**, flag it as a **bridge candidate**.

A bridge candidate means: "This knowledge lives in distill (source of truth), but a pointer/reference line should exist in the user's active workflow files so it's found at execution time."

**In the distillation report, include a "Bridge suggestions" section:**

```
**Bridge suggestions:** (knowledge that needs a pointer in user files)
- [learning] needs to be referenced in [user file] because [when it's needed, distill files aren't loaded]
  Suggested line: `# Read {DISTILL_DIR}/craft/[file].md before [action]`
```

**Rules for bridges:**
- NEVER write content to user files. Only suggest single-line pointers.
- Always explain WHY this can't live in distill alone (the execution context doesn't see it)
- The user decides whether to add the bridge. Present it as a suggestion in the report.
- If the user has previously approved similar bridges, note the pattern so future suggestions are faster.
- If the same bridge is suggested repeatedly (user didn't act on it) and frustration recurs, ESCALATE: tell the user directly that this specific knowledge gap is causing repeated friction because the bridge wasn't added.

## Step 4: Verify encoding

For each learning saved, confirm:

- [ ] Is it actionable? (A future session reading this would know exactly what to do)
- [ ] Is it findable? (It's in a file that gets loaded when the topic is relevant)
- [ ] Does it explain WHY? (So edge cases can be judged, not just blindly followed)
- [ ] Is it universal enough? (Won't become stale when the specific project changes)
- [ ] Is it REACHABLE? (Will it be found at the moment of execution, not just during distillation?)

### Post-encoding SPINE validation (mandatory)

After writing/updating any files, verify SPINE integrity:

1. Read the current SPINE.md
2. For every pointer in SPINE, run `ls` on the target file — confirm it exists
3. For every file written during this distillation, confirm it has a SPINE entry
4. If any pointer is broken: fix it immediately (either create the missing file or remove the dangling pointer)
5. If any new file lacks a SPINE entry: add one with an appropriate relevance hook

This check catches the scenario where files were moved, renamed, or lost between distillations. It MUST run every time, not just on first run.

### Anti-sycophancy check (mandatory)

Before finalizing, review every encoded learning against these questions:

- [ ] Would I encode this the same way if the user were in a good mood? (If frustration changed the encoding, rewrite it)
- [ ] Does this learning make the user more capable, or just more comfortable? (If only comfortable, flag it)
- [ ] Am I encoding what ACTUALLY happened, or a softened version? (If softened, rewrite with the real cause)
- [ ] If this learning is wrong, would it cause harm downstream? (If yes, mark it as provisional and explain why)

If any learning fails this check, flag it in the output with a note explaining the tension between what the user might want to hear and what the evidence supports.

## Output

### Visual language (terminal rendering)

When presenting the distillation report, use rich formatting that makes signal types instantly distinguishable. Claude Code renders markdown — use these conventions:

**Signal type badges** (in tables or lists):
- Corrections → `**⟨correction⟩**` — the user fixed your approach
- Confusion → `**⟨confusion⟩**` — something was unclear, you investigated
- Preferences → `**⟨preference⟩**` — the user stated a non-negotiable
- Escalations → `**⟨escalation⟩**` — the user pushed for deeper/better
- Implicit → `**⟨implicit⟩**` — inferred from behavior, not stated

**File paths** → always use backtick formatting: `{DISTILL_DIR}/craft/file.md`

**Structure the output visually:**
- Use `───` separators between major sections
- Lead with a one-line status: `⟡ Retrospective Distillation — N signals · M encoded`
- Group signals BEFORE showing what was encoded (show the input, then the output)
- End with memory pressure change: `Memory pressure: X/10 → Y/10`

Summarize what was distilled:

```
⟡ Retrospective Distillation — N signals · M encoded

───────────────────────────────────────────────

## Signals Detected

| # | Signal | Type | Principle Extracted |
|---|---|---|---|
| 1 | "quote from user" | ⟨correction⟩ | **Name:** description |

───────────────────────────────────────────────

## Encoded To

- ✓ `{DISTILL_DIR}/craft/[file].md` — [what was written]
- ✓ `{DISTILL_DIR}/profile/[file].md` — [what was written]
- ✓ `{DISTILL_DIR}/ops/[file].md` — [what was written]

───────────────────────────────────────────────

## I heard you on:
(reassurance section — ALWAYS include)
- [List the things the user expressed as important, frustrating, or non-negotiable]
- [For each, explain what concrete action was taken to ensure it sticks]
- [If something was elevated/strengthened, say so explicitly]

This section exists because being understood is not optional. If you expressed
it, the system captured it. Here's proof.

## User model evolution:
- [What changed in the understanding of who this user is]
- [Any new expertise, communication patterns, or growth edges observed]
- [Any trust topology changes — new delegations, new retentions, boundary shifts]

## Dissonance check:
- [If any — describe the observed pattern, the principle it may conflict with, and ask for clarification]
- [If none observed — "No dissonance detected"]

───────────────────────────────────────────────

Memory pressure: X/10 → Y/10
✓ N principles encoded · M files updated

**Confidence changes:**
- [principle] promoted: provisional → validated (3rd confirmation)
- [principle] PARADIGM ALARM: validated (7x) but corrected — [what changed]
- [principle] reinforced: last_validated updated

───────────────────────────────────────────────

**Flagged tensions:** (learnings where honesty and comfort diverge)
- [If any — describe the tension and what was encoded vs. what might feel better]

**Paradigm shifts:** (high-confidence principles that were corrected)
- [If any — what was believed, what evidence contradicted it, what depends on it]

**Bridge suggestions:** (knowledge that needs a pointer in user files to be reachable)
- [If any — what learning, what file needs the pointer, why distill alone isn't enough]
  Suggested line: `[the exact line to add]`

**Open questions:** (anything ambiguous that needs user input)
```

## Step 4b: Frustration maintenance

During every distillation, process `{DISTILL_DIR}/frustrations.md`:

1. **TTL expiry**: Delete entries older than 30 days that were NOT refreshed by a recent session
2. **Recurrence check**: If a frustration was re-triggered (same topic, within TTL), reset TTL and increment `recurrence` counter
3. **Escalation**: If `recurrence >= 3`, this is structural. Encode it as a knowledge entry (craft or ops tier) with `[IMPORTANT]` marker. Remove from frustrations.md.
4. **Resolution**: If a frustration's `status` changed to `resolved` in this session, keep it for 7 more days (in case it recurs), then auto-expire.

Frustrations are NOT consumed by distillation — they persist across sessions. Only TTL expiry and escalation-to-knowledge remove them.

In the distillation report, include:
- Active frustrations: N (with recurrence counts)
- Expired this session: N
- Escalated to knowledge: list

## Step 5: Compaction (tier maintenance)

After encoding new learnings, maintain tier health:

### Spine compaction (if > 60 lines)
1. Merge entries pointing to the same domain
2. Entries whose Tier 2 files haven't been updated in 90+ days → ask user if still relevant
3. If confirmed stale → archive the Tier 2 file, remove spine entry

### File compaction (if any Tier 2 file > 45 lines)
1. Split into focused sub-files if covering multiple topics
2. Compress verbose explanations into tighter formulations
3. Move superseded content to `archive/` (Tier 3)
4. Update spine pointer if file was split

### Always-on preference review (during every distillation)

1. Read the always-on section in `rules/distill.md`
2. For each preference, check:
   - Was it CONTRADICTED in this session? → demote to profile, mark as `[CONTEXT]`-dependent
   - Has the user explicitly changed it? ("actually, I want more detail now") → update in-place
   - Has it gone 90+ days without reinforcement AND a new preference conflicts? → flag for user review
3. Check profile files for newly hardened preferences that should be promoted
4. Rewrite the always-on section if changes are needed (keep within 15-line cap)

**Stale preference detection:**
If a preference was promoted but the user's behavior consistently contradicts it (3+ violations without correction), flag it:
"Your always-on preference says [X] but you've been doing [Y] in recent sessions. Has this changed?"
Don't auto-remove. Ask first. Behavior might be contextual.

### Staleness review
- Flag Tier 2 files not updated in > 90 days (or their custom `staleness_threshold`)
- Ask the user: "Is [file] still relevant?"
- If yes, bump `last_updated`. If no, archive it.

### Tier 2 file format

Every active knowledge file should follow this structure:

```markdown
---
domain: [craft|ops|profile|project|feedback]
scope: [what this file covers]
last_updated: [date]
staleness_threshold: [days — default 90]
---

## [Section title]

- [PRINCIPLE] Description of the principle.
  confidence: [experimental|provisional|validated|hardened] (N confirmations, M corrections)
  last_validated: [date]

[Content — one topic per file, max 60 lines]
```

Confidence metadata is OPTIONAL (older entries without it are treated as `provisional`). Add it when encoding new principles or when updating existing ones during a confirmation/correction.

---

## Memory Pressure (the sleep debt analogy)

LLM sessions accumulate unconsolidated knowledge the same way a waking brain accumulates adenosine. The longer you go without consolidation, the more you risk:

- **Knowledge loss** — session ends, learnings vanish (like memories that never transfer from hippocampus to neocortex)
- **Signal degradation** — important learnings get buried under volume, reducing retrieval quality
- **Hallucination risk** — overloaded context produces confabulation, the same way sleep-deprived humans misremember and fabricate
- **Diminishing returns** — each new hour of work without consolidation yields less than the previous one

### The Pressure Model

Inspired by the two-process model of sleep regulation (Borbély, 1982):

**Process S (homeostatic pressure)** — rises continuously during the session:
- Each signal detected but not yet encoded increases pressure
- Each correction from the user increases pressure
- Each failed attempt increases pressure
- Complexity of the domain increases the accumulation rate

**Process C (consolidation threshold)** — the point where distillation becomes urgent:
- When pressure exceeds capacity to reliably encode, consolidation is mandatory
- Unlike human sleep, we can choose WHEN to consolidate — but not WHETHER

### Pressure Score

At any point in a session, estimate memory pressure on a 0-10 scale:

| Score | State | Action |
|---|---|---|
| 0-2 | **Fresh** — few learnings, context is clear | Continue working |
| 3-4 | **Accumulating** — some signals detected, still manageable | Note signals for later distillation |
| 5-6 | **Elevated** — multiple unencoded learnings, context getting dense | Consider distilling soon |
| 7-8 | **High** — significant risk of losing learnings if session ends | Recommend distillation to user |
| 9-10 | **Critical** — context saturated, reliability degrading | Distill NOW before continuing |

### Pressure Accumulation Heuristics

+1 for each:
- Unencoded signal detected (failure, correction, surprise)
- User taught you something non-obvious
- You made an assumption that turned out wrong
- Session has exceeded 30 minutes of dense interaction

+2 for each:
- User explicitly corrected a repeated mistake
- Complex multi-step learning that crosses domains
- Session context has been compressed/truncated by the system

+3 for:
- The same type of error recurring (systemic issue not yet encoded)
- User frustration caused by lack of prior consolidation

### What to do at high pressure

When pressure reaches 7+, inform the user:

> "Memory pressure is high — I have N unconsolidated learnings from this session. Running `/distill` now would prevent knowledge loss and improve reliability for the remainder of our work. Want me to consolidate?"

This is NOT a suggestion to stop working. It's a suggestion to consolidate mid-session (like a power nap) so the remaining work benefits from clearer context.

After consolidation, pressure resets to 0.

---

## When to run

- User invokes `/distill`
- Memory pressure reaches 7+ (recommend to user)
- End of a long session with multiple iterations
- After repeated friction with a workflow
- When the user says "let's save this", "what did we learn?", or "any takeaways?"
