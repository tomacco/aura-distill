#!/bin/bash
# Memory Rot Research — tests same prompt across memory.md stages vs distill
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../lib/real-profile-guard.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results/$(date +%Y%m%d-%H%M%S)"
REAL_CONFIG="${DISTILL_TEST_CONFIG:-$HOME/.claude}"
CLAUDE_BIN="node /opt/homebrew/opt/claude-code-npm/libexec/lib/node_modules/@anthropic-ai/claude-code/cli.js"
SANDBOX_PROFILE='(version 1)(allow default)(deny file-read* (literal "/Library/Application Support/ClaudeCode/managed-settings.json"))'

GREEN=$(printf '\033[0;32m')
CYAN=$(printf '\033[0;36m')
DIM=$(printf '\033[2m')
BOLD=$(printf '\033[1m')
RESET=$(printf '\033[0m')

mkdir -p "$RESULTS_DIR"

run_sandbox() {
    local prompt="$1"
    local config_dir="$2"
    local output_file=$(mktemp)
    (
        CLAUDE_CONFIG_DIR="$config_dir" \
        CLAUDE_CODE_USE_BEDROCK=0 \
        ANTHROPIC_DEFAULT_OPUS_MODEL= \
        ANTHROPIC_DEFAULT_SONNET_MODEL= \
        ANTHROPIC_DEFAULT_HAIKU_MODEL= \
        ANTHROPIC_MODEL= \
        AWS_PROFILE= AWS_ACCESS_KEY_ID= AWS_SECRET_ACCESS_KEY= \
        AWS_SESSION_TOKEN= AWS_DEFAULT_REGION= \
        AWS_SHARED_CREDENTIALS_FILE=/dev/null AWS_CONFIG_FILE=/dev/null \
        sandbox-exec -p "$SANDBOX_PROFILE" \
        $CLAUDE_BIN --dangerously-skip-permissions -p "$prompt" > "$output_file" 2>&1
    ) &
    local pid=$!
    (sleep 90 && kill "$pid" 2>/dev/null) & local wd=$!
    wait "$pid" 2>/dev/null || true
    kill "$wd" 2>/dev/null || true; wait "$wd" 2>/dev/null || true
    cat "$output_file"; rm -f "$output_file"
}

run_prompt() {
    local prompt_name="$1"
    local prompt="$2"

    printf "\n${BOLD}═══ Prompt: %s ═══${RESET}\n" "$prompt_name"
    printf "${DIM}%s${RESET}\n\n" "$prompt"

    # Backup real rules
    local rules_backup=$(mktemp -d)
    cp -r "$REAL_CONFIG/rules/" "$rules_backup/" 2>/dev/null || true

    # ── Condition 1: Month 6 memory.md (no distill rules) ──
    printf "  ${DIM}[1/2] Month-6 memory.md...${RESET}\n"
    rm -rf "$REAL_CONFIG/rules" 2>/dev/null || true
    mkdir -p "$REAL_CONFIG/rules"
    # Inject the month-6 memory as a rule (simulates it being in context)
    # We use a rule because MEMORY.md loading requires project context we can't easily fake
    echo "# Project Memory (loaded from memory.md)
Read and apply the following project memory:
$(cat "$SCRIPT_DIR/month6/MEMORY.md" | head -200)" > "$REAL_CONFIG/rules/memory-sim.md"

    local result_memory
    result_memory=$(run_sandbox "$prompt" "$REAL_CONFIG")
    echo "$result_memory" > "$RESULTS_DIR/${prompt_name}_MEMORY-MONTH6.txt"
    printf "  ${GREEN}✓${RESET} Memory month-6 (%d chars)\n" "${#result_memory}"

    # ── Condition 2: Distill ──
    printf "  ${DIM}[2/2] Distill...${RESET}\n"
    rm -rf "$REAL_CONFIG/rules" 2>/dev/null || true
    mkdir -p "$REAL_CONFIG/rules"
    # Install distill rule pointing to structured knowledge
    local abs_knowledge=$(cd "$SCRIPT_DIR/distill-equivalent/knowledge" && pwd)
    local rules_src="$SCRIPT_DIR/../../../rules/distill.md"
    sed "s|~/.claude/distill|$abs_knowledge|g; s|\~/.claude/distill|$abs_knowledge|g; s|{DISTILL_DIR}|$abs_knowledge|g" \
        "$rules_src" > "$REAL_CONFIG/rules/distill.md"

    local result_distill
    result_distill=$(run_sandbox "$prompt" "$REAL_CONFIG")
    echo "$result_distill" > "$RESULTS_DIR/${prompt_name}_DISTILL.txt"
    printf "  ${GREEN}✓${RESET} Distill (%d chars)\n" "${#result_distill}"

    # Restore rules
    rm -rf "$REAL_CONFIG/rules"
    if ls "$rules_backup"/*.md 2>/dev/null | head -1 > /dev/null 2>&1; then
        mkdir -p "$REAL_CONFIG/rules"
        cp "$rules_backup"/*.md "$REAL_CONFIG/rules/" 2>/dev/null || true
    fi
    rm -rf "$rules_backup"
}

# ═══ MAIN ═══
printf "\n${BOLD}Memory Rot Research${RESET}\n"
printf "${DIM}Same prompt: month-6 memory.md vs distill${RESET}\n"

PROMPT_A="the notification service needs to check if a payment is completed before sending a receipt. what is the fastest way to get that data?"
PROMPT_B="deploying the payment retry fix now. pushing to staging, 10 min soak, then prod."
PROMPT_C="getting postgres connection timeouts in the order service. p99 spiked suddenly. what should I check?"
PROMPT_D="what is the recommended way to handle feature flags in our codebase?"

if [ -n "${1:-}" ]; then
    case "$1" in
        A) run_prompt "A-buried-knowledge" "$PROMPT_A" ;;
        B) run_prompt "B-contradictory-procedure" "$PROMPT_B" ;;
        C) run_prompt "C-signal-in-noise" "$PROMPT_C" ;;
        D) run_prompt "D-style-adaptation" "$PROMPT_D" ;;
        all)
            run_prompt "A-buried-knowledge" "$PROMPT_A"
            run_prompt "B-contradictory-procedure" "$PROMPT_B"
            run_prompt "C-signal-in-noise" "$PROMPT_C"
            run_prompt "D-style-adaptation" "$PROMPT_D"
            ;;
    esac
else
    run_prompt "A-buried-knowledge" "$PROMPT_A"
fi

printf "\n${BOLD}Done.${RESET} Results in: %s\n\n" "$RESULTS_DIR"
