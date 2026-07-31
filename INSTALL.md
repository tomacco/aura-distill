# Installing aura-distill

Three installation methods, from automated to fully manual.

## Shared Claude + Codex layout

New installations keep the knowledge base in `~/.aura-distill/`. Claude's
`CLAUDE.md` and Codex's global `~/.codex/AGENTS.md` receive small managed
pointers to the same `SPINE.md`, so both clients recall and update one source
of truth.

When the installer finds an older Claude-only knowledge base at
`~/.claude/distill/`, it copies that knowledge into the shared directory and
leaves the legacy directory untouched. Re-running the installer is idempotent:
managed instruction blocks are replaced in place and unrelated user guidance
is preserved.

---

## Method 1: Script (one command)

```bash
curl -sL https://raw.githubusercontent.com/tomacco/aura-distill/main/install.sh | bash
```

**With a specific profile:**
```bash
curl -sL https://raw.githubusercontent.com/tomacco/aura-distill/main/install.sh | bash -s -- --profile personal
# Installs to ~/.claude-personal/ instead of ~/.claude/
```

If you have multiple profiles, the script will list them and ask you to choose (or pass `--profile`).

---

## Method 2: Agent-assisted (paste to Claude)

Tell Claude Code:

```
Install aura-distill from github.com/tomacco/aura-distill using the manual steps in INSTALL.md. My Claude config is at ~/.claude/ (or specify your profile path).
```

Or more explicitly — paste this to any Claude Code session:

```
Read https://raw.githubusercontent.com/tomacco/aura-distill/main/INSTALL.md and follow the "Manual installation" steps. Install to my active Claude profile.
```

---

## Method 3: Manual (no scripts, full control)

For security-conscious users who don't pipe curl to bash.

### Step 1: Download the files

```bash
# Shared knowledge directory (default for every client)
DISTILL_DIR="$HOME/.aura-distill"
# Claude adapter directory
PROFILE="$HOME/.claude"

# Core command (the /distill slash command)
curl -sL https://raw.githubusercontent.com/tomacco/aura-distill/main/distill.md \
  -o "$PROFILE/commands/distill.md"

# Process engine (how /distill works internally)
curl -sL https://raw.githubusercontent.com/tomacco/aura-distill/main/distill-process.md \
  -o "$DISTILL_DIR/distill-process.md"

# Session monitor (loaded every session, tiny)
curl -sL https://raw.githubusercontent.com/tomacco/aura-distill/main/distill-monitor.md \
  -o "$DISTILL_DIR/distill-monitor.md"

# Retrieval rules (auto-loads, tells Claude how to use knowledge)
curl -sL https://raw.githubusercontent.com/tomacco/aura-distill/main/rules/distill.md \
  -o "$PROFILE/rules/distill.md"
```

### Step 2: Create the directory structure

```bash
mkdir -p "$DISTILL_DIR"/{craft,ops,profile,projects,feedback,archive}
mkdir -p "$PROFILE/commands"
mkdir -p "$PROFILE/rules"
mkdir -p "$HOME/.codex"
```

### Step 3: Initialize the SPINE

```bash
cat > "$DISTILL_DIR/SPINE.md" << 'EOF'
# Distill Knowledge Index

<!-- This file is managed by aura-distill. Max 80 lines. -->
<!-- Each entry: - [Title](path.md) — when to read this -->
EOF
```

### Step 4: Set the version

```bash
curl -sL https://raw.githubusercontent.com/tomacco/aura-distill/main/VERSION \
  -o "$DISTILL_DIR/.version"
```

### Step 5: (Optional) Disable built-in auto-memory

Distill owns knowledge management. To prevent Claude's built-in memory from conflicting:

```bash
# If settings.json exists, add autoMemoryEnabled: false
# Or create it:
echo '{ "autoMemoryEnabled": false }' > "$PROFILE/settings.json"
```

### Step 6: Add Claude and Codex integration pointers

Add this managed guidance to both `$PROFILE/CLAUDE.md` and `$HOME/.codex/AGENTS.md`:

```markdown
<!-- aura-distill:start -->
# Aura Distill shared knowledge
Before doing any work, read ~/.aura-distill/distill-monitor.md and ~/.aura-distill/SPINE.md. If the task matches a SPINE entry, read the linked file before responding and apply it.
<!-- aura-distill:end -->
```

---

## Multi-profile support

Claude Code supports multiple config profiles at `~/.claude-<name>/`. Each profile is independent — its own rules, commands, knowledge, and settings.

**Detecting profiles:**
```bash
ls -d ~/.claude-*/ 2>/dev/null
```

**Installing to a specific profile:**
```bash
# Via script
./install.sh --profile personal    # → ~/.claude-personal/
./install.sh --profile work        # → ~/.claude-work/

# Via manual
PROFILE="$HOME/.claude-personal" # then follow steps above
```

**Single profile (default):**
If only `~/.claude/` exists, the installer uses it automatically. No `--profile` needed.

---

## What gets installed (file inventory)

| File | Location | Purpose |
|------|----------|---------|
| `distill.md` | `$PROFILE/commands/` | The `/distill` slash command |
| `distill-process.md` | `~/.aura-distill/` | How distillation works (sub-agent reads this) |
| `distill-monitor.md` | `~/.aura-distill/` | Session monitor (pressure tracking) |
| `distill.md` (rules) | `$PROFILE/rules/` | Retrieval rules (auto-loaded every session) |
| `SPINE.md` | `~/.aura-distill/` | Shared knowledge index |
| `.version` | `~/.aura-distill/` | Installed version (for update checks) |
| managed pointer | `~/.claude/CLAUDE.md` | Claude integration |
| managed pointer | `~/.codex/AGENTS.md` | Codex integration |

**Total: 5 files + 1 index. No dependencies. No Node.js. No database.**

---

## Verifying installation

After installing, start a new Claude Code or Codex session and say:

```
Read ~/.aura-distill/SPINE.md
```

If Claude reads it without error, the installation is working. The rules file will make Claude read the SPINE automatically at session start.

---

## Uninstalling (keeps your knowledge)

```bash
rm -f "$PROFILE/commands/distill.md"
rm -f "$PROFILE/rules/distill.md"
# Remove the managed aura-distill blocks from CLAUDE.md and ~/.codex/AGENTS.md.
# Keep ~/.aura-distill/ unless you intentionally want to delete your knowledge.
```

---

## Research & methodology

All findings are empirical and reproducible:
https://tomacco.github.io/aura-distill/research/

@tomacco is super happy to share this research with you.
Every finding has raw outputs published alongside analysis.
