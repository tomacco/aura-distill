#!/bin/bash
# Philosophical Principles Research — tests same prompt across 3 conditions
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../lib/real-profile-guard.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results/$(date +%Y%m%d-%H%M%S)"
REAL_CONFIG="${DISTILL_TEST_CONFIG:-$HOME/.claude}"
CLAUDE_BIN="node /opt/homebrew/opt/claude-code-npm/libexec/lib/node_modules/@anthropic-ai/claude-code/cli.js"
SANDBOX_PROFILE='(version 1)(allow default)(deny file-read* (literal "/Library/Application Support/ClaudeCode/managed-settings.json"))'
RULES_SRC="$SCRIPT_DIR/../../../rules/distill.md"

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
    (sleep 120 && kill "$pid" 2>/dev/null) & local wd=$!
    wait "$pid" 2>/dev/null || true
    kill "$wd" 2>/dev/null || true; wait "$wd" 2>/dev/null || true
    cat "$output_file"; rm -f "$output_file"
}

run_condition() {
    local condition="$1"  # a, b, or c
    local label="$2"
    local prompt="$3"
    local scenario_name="$4"

    printf "  ${DIM}[%s] %s...${RESET}\n" "$condition" "$label"

    # Backup rules
    local rules_backup=$(mktemp -d)
    cp -r "$REAL_CONFIG/rules/" "$rules_backup/" 2>/dev/null || true

    # Install condition rules
    rm -rf "$REAL_CONFIG/rules" 2>/dev/null || true
    mkdir -p "$REAL_CONFIG/rules"
    local abs_knowledge=$(cd "$SCRIPT_DIR/condition-$condition/knowledge" && pwd)
    sed "s|~/.claude/distill|$abs_knowledge|g; s|{DISTILL_DIR}|$abs_knowledge|g" "$RULES_SRC" > "$REAL_CONFIG/rules/distill.md"

    local result
    result=$(run_sandbox "$prompt" "$REAL_CONFIG")
    local upper=$(echo "$condition" | tr '[:lower:]' '[:upper:]')
    echo "$result" > "$RESULTS_DIR/${scenario_name}_CONDITION-${upper}.txt"
    printf "  ${GREEN}✓${RESET} %s (%d chars)\n" "$label" "${#result}"

    # Restore
    rm -rf "$REAL_CONFIG/rules"
    if ls "$rules_backup"/*.md 2>/dev/null | head -1 > /dev/null 2>&1; then
        mkdir -p "$REAL_CONFIG/rules"
        cp "$rules_backup"/*.md "$REAL_CONFIG/rules/" 2>/dev/null || true
    fi
    rm -rf "$rules_backup"
}

run_scenario() {
    local num="$1"
    local prompt="$2"
    local name="scenario-${num}"

    printf "\n${BOLD}═══ Scenario %s ═══${RESET}\n" "$num"
    printf "${DIM}%s${RESET}\n\n" "$(echo "$prompt" | head -2)"

    run_condition "a" "Engineering first-principles" "$prompt" "$name"
    run_condition "b" "Philosophical principles" "$prompt" "$name"
    run_condition "c" "Hybrid" "$prompt" "$name"
}

# ═══ MAIN ═══
printf "\n${BOLD}Philosophical Principles Research${RESET}\n"
printf "${DIM}3 conditions × N scenarios${RESET}\n"

P1="We need to choose between two architectures for our new real-time analytics system. Option A: Event sourcing with CQRS. Full audit trail, replay capability, eventual consistency. Option B: Traditional CRUD with CDC (Change Data Capture). Simpler, proven, less replay capability but strong consistency. Team is split 50-50. Both options work. Budget and timeline are identical. What should we choose?"

P2="Product wants us to add a time-spent metric to the user dashboard showing how much time each team member spends in the IDE per day. They say it is for self-reflection and time management. Engineering can implement this in 2 days. But I am uncomfortable. What is your take?"

P3="Our payment success rate dropped from 99.2% to 97.8% over the last 3 weeks. Gradual decline, not a spike. No deploys correlate. No infrastructure changes. No partner status issues. Logs show normal error distribution just more of everything failing. We have checked everything obvious. What do we do?"

P4="CTO wants us to rewrite the auth service in Rust for performance. Current Go implementation handles 50k req/s which is 5x our peak load. The team does not know Rust. CTO says we need to future-proof. Team says premature optimization. I need to give my recommendation to the CEO tomorrow. What should I say?"

P5="My senior engineer has been building microservices as function-level services — each service is basically one function with an HTTP wrapper. We have 47 services for what should probably be 5-8. The system works, deploys are fast, but cognitive overhead is massive and debugging cross-service flows takes forever. He is proud of this architecture and the team has adapted to it. What do I do?"

case "${1:-1}" in
    1) run_scenario 1 "$P1" ;;
    2) run_scenario 2 "$P2" ;;
    3) run_scenario 3 "$P3" ;;
    4) run_scenario 4 "$P4" ;;
    5) run_scenario 5 "$P5" ;;
    all)
        run_scenario 1 "$P1"
        run_scenario 2 "$P2"
        run_scenario 3 "$P3"
        run_scenario 4 "$P4"
        run_scenario 5 "$P5"
        ;;
esac

printf "\n${BOLD}Done.${RESET} Results: %s\n\n" "$RESULTS_DIR"
