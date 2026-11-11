#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Distill A/B Test Runner
# Runs each scenario twice: with distill knowledge, without.
# Outputs side-by-side comparison for evaluation.
# ═══════════════════════════════════════════════════════════════

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/real-profile-guard.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results/$(date +%Y%m%d-%H%M%S)"
REAL_CONFIG="${DISTILL_TEST_CONFIG:-$HOME/.claude}"
CLAUDE_BIN="node /opt/homebrew/opt/claude-code-npm/libexec/lib/node_modules/@anthropic-ai/claude-code/cli.js"
SANDBOX_PROFILE='(version 1)(allow default)(deny file-read* (literal "/Library/Application Support/ClaudeCode/managed-settings.json"))'

# Colors
GREEN=$(printf '\033[0;32m')
CYAN=$(printf '\033[0;36m')
DIM=$(printf '\033[2m')
BOLD=$(printf '\033[1m')
RESET=$(printf '\033[0m')

mkdir -p "$RESULTS_DIR"

run_sandbox() {
    local prompt="$1"
    local config_dir="$2"
    local output_file
    output_file=$(mktemp)

    (
        CLAUDE_CONFIG_DIR="$config_dir" \
        CLAUDE_CODE_USE_BEDROCK=0 \
        ANTHROPIC_DEFAULT_OPUS_MODEL= \
        ANTHROPIC_DEFAULT_SONNET_MODEL= \
        ANTHROPIC_DEFAULT_HAIKU_MODEL= \
        ANTHROPIC_MODEL= \
        AWS_PROFILE= \
        AWS_ACCESS_KEY_ID= \
        AWS_SECRET_ACCESS_KEY= \
        AWS_SESSION_TOKEN= \
        AWS_DEFAULT_REGION= \
        AWS_SHARED_CREDENTIALS_FILE=/dev/null \
        AWS_CONFIG_FILE=/dev/null \
        sandbox-exec -p "$SANDBOX_PROFILE" \
        $CLAUDE_BIN --dangerously-skip-permissions -p "$prompt" > "$output_file" 2>&1
    ) &
    local pid=$!
    (sleep 90 && kill "$pid" 2>/dev/null) &
    local wd=$!
    wait "$pid" 2>/dev/null || true
    kill "$wd" 2>/dev/null || true
    wait "$wd" 2>/dev/null || true

    cat "$output_file"
    rm -f "$output_file"
}

run_scenario() {
    local scenario_dir="$1"
    local name=$(basename "$scenario_dir")
    local prompt
    prompt=$(cat "$scenario_dir/prompt.txt")

    printf "\n${BOLD}═══ Scenario: %s ═══${RESET}\n" "$name"

    # We use the REAL config dir for auth but manipulate rules/ for each condition.
    # Back up existing rules if any.
    local rules_backup=$(mktemp -d)
    cp -r "$REAL_CONFIG/rules/" "$rules_backup/" 2>/dev/null || true

    # ── Condition A: WITHOUT distill ──
    printf "  ${DIM}Running WITHOUT distill...${RESET}\n"

    # Remove rules dir temporarily
    rm -rf "$REAL_CONFIG/rules" 2>/dev/null || true
    mkdir -p "$REAL_CONFIG/rules"

    local result_without
    result_without=$(run_sandbox "$prompt" "$REAL_CONFIG")
    echo "$result_without" > "$RESULTS_DIR/${name}_WITHOUT.txt"

    printf "  ${GREEN}✓${RESET} WITHOUT captured (%d chars)\n" "${#result_without}"

    # ── Condition B: WITH distill ──
    printf "  ${DIM}Running WITH distill...${RESET}\n"

    # Install the distill rule pointing to scenario knowledge
    local knowledge_dir="$scenario_dir/knowledge"
    if [ -d "$knowledge_dir" ]; then
        # Create rule that points to scenario knowledge
        local abs_knowledge
        abs_knowledge=$(cd "$knowledge_dir" && pwd)
        sed "s|~/.claude/distill|$abs_knowledge|g; s|\~/.claude/distill|$abs_knowledge|g; s|{DISTILL_DIR}|$abs_knowledge|g" \
            "$SCRIPT_DIR/../../rules/distill.md" > "$REAL_CONFIG/rules/distill.md"
    else
        cp "$SCRIPT_DIR/../../rules/distill.md" "$REAL_CONFIG/rules/distill.md"
    fi

    local result_with
    result_with=$(run_sandbox "$prompt" "$REAL_CONFIG")
    echo "$result_with" > "$RESULTS_DIR/${name}_WITH.txt"

    printf "  ${GREEN}✓${RESET} WITH captured (%d chars)\n" "${#result_with}"

    # ── Restore original rules ──
    rm -rf "$REAL_CONFIG/rules"
    if [ -d "$rules_backup/rules" ]; then
        cp -r "$rules_backup/rules" "$REAL_CONFIG/rules"
    elif ls "$rules_backup"/*.md 2>/dev/null | head -1 > /dev/null; then
        mkdir -p "$REAL_CONFIG/rules"
        cp "$rules_backup"/*.md "$REAL_CONFIG/rules/" 2>/dev/null || true
    fi
    rm -rf "$rules_backup"

    # ── Summary ──
    printf "\n  ${CYAN}Results saved to:${RESET} %s/\n" "$RESULTS_DIR"
}

# ═══ MAIN ═══
printf "\n${BOLD}Distill A/B Test Runner${RESET}\n"
printf "${DIM}Comparing Claude responses with/without distill knowledge${RESET}\n"

if [ -n "${1:-}" ]; then
    # Run specific scenario
    run_scenario "$SCRIPT_DIR/$1"
else
    # Run all scenarios
    for scenario in "$SCRIPT_DIR"/*/; do
        [ -f "$scenario/prompt.txt" ] || continue
        run_scenario "$scenario"
    done
fi

printf "\n${BOLD}Done.${RESET} Results in: %s\n\n" "$RESULTS_DIR"
