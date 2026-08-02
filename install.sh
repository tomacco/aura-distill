#!/bin/bash
# aura-distill installer
# https://github.com/tomacco/aura-distill

set -e




VERSION="1.1.14"

BUILD="20260518-01"
REPO="${AURA_DISTILL_REPO:-https://raw.githubusercontent.com/tomacco/aura-distill/main}"
# Profile paths are set dynamically after profile detection (see below)
PROFILE_DIR=""
AURA_DIR="${AURA_DISTILL_HOME:-$HOME/.aura-distill}"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
MANAGED_START='<!-- aura-distill:start -->'
MANAGED_END='<!-- aura-distill:end -->'

# ═══ COLORS & FORMATTING ═══
CYAN=$(printf '\033[0;36m')
PURPLE=$(printf '\033[0;35m')
GREEN=$(printf '\033[0;32m')
DIM=$(printf '\033[2m')
BOLD=$(printf '\033[1m')
RESET=$(printf '\033[0m')
RED=$(printf '\033[0;31m')
YELLOW=$(printf '\033[0;33m')

# ═══ ANIMATION HELPERS ═══

spinner() {
  local pid=$1
  local msg=$2
  local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
  local i=0
  tput civis 2>/dev/null  # hide cursor
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r  %s %s   " "${frames[$i]}" "$msg"
    i=$(( (i + 1) % ${#frames[@]} ))
    sleep 0.1
  done
  wait "$pid"
  local exit_code=$?
  printf "\r                                                              \r"
  tput cnorm 2>/dev/null  # show cursor
  return $exit_code
}

done_msg() {
  echo "  ${GREEN}✓${RESET} $1"
}

skip_msg() {
  echo "  ${DIM}·${RESET} $1"
}

warn_msg() {
  echo "  ${YELLOW}⚠${RESET} $1"
}

fail_msg() {
  echo "  ${RED}✗${RESET} $1"
}

info_msg() {
  echo "  ${CYAN}ℹ${RESET} $1"
}

fetch_file() {
  local source="$1"
  if [ -f "$source" ]; then cat "$source"; else curl -fsL "$source"; fi
}

# ═══ HEADER ANIMATION ═══

show_header() {
  clear 2>/dev/null || true
  echo ""
  printf "${PURPLE}"
  echo "        ╭──────────────────────────────────────╮"
  echo "        │                                      │"
  echo "        │        ░█▀█░█░█░█▀▄░█▀█              │"
  echo "        │        ░█▀█░█░█░█▀▄░█▀█              │"
  echo "        │        ░▀░▀░▀▀▀░▀░▀░▀░▀              │"
  echo "        │                                      │"
  echo "        │      ░█▀▄░▀█▀░█▀▀░▀█▀░▀█▀░█░░░█░░    │"
  echo "        │      ░█░█░░█░░▀▀█░░█░░░█░░█░░░█░░    │"
  echo "        │      ░▀▀░░▀▀▀░▀▀▀░░▀░░▀▀▀░▀▀▀░▀▀▀    │"
  echo "        │                                      │"
  echo "        ╰──────────────────────────────────────╯"
  printf "${RESET}"
  echo ""
  printf "  ${DIM}every session makes all sessions better${RESET}\n"
  printf "  ${DIM}say what matters. it's listening.${RESET}\n"
  echo ""
  printf "  ${DIM}v${VERSION} (build ${BUILD})${RESET}\n"
  echo ""
}

show_section() {
  echo ""
  printf "  ${PURPLE}━━${RESET} ${BOLD}%s${RESET}\n" "$1"
  echo ""
}


# ═══ PROFILE DETECTION ═══

# Parse arguments
PROFILE_NAME=""
TOKEN_SAVER="auto"   # auto = keep prior choice (default on for new installs); on/off/remove = explicit
while [[ $# -gt 0 ]]; do
    case $1 in
        --profile) PROFILE_NAME="$2"; shift 2 ;;
        --profile=*) PROFILE_NAME="${1#*=}"; shift ;;
        --token-saver) TOKEN_SAVER="on"; shift ;;
        --no-token-saver) TOKEN_SAVER="off"; shift ;;
        --remove-token-saver) TOKEN_SAVER="remove"; shift ;;
        *) shift ;;
    esac
done

# Detect available profiles
detect_profiles() {
    local profiles=()
    [ -d "$HOME/.claude" ] && profiles+=("default:$HOME/.claude")
    for dir in "$HOME"/.claude-*/; do
        [ -d "$dir" ] || continue
        local name=$(basename "$dir" | sed 's/^\.claude-//')
        # Skip test/internal profiles
        [[ "$name" == *"isolation"* || "$name" == *"hidden"* || "$name" == *"backup"* ]] && continue
        profiles+=("$name:$dir")
    done
    echo "${profiles[@]}"
}

resolve_profile() {
    local profiles=($(detect_profiles))
    local count=${#profiles[@]}

    # If --profile was passed, use it
    if [ -n "$PROFILE_NAME" ]; then
        if [ "$PROFILE_NAME" = "default" ]; then
            PROFILE_DIR="$HOME/.claude"
        else
            PROFILE_DIR="$HOME/.claude-${PROFILE_NAME}"
        fi
        if [ ! -d "$PROFILE_DIR" ]; then
            fail_msg "Profile '$PROFILE_NAME' not found at $PROFILE_DIR"
            exit 1
        fi
        return
    fi

    # Single profile (or only default) → use it silently
    if [ $count -le 1 ]; then
        PROFILE_DIR="$HOME/.claude"
        return
    fi

    # Multiple profiles → ask user
    echo ""
    printf "  ${BOLD}Multiple profiles detected:${RESET}\n"
    echo ""
    local i=1
    for entry in "${profiles[@]}"; do
        local name="${entry%%:*}"
        local path="${entry#*:}"
        local marker=""
        [ -f "${path}distill/.version" ] && marker=" ${DIM}(distill installed)${RESET}"
        printf "    ${CYAN}%d)${RESET} %s %s${marker}\n" "$i" "$name" "${DIM}($path)${RESET}"
        i=$((i + 1))
    done
    echo ""
    printf "  ${BOLD}Choose profile [1-%d]:${RESET} " "$count"
    read -r choice

    if [ -z "$choice" ] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$count" ] 2>/dev/null; then
        fail_msg "Invalid choice. Run with --profile <name> to skip this prompt."
        exit 1
    fi

    local selected="${profiles[$((choice-1))]}"
    PROFILE_DIR="${selected#*:}"
    # Remove trailing slash
    PROFILE_DIR="${PROFILE_DIR%/}"
}

# ═══ MAIN INSTALLATION ═══

show_header

# Resolve which profile to install to
resolve_profile

# Set paths based on resolved profile
CMD_DIR="$PROFILE_DIR/commands"
DISTILL_DIR="$AURA_DIR"
RULES_DIR="$PROFILE_DIR/rules"
CLAUDE_MD="$PROFILE_DIR/CLAUDE.md"
CODEX_AGENTS="$CODEX_DIR/AGENTS.md"
LEGACY_DISTILL_DIR="$PROFILE_DIR/distill"

info_msg "Installing to: ${PROFILE_DIR}"
echo ""

# Detect existing installation
EXISTING_VERSION=""
if [ -f "$DISTILL_DIR/.version" ]; then
    EXISTING_VERSION=$(cat "$DISTILL_DIR/.version")
    info_msg "Existing installation: v${EXISTING_VERSION} → v${VERSION}"
    echo ""
fi


show_section "Core files"

# Ensure directories exist
mkdir -p "$CMD_DIR"
mkdir -p "$DISTILL_DIR"/{craft,ops,profile,projects,feedback,archive,data,inbox}

# New installs use the client-neutral store. When an older Claude-only install
# exists, seed the shared store without moving or modifying the legacy copy.
if [ -d "$LEGACY_DISTILL_DIR" ] && [ "$LEGACY_DISTILL_DIR" != "$DISTILL_DIR" ] \
   && [ ! -f "$DISTILL_DIR/.legacy-imported" ]; then
    cp -R "$LEGACY_DISTILL_DIR"/. "$DISTILL_DIR"/ 2>/dev/null || true
    printf 'copied from %s on %s\n' "$LEGACY_DISTILL_DIR" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$DISTILL_DIR/.legacy-imported"
    info_msg "Existing Claude knowledge copied to shared store; legacy files preserved"
elif [ -d "$LEGACY_DISTILL_DIR" ] && [ -f "$DISTILL_DIR/.legacy-imported" ]; then
    info_msg "Shared store was already seeded; $LEGACY_DISTILL_DIR left untouched (use AURA_DISTILL_HOME for an isolated profile)"
fi

# Download core files and resolve {DISTILL_DIR} to actual path

fetch_file "$REPO/distill.md" | sed "s|{DISTILL_DIR}|$DISTILL_DIR|g" > "$CMD_DIR/distill.md"
done_msg "distill.md ${DIM}(command)${RESET}"


fetch_file "$REPO/distill-process.md" | sed "s|{DISTILL_DIR}|$DISTILL_DIR|g" > "$DISTILL_DIR/distill-process.md"
done_msg "distill-process.md ${DIM}(process engine)${RESET}"


fetch_file "$REPO/distill-monitor.md" | sed "s|{DISTILL_DIR}|$DISTILL_DIR|g" > "$DISTILL_DIR/distill-monitor.md"
done_msg "distill-monitor.md ${DIM}(session monitor)${RESET}"

# Version
echo "$VERSION" > "$DISTILL_DIR/.version"

# Spine
if [ ! -f "$DISTILL_DIR/SPINE.md" ]; then
    echo "# Distill Knowledge Index" > "$DISTILL_DIR/SPINE.md"
    echo "" >> "$DISTILL_DIR/SPINE.md"
    echo "<!-- This file is managed by aura-distill. Max 80 lines. -->" >> "$DISTILL_DIR/SPINE.md"
    echo "<!-- Each entry: - [Title](path.md) — when to read this -->" >> "$DISTILL_DIR/SPINE.md"
    done_msg "SPINE.md ${DIM}(knowledge index)${RESET}"
else
    skip_msg "SPINE.md ${DIM}(preserved)${RESET}"
fi

# ═══ KNOWLEDGE RETRIEVAL (rules file) ═══

show_section "Knowledge retrieval"

mkdir -p "$RULES_DIR"

# Preserve the user's synced Always-On preferences across updates (like SPINE).
# /distill writes real content into this section; overwriting it is data loss.
PREFS_MARK="## Always-On User Preferences"
PREFS_TMP=""
if [ -f "$RULES_DIR/distill.md" ] && grep -q "^$PREFS_MARK" "$RULES_DIR/distill.md" \
   && grep -A 30 "^$PREFS_MARK" "$RULES_DIR/distill.md" | grep -q "^\*\*"; then
    PREFS_TMP=$(mktemp)
    sed -n "/^$PREFS_MARK/,\$p" "$RULES_DIR/distill.md" > "$PREFS_TMP"
fi

RULES_TMP=$(mktemp)
if fetch_file "$REPO/rules/distill.md" | sed "s|{DISTILL_DIR}|$DISTILL_DIR|g" > "$RULES_TMP" \
   && grep -q "Distill" "$RULES_TMP"; then
    if [ -n "$PREFS_TMP" ]; then
        # Build the merged file in a temp and move it into place atomically —
        # never truncate the live file before the merge is complete.
        MERGED_TMP=$(mktemp)
        sed "/^$PREFS_MARK/,\$d" "$RULES_TMP" > "$MERGED_TMP"
        cat "$PREFS_TMP" >> "$MERGED_TMP"
        mv "$MERGED_TMP" "$RULES_DIR/distill.md"
        rm -f "$PREFS_TMP"
        done_msg "rules/distill.md ${DIM}(auto-loads every session; your preferences preserved)${RESET}"
    else
        mv "$RULES_TMP" "$RULES_DIR/distill.md"
        done_msg "rules/distill.md ${DIM}(auto-loads every session)${RESET}"
    fi
    rm -f "$RULES_TMP"
else
    rm -f "$RULES_TMP" "$PREFS_TMP"
    warn_msg "rules/distill.md download failed — existing file left untouched"
fi

# ═══ TOKEN SAVER (agent presets) ═══
# User has full control: --token-saver / --no-token-saver / --remove-token-saver.
# The choice persists in $DISTILL_DIR/.token-saver across updates.
# What it is and why: https://tomacco.github.io/aura-distill/token-saving.html

show_section "Token Saver"

AGENTS_DIR="$PROFILE_DIR/agents"
TS_MARKER="$DISTILL_DIR/.token-saver"

# Resolve "auto": respect a previously persisted choice; default ON for fresh state
if [ "$TOKEN_SAVER" = "auto" ] && [ "$(cat "$TS_MARKER" 2>/dev/null)" = "disabled" ]; then
    TOKEN_SAVER="off"
fi

install_token_saver_agent() {
    local name=$1
    local target="$AGENTS_DIR/${name}.md"
    if [ -f "$target" ] && ! grep -q "aura-distill" "$target" 2>/dev/null; then
        warn_msg "agents/${name}.md exists and isn't ours — preserved untouched"
        return
    fi
    # Download to temp and validate before touching the target: a raw-GitHub 404
    # exits 0 with body "404: Not Found", and a poisoned file would then be
    # protected forever by the not-ours guard above.
    local tmp
    tmp=$(mktemp)
    if fetch_file "$REPO/agents/${name}.md" > "$tmp" 2>/dev/null \
       && grep -q "aura-distill" "$tmp" && grep -q "^name: ${name}" "$tmp"; then
        mv "$tmp" "$target"
        done_msg "agents/${name}.md ${DIM}(preset subagent)${RESET}"
    else
        rm -f "$tmp"
        warn_msg "agents/${name}.md download failed — skipped (re-run the installer to retry)"
    fi
}

case "$TOKEN_SAVER" in
    remove|off)
        for a in scribe scout; do
            if [ -f "$AGENTS_DIR/${a}.md" ] && grep -q "aura-distill" "$AGENTS_DIR/${a}.md" 2>/dev/null; then
                rm -f "$AGENTS_DIR/${a}.md"
                done_msg "Removed agents/${a}.md"
            fi
        done
        echo "disabled" > "$TS_MARKER"
        skip_msg "Token Saver ${DIM}(off — enable anytime: re-run with --token-saver)${RESET}"
        ;;
    *)
        mkdir -p "$AGENTS_DIR"
        install_token_saver_agent "scribe"
        install_token_saver_agent "scout"
        echo "enabled" > "$TS_MARKER"
        info_msg "Two lightweight subagent presets — local files only, nothing is collected or sent anywhere."
        info_msg "What they do & the research behind them: ${CYAN}https://tomacco.github.io/aura-distill/token-saving.html${RESET}"
        info_msg "Not for you? ${DIM}re-run with --remove-token-saver${RESET}"
        ;;
esac

# ═══ CLAUDE + CODEX INTEGRATION ═══

show_section "Session integration"

# Disable auto-memory (distill owns knowledge management)
SETTINGS_JSON="$PROFILE_DIR/settings.json"
if [ -f "$SETTINGS_JSON" ]; then
    if grep -q '"autoMemoryEnabled"' "$SETTINGS_JSON" 2>/dev/null; then
        skip_msg "Auto-memory already configured in settings.json"
    else
        # Add autoMemoryEnabled: false after the opening brace
        sed -i.bak 's/^{$/{\n  "autoMemoryEnabled": false,/' "$SETTINGS_JSON"
        rm -f "$SETTINGS_JSON.bak"
        done_msg "Disabled auto-memory ${DIM}(distill owns knowledge)${RESET}"
    fi
else
    echo '{ "autoMemoryEnabled": false }' > "$SETTINGS_JSON"
    done_msg "Created settings.json with auto-memory disabled"
fi

integration_block() {
local client="$1"
cat <<EOF
$MANAGED_START
# Aura Distill shared knowledge

Before doing any work, read $DISTILL_DIR/SPINE.md. When the request or an announced action matches a SPINE entry, read the linked file before responding and apply it.
EOF
if [ "$client" = "codex" ]; then
cat <<EOF
Read $DISTILL_DIR/distill-monitor.md for the full retrieval and memory-pressure behavior. When the user asks to distill, read $DISTILL_DIR/distill-process.md and run that process in an isolated sub-agent when supported.
EOF
fi
cat <<EOF
If $DISTILL_DIR/.needs-migration exists and does not start with "migrated", tell the user to ask you to distill/migrate existing memories before proceeding.
$MANAGED_END
EOF
}

upsert_managed_block() {
    local target="$1" label="$2" tmp
    mkdir -p "$(dirname "$target")"
    tmp=$(mktemp)
    if [ -f "$target" ]; then
        awk -v start="$MANAGED_START" -v end="$MANAGED_END" '
          function emit(line) {
            if (line == "") { blanks++; return }
            while (blanks > 0) { print ""; blanks-- }
            print line
          }
          function flush_legacy( i) {
            for (i=1; i<=legacy_n; i++) emit(legacy_lines[i])
            delete legacy_lines; legacy_n=0; legacy=0
          }
          $0 == start { skip=1; next }
          $0 == end { skip=0; next }
          skip { next }
          /^# Distill .*knowledge system \(github.com\/tomacco\/aura-distill\)$/ {
            legacy=1; legacy_lines[++legacy_n]=$0; next
          }
          legacy {
            legacy_lines[++legacy_n]=$0
            if (/^GATE:/) { delete legacy_lines; legacy_n=0; legacy=0; next }
            if (/^#/ && legacy_n > 1) flush_legacy()
            next
          }
          { emit($0) }
          END { if (legacy) flush_legacy() }
        ' "$target" > "$tmp"
    fi
    [ ! -s "$tmp" ] || printf '\n' >> "$tmp"
    integration_block "$label" >> "$tmp"
    mv "$tmp" "$target"
    done_msg "$label configured"
}

upsert_managed_block "$CLAUDE_MD" "claude"
upsert_managed_block "$CODEX_AGENTS" "codex"

# ═══ MEMORY MIGRATION CHECK ═══

# Detect existing memory files that should be ingested
MEMORY_FILES=$(find "$HOME/.claude" -path "*/memory/*.md" -not -path "*/distill/*" 2>/dev/null | wc -l | tr -d ' ')
if [ "$MEMORY_FILES" -gt 0 ] && [ ! -f "$DISTILL_DIR/.migrated" ]; then
    echo ""
    printf "  ${CYAN}━━${RESET} ${BOLD}Existing memories detected${RESET}\n"
    echo ""
    printf "  Found ${BOLD}${MEMORY_FILES}${RESET} memory files from Claude's built-in system.\n"
    printf "  Since distill now owns knowledge management, these won't be\n"
    printf "  read by the auto-memory system anymore.\n"
    echo ""
    printf "  ${BOLD}On your next session, run ${CYAN}/distill${RESET}${BOLD} — it will:${RESET}\n"
    printf "    • Read your existing memories\n"
    printf "    • Ingest them into distill's tiered system\n"
    printf "    • Apply quality checks and proper categorization\n"
    printf "    • Your old files stay untouched (as backup)\n"
    echo ""
    # Flag so we only show this once
    echo "pending $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$DISTILL_DIR/.needs-migration"
fi

# ═══ COMPLETE ═══

echo ""
echo ""
printf "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
echo ""
printf "  ${GREEN}${BOLD}Installed${RESET}\n"
printf "  ${DIM}Zero dependencies. Just files.${RESET}\n"
echo ""
printf "  ${DIM}Version:  ${RESET}v${VERSION}\n"
printf "  ${DIM}Command:  ${RESET}/distill\n"
printf "  ${DIM}Knowledge:${RESET} ~/.aura-distill/\n"
echo ""
if [ -n "$EXISTING_VERSION" ]; then
    printf "  ${CYAN}Upgraded${RESET} v${EXISTING_VERSION} → v${VERSION}\n"
    echo ""
    if [ "$(cat "$TS_MARKER" 2>/dev/null)" = "enabled" ] && [ ! -f "$DISTILL_DIR/.token-saver-announced" ]; then
        printf "  ${BOLD}${PURPLE}NEW — Token Saver${RESET}\n"
        printf "  Two preset subagents (${BOLD}scribe${RESET}, ${BOLD}scout${RESET}) that skip the tool-schema tax:\n"
        printf "  a text-only job now boots at ~2k tokens instead of ~19-27k. Local files only,\n"
        printf "  fully yours, nothing collected. The 5-minute read on what changed and the\n"
        printf "  research behind it: ${CYAN}https://tomacco.github.io/aura-distill/token-saving.html${RESET}\n"
        printf "  ${DIM}Opt out anytime: re-run the installer with --remove-token-saver${RESET}\n"
        echo ""
        touch "$DISTILL_DIR/.token-saver-announced"
    fi
fi
printf "  ${DIM}Uninstall (keeps your learnings):${RESET}\n"
printf "    ${DIM}rm -f ~/.claude/commands/distill.md ~/.claude/rules/distill.md; remove aura-distill managed blocks from CLAUDE.md and ~/.codex/AGENTS.md${RESET}\n"
echo ""
printf "  ${PURPLE}say what matters. it's listening.${RESET}\n"
echo ""
printf "  ${DIM}Research:${RESET} https://tomacco.github.io/aura-distill/research/\n"
printf "  ${DIM}@tomacco is super happy to share this research with you.${RESET}\n"
printf "  ${DIM}Every finding is reproducible. Raw outputs published.${RESET}\n"
echo ""
