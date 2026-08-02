# Mechanisms Tracker

Living document of the mechanisms in aura-distill, their current state, and improvement ideas.

## Coverage & Automation

| Mechanism | Status | How it works | Known gaps |
|-----------|--------|--------------|------------|
| Distillation ledger | next release | Beacon nonce written into the live transcript (Step 1F) + one JSONL line appended to `data/distill-ledger.jsonl` after each run (session id, transcript path, line count, signals) | Identity `unresolved` when the client's transcript root is unknown; dedupe is recorded here but only ENFORCED by the auto-distiller (#51); Codex transcript layout assumed, not yet live-verified |

### Future improvements
- [ ] Auto-distiller discovery: diff transcript roots against the ledger (#51)
- [ ] `marks` mode entries once pre-distill marks ship (#48, gated on #49)
- [ ] Hook-based session identity fast-path (SessionStart hook writes id/path directly; needs a safe settings.json JSON-merge design)

## Concurrency & Reliability

| Mechanism | Status | How it works | Known gaps |
|-----------|--------|--------------|------------|
| Lock file | v0.3.2 | `.lock` with timestamp, 5-min staleness | No queuing — if locked, user chooses wait or cancel |
| Checkpoint | v0.3.3 | `.checkpoint` with step/signals/date | Resume only replays from last checkpoint, not partial step |
| Lock refresh | v0.3.3 | Long-running sub-agents refresh timestamp | No heartbeat mechanism — relies on sub-agent remembering |
| Queue/wait | v0.3.3 | Dispatcher polls lock every 30s if user says "wait" | Polling in main context — costs some attention |

### Future improvements
- [ ] True file-based queue (numbered lock files for ordering)
- [ ] Heartbeat mechanism (sub-agent writes every 60s, stale = 2 missed heartbeats)
- [ ] Partial resume within a step (e.g., "3 of 8 signals were encoded before crash")

## Knowledge Delivery

| Mechanism | Status | How it works | Known gaps |
|-----------|--------|--------------|------------|
| Spine auto-load | next release | Managed blocks in Claude `CLAUDE.md` and Codex `AGENTS.md` point to the shared SPINE | Depends on clients loading their global instruction files |
| Post-distill spine read | v0.2.0 | Dispatcher reads SPINE after sub-agent returns | Only for current session |
| Bridge detection | v0.3.2 | Step 3b identifies unreachable knowledge | Only suggests — user must act |
| Bridge escalation | v0.3.2 | Repeated suggestion + frustration → louder prompt | No tracking of "how many times suggested" yet |

### Future improvements
- [ ] Track bridge suggestion history (file: `.bridge-log`)
- [ ] Auto-detect which contexts sub-agents are spawned into
- [ ] Offer to auto-inject bridges if user has approved pattern before
- [ ] Project-level CLAUDE.md detection (suggest bridges there, not just global)

## User Model & Adaptation

| Mechanism | Status | How it works | Known gaps |
|-----------|--------|--------------|------------|
| User profile | v0.1.0 | Expertise/communication/thinking in profile/ | Only updated during distill, not real-time |
| Trust topology | v0.3.4 | Maps what user delegates/retains/verifies and WHY | Requires multiple sessions to build accurate picture |
| Dissonance detection | v0.3.4 | Compares delegation behavior to stated principles | Only flags — never assumes wrong, asks for clarification |
| Frustration escalation | v0.3.0 | Repeated frustration → elevate + strengthen + cross-ref | No quantitative tracking of "times frustrated about X" |
| Reassurance output | v0.3.0 | "I heard you on:" section in report | Only in report — no in-session reassurance |
| Pressure monitoring | v0.2.0 | Monitor tracks score, suggests at 7+ | Heuristic, not measured — no persistence between sessions |

### Future improvements
- [ ] Persistent pressure counter (carry over between sessions if not distilled)
- [ ] Frustration frequency tracking (count per topic, not just boolean)
- [ ] In-session micro-reassurance ("noted, I'll remember this")
- [ ] User model versioning (track how understanding evolves over time)
- [ ] Trust topology trend tracking (how delegation boundaries shift over time)
- [ ] Proactive trust calibration ("you've been delegating X more — should I treat it as trusted territory now?")
- [ ] Dissonance resolution history (track what was flagged, what user said, how it resolved)
- [ ] **Distill rhythm learning:** Track when users actually distill (time into session, pressure level, trigger type: manual vs suggestion). After N sessions, detect their natural pattern and offer to auto-distill at that rhythm. "You usually distill after ~45min of dense work. Want me to just do it automatically at that point?" User opts in → fully automated consolidation at their natural cadence.

## Version & Distribution

| Mechanism | Status | How it works | Known gaps |
|-----------|--------|--------------|------------|
| VERSION file | v0.2.0 | Repo source of truth | — |
| .version local | v0.2.0 | Installed version for comparison | Can drift if user manually edits |
| Auto-bump GH Action | v0.3.0 | Patch++ on every content push to main | Bumps even for docs-only changes |
| In-session update | v0.3.2 | /distill checks version, user accepts | No changelog shown — user doesn't know what changed |
| Auto-update preference | v0.3.2 | feedback/preferences.md stores opt-in | Not tested with real users yet |

### Future improvements
- [ ] CHANGELOG.md auto-generated from commits
- [ ] Show what changed when prompting for update
- [ ] Major version updates require explicit confirmation (breaking changes)
- [ ] Rollback mechanism ("this update broke something, revert")

## Retrieval & Delivery

The current system uses SPINE-based file retrieval (read the index → read relevant files on demand). Previous explorations of an MCP server approach (v0.5.0) were abandoned in v0.6.0 — the file-based system proved simpler and sufficient. See `ARCHITECTURE-V2.md` for the abandoned spec if revisiting.

| Mechanism | Status | How it works | Known gaps |
|-----------|--------|--------------|------------|
| SPINE index | v0.1.0 | Always-loaded knowledge map, pointers to files | 80-line limit; relevance hooks must be precise |
| On-demand file read | v0.1.0 | LLM reads Tier 2 files when SPINE matches domain | Relies on LLM discipline — sometimes skips |
| Trigger on actions | v0.7.5 | "Deploying X" triggers retrieval, not just questions | Fixed after memory-rot research |
| Origin tracking | v0.8.0 | `origin: directive\|evidence\|convention\|constraint` | New — not yet validated at scale |

### Future improvements
- [ ] Proactive recall ("I notice you're about to write code — here's what I know")
- [ ] Confidence scoring on recalled knowledge ("this file was useful 95% of the time")
- [ ] Decay scoring ("this file hasn't been useful in 30 days — still relevant?")

## Anti-sycophancy & Integrity

| Mechanism | Status | How it works | Known gaps |
|-----------|--------|--------------|------------|
| 5 integrity principles | v0.1.0 | Non-negotiable rules in distill-process.md | Relies on LLM compliance — no enforcement |
| Anti-sycophancy check | v0.1.0 | 4-question checklist before finalizing | Manual check, no automated validation |
| Flagged tensions | v0.1.0 | Report section for honesty-vs-comfort conflicts | Rare in practice — LLMs tend to avoid flagging |

### Future improvements
- [ ] Adversarial self-check: "If I removed this learning, would the user be worse off?"
- [ ] Cross-session consistency check: "Does this contradict what I said last time?"
- [ ] User can challenge encoded learnings ("I disagree with this — re-evaluate")
