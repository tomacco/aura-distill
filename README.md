<p align="center">
  <img src="docs/header.svg?v=1.1.12" alt="aura-distill" width="800"/>
</p>

<p align="center">
  <strong>Not what it remembers — how it learns.</strong><br>
  <em>First-principles memory for Claude Code and Codex. A/B tested.</em>
</p>

<p align="center">
  <a href="https://tomacco.github.io/aura-distill/"><strong>Live Demo</strong></a> ·
  <a href="https://tomacco.github.io/aura-distill/research/"><strong>Research</strong></a> ·
  <a href="#installation">Install</a> ·
  <a href="#results">Results</a>
</p>

---

## The problem

Claude Code has memory. But it remembers *facts*, not *principles*.

It saves "user prefers dark mode" — but not "when I retry a permanent failure, I'm wasting resources." It dumps observations into a flat file with no hierarchy, no consolidation, no retrieval strategy.

**Distill fixes how Claude learns** — not what it remembers, but *how* it structures, retrieves, and applies knowledge.

---

## Results

We A/B tested the same prompts with and without distill knowledge. Same model, same session.

| Scenario | Without distill | With distill |
|----------|----------------|--------------|
| User asks to retry 404 errors | Complies silently | **Refuses**: "404 is permanent. Won't retry." Offers correct alternative. |
| User follows outdated deploy procedure | Drafts announcement for wrong process | **Catches it**: "Procedure changed after May 8 incident." |
| User queries another service's DB | Writes the SQL + soft footnote | **Refuses**: "Violates one-service-one-DB." Cites past mistake. |

**Average improvement: +6.0 on a 12-point scale.** [Full methodology and raw outputs →](docs/research.md)

---

## Installation

**macOS** (Homebrew):
```bash
brew install tomacco/aura-distill/aura-distill
aura-distill install
```

**macOS / Linux / WSL** (bash):
```bash
curl -sL https://raw.githubusercontent.com/tomacco/aura-distill/main/install.sh | bash
```

**Windows** (PowerShell):
```powershell
irm https://raw.githubusercontent.com/tomacco/aura-distill/main/install.ps1 | iex
```

<sub>No sudo. Knowledge lives in `~/.aura-distill/`; small adapters are added to Claude and Codex configuration. [Read install.sh](install.sh) / [install.ps1](install.ps1) first if you're the responsible kind.</sub>

This installs:

| File | Location | Purpose |
|------|----------|---------|
| `distill.md` | `~/.claude/commands/` | The `/distill` slash command |
| `distill.md` | `~/.claude/rules/` | Knowledge retrieval (18 lines, auto-loads every session) |
| `distill-process.md` | `~/.aura-distill/` | Full process (read by sub-agent) |
| `SPINE.md` | `~/.aura-distill/` | Shared Claude/Codex knowledge index |
| managed pointer | `~/.claude/CLAUDE.md` | Makes Claude load the shared SPINE |
| managed pointer | `~/.codex/AGENTS.md` | Makes Codex load the shared SPINE |

Zero dependencies. No Node.js. No MCP server. No database. Just files.

---

## How it works

```
you type /distill
    → harvests signals from the conversation (corrections, preferences, surprises)
    → spawns an isolated sub-agent (your context stays clean)
    → sub-agent traces each signal to a first principle
    → encodes in ~/.aura-distill/ with markers: [UPDATED], [CONTEXT], [NON-NEGOTIABLE]
    → every future session retrieves relevant knowledge before responding
```

### What makes it different from memory.md

| memory.md | distill |
|-----------|---------|
| Saves "user said don't modify shared factory" | Encodes "blast radius awareness: never modify shared infra for one consumer" |
| Flat file, linear reading | Tiered: SPINE index → domain files → archive |
| No staleness detection | `[UPDATED]` tags + `staleness_threshold` metadata |
| Grows until it hits 200-line cap | Compacts: archive old knowledge, never drops it |
| Same response regardless of context | Retrieves by relevance (SPINE hooks match current task) |

### Knowledge markers

```markdown
- [CONTEXT] "Always interfaces" = new services. "Concrete" = prototypes.
- [UPDATED 2026-05-13] Deploy now requires canary first. Old way removed.
- [NON-NEGOTIABLE] One service, one database. No shared DBs.
- [PROVISIONAL] Using WebSockets — may switch to SSE after LB testing.
- [IMPORTANT] Under pressure, user fixates on first hypothesis. Widen the search.
```

---

## Architecture

```
~/
├── .claude/CLAUDE.md               ← managed pointer for Claude
├── .codex/AGENTS.md                ← managed pointer for Codex
└── .aura-distill/                  ← shared, client-neutral knowledge
    ├── SPINE.md                     ← tier 1: index (max 80 lines)
    ├── distill-process.md           ← the distillation process
    ├── craft/                       ← tier 2: discipline knowledge
    ├── ops/                         ← tier 2: operational knowledge
    ├── profile/                     ← tier 2: user model
    ├── projects/                    ← tier 2: project context
    ├── feedback/                    ← tier 2: preferences
    └── archive/                     ← tier 3: compressed history
```

**Three tiers** — inspired by biological memory:
- **Tier 1 (Spine):** Always loaded. Max 80 lines. Pointers with relevance hooks.
- **Tier 2 (Active):** Read on demand when task matches. Max 60 lines per file.
- **Tier 3 (Archive):** Compressed history. Promoted back when recalled. Never deleted.

---

## Anti-sycophancy

Five integrity principles are non-negotiable:

1. Never encode comfort as truth
2. Never flatten standards to reduce friction
3. Never confuse preference with principle
4. Frustration is diagnostic, not directive
5. The user's growth is the goal

Claude with distill **pushes back** when you're about to make a mistake it already learned about. That's the point.

---

## Uninstall

If installed via Homebrew:
```bash
aura-distill uninstall
brew uninstall aura-distill
```

**macOS / Linux / WSL:**
```bash
rm -f ~/.claude/commands/distill.md ~/.claude/rules/distill.md
# Remove the managed aura-distill blocks from ~/.claude/CLAUDE.md and ~/.codex/AGENTS.md.
# Keep ~/.aura-distill/ unless you intentionally want to delete your knowledge.
```

**Windows** (PowerShell):
```powershell
Remove-Item -Force $HOME\.claude\commands\distill.md, $HOME\.claude\rules\distill.md
# Remove the managed aura-distill blocks from CLAUDE.md and AGENTS.md.
# Keep $HOME\.aura-distill unless you intentionally want to delete your knowledge.
```

Your knowledge files in `~/.aura-distill/` are preserved. They're yours.

---

<p align="center">
  <sub>v1.1.12 · MIT · Built for Claude Code and Codex</sub>
</p>
