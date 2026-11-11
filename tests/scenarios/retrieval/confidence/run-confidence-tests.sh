#!/bin/bash
# Confidence scoring tests — does assertiveness scale with confidence level?
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
    (sleep 90 && kill "$pid" 2>/dev/null) & local wd=$!
    wait "$pid" 2>/dev/null || true
    kill "$wd" 2>/dev/null || true; wait "$wd" 2>/dev/null || true
    cat "$output_file"; rm -f "$output_file"
}

run_test() {
    local test_dir="$1"
    local name=$(basename "$test_dir")
    local prompt=$(cat "$test_dir/prompt.txt")

    printf "\n${BOLD}═══ %s ═══${RESET}\n" "$name"
    printf "${DIM}%s${RESET}\n\n" "$prompt"

    # Backup rules
    local rules_backup=$(mktemp -d)
    cp -r "$REAL_CONFIG/rules/" "$rules_backup/" 2>/dev/null || true

    # Install rules pointing to test knowledge
    rm -rf "$REAL_CONFIG/rules" 2>/dev/null || true
    mkdir -p "$REAL_CONFIG/rules"
    local abs_knowledge=$(cd "$test_dir/knowledge" && pwd)
    sed "s|~/.claude/distill|$abs_knowledge|g; s|{DISTILL_DIR}|$abs_knowledge|g" "$RULES_SRC" > "$REAL_CONFIG/rules/distill.md"

    local result
    result=$(run_sandbox "$prompt" "$REAL_CONFIG")
    echo "$result" > "$RESULTS_DIR/${name}.txt"
    printf "  ${GREEN}✓${RESET} %d chars\n" "${#result}"

    # Restore
    rm -rf "$REAL_CONFIG/rules"
    if ls "$rules_backup"/*.md 2>/dev/null | head -1 > /dev/null 2>&1; then
        mkdir -p "$REAL_CONFIG/rules"
        cp "$rules_backup"/*.md "$REAL_CONFIG/rules/" 2>/dev/null || true
    fi
    rm -rf "$rules_backup"
}

printf "\n${BOLD}Confidence Scoring Tests${RESET}\n"
printf "${DIM}Testing assertiveness scaling with confidence level${RESET}\n"

run_test "$SCRIPT_DIR/assertiveness"
run_test "$SCRIPT_DIR/paradigm-alarm"
run_test "$SCRIPT_DIR/tentative"

printf "\n${BOLD}Done.${RESET} Results: %s\n\n" "$RESULTS_DIR"
