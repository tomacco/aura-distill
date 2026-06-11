#!/bin/bash
# aura-distill installer
# https://github.com/tomacco/aura-distill

set -e




VERSION="1.1.4"

BUILD="20260518-01"
REPO="https://raw.githubusercontent.com/tomacco/aura-distill/main"
# Profile paths are set dynamically after profile detection (see below)
PROFILE_DIR=""
DISTILL_LINE='# Distill — knowledge system (github.com/tomacco/aura-distill)

GATE: If ~/.claude/distill/.needs-migration exists, tell the user: "Run /distill to migrate existing memories." Do NOT proceed until addressed or declined.'

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

# ═══ HEADER ANIMATION ═══

show_header() {
  clear
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

# Parse --profile argument
PROFILE_NAME=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --profile) PROFILE_NAME="$2"; shift 2 ;;
        --profile=*) PROFILE_NAME="${1#*=}"; shift ;;
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
DISTILL_DIR="$PROFILE_DIR/distill"
RULES_DIR="$PROFILE_DIR/rules"
CLAUDE_MD="$PROFILE_DIR/CLAUDE.md"

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
mkdir -p "$DISTILL_DIR"/{craft,ops,profile,projects,feedback,archive}

# Download core files and resolve {DISTILL_DIR} to actual path

curl -sL "$REPO/distill.md" | sed "s|{DISTILL_DIR}|$DISTILL_DIR|g" > "$CMD_DIR/distill.md"
done_msg "distill.md ${DIM}(command)${RESET}"


curl -sL "$REPO/distill-process.md" | sed "s|{DISTILL_DIR}|$DISTILL_DIR|g" > "$DISTILL_DIR/distill-process.md"
done_msg "distill-process.md ${DIM}(process engine)${RESET}"


curl -sL "$REPO/distill-monitor.md" | sed "s|{DISTILL_DIR}|$DISTILL_DIR|g" > "$DISTILL_DIR/distill-monitor.md"
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
curl -sL "$REPO/rules/distill.md" | sed "s|{DISTILL_DIR}|$DISTILL_DIR|g" > "$RULES_DIR/distill.md"
done_msg "rules/distill.md ${DIM}(auto-loads every session)${RESET}"

# ═══ CLAUDE.md INTEGRATION ═══

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

if [ -f "$CLAUDE_MD" ]; then
    if grep -q "aura-distill" "$CLAUDE_MD" 2>/dev/null; then
        done_msg "CLAUDE.md ${DIM}(already configured)${RESET}"
    elif grep -q "distill" "$CLAUDE_MD" 2>/dev/null; then
        # Older version reference — replace it
        sed -i.bak '/distill/d' "$CLAUDE_MD"
        rm -f "$CLAUDE_MD.bak"
        echo "" >> "$CLAUDE_MD"
        echo "$DISTILL_LINE" >> "$CLAUDE_MD"
        done_msg "CLAUDE.md ${DIM}(upgraded)${RESET}"
    else
        echo "" >> "$CLAUDE_MD"
        echo "$DISTILL_LINE" >> "$CLAUDE_MD"
        done_msg "CLAUDE.md configured"
    fi
else
    echo "$DISTILL_LINE" > "$CLAUDE_MD"
    done_msg "Created CLAUDE.md"
fi

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
printf "  ${DIM}Knowledge:${RESET} ~/.claude/distill/\n"
echo ""
if [ -n "$EXISTING_VERSION" ]; then
    printf "  ${CYAN}Upgraded${RESET} v${EXISTING_VERSION} → v${VERSION}\n"
    echo ""
fi
printf "  ${DIM}Uninstall (keeps your learnings):${RESET}\n"
printf "    ${DIM}rm -rf ~/.claude/distill ~/.claude/commands/distill.md ~/.claude/rules/distill.md${RESET}\n"
echo ""
printf "  ${PURPLE}say what matters. it's listening.${RESET}\n"
echo ""
printf "  ${DIM}Research:${RESET} https://tomacco.github.io/aura-distill/research/\n"
printf "  ${DIM}@tomacco is super happy to share this research with you.${RESET}\n"
printf "  ${DIM}Every finding is reproducible. Raw outputs published.${RESET}\n"
echo ""
