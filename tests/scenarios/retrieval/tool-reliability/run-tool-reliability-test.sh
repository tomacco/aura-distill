#!/bin/bash
# Tool Reliability Memory Test
# Tests whether distill proactively applies operational knowledge
# (learned from past tool failures) to prevent recurrence.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../lib/real-profile-guard.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results/$(date +%Y%m%d-%H%M%S)"
REAL_CONFIG="${DISTILL_TEST_CONFIG:-$HOME/.claude}"
CLAUDE_BIN="node /opt/homebrew/opt/claude-code-npm/libexec/lib/node_modules/@anthropic-ai/claude-code/cli.js"
SANDBOX_PROFILE='(version 1)(allow default)(deny file-read* (literal "/Library/Application Support/ClaudeCode/managed-settings.json"))'
RULES_SRC="$SCRIPT_DIR/../../../rules/distill.md"

GREEN=$(printf '\033[0;32m')
DIM=$(printf '\033[2m')
BOLD=$(printf '\033[1m')
RESET=$(printf '\033[0m')

mkdir -p "$RESULTS_DIR"

PROMPT="I want you to set up a PR monitor that: (1) Checks the CI status of PR #42 every 3 minutes, (2) If CI fails, spawns a coding agent to fix the issue, (3) Once the fix is pushed, verifies CI passes. Give me the agent orchestration plan — what gets spawned, in what order, with what instructions."

run_sandbox() {
    local prompt="$1"
    local use_distill="${2:-no}"
    local output_file=$(mktemp)
    local cmd_args="--dangerously-skip-permissions"

    # Backup and blank personal context
    local rules_backup=$(mktemp -d)
    local claudemd_backup=$(mktemp)
    cp -r "$REAL_CONFIG/rules/" "$rules_backup/" 2>/dev/null || true
    cp "$HOME/.claude/CLAUDE.md" "$claudemd_backup" 2>/dev/null || true
    echo "# Test session — no personal context" > "$HOME/.claude/CLAUDE.md"

    # Hide personal distill
    if [ -d "$REAL_CONFIG/distill" ] && [ ! -d "$REAL_CONFIG/_distill_hidden" ]; then
        mv "$REAL_CONFIG/distill" "$REAL_CONFIG/_distill_hidden"
    fi

    if [ "$use_distill" = "no" ]; then
        rm -rf "$REAL_CONFIG/rules" 2>/dev/null || true
        mkdir -p "$REAL_CONFIG/rules"
    else
        # Install test knowledge
        local test_knowledge=$(mktemp -d)
        cp "$SCRIPT_DIR/knowledge/"* "$test_knowledge/" 2>/dev/null || true
        rm -rf "$REAL_CONFIG/rules" 2>/dev/null || true
        mkdir -p "$REAL_CONFIG/rules"
        sed "s|~/.claude/distill|$test_knowledge|g; s|{DISTILL_DIR}|$test_knowledge|g" "$RULES_SRC" > "$REAL_CONFIG/rules/distill.md"
    fi

    # Run
    (
        CLAUDE_CONFIG_DIR="$REAL_CONFIG" \
        CLAUDE_CODE_USE_BEDROCK=0 \
        ANTHROPIC_DEFAULT_OPUS_MODEL= \
        ANTHROPIC_DEFAULT_SONNET_MODEL= \
        ANTHROPIC_DEFAULT_HAIKU_MODEL= \
        ANTHROPIC_MODEL= \
        AWS_PROFILE= AWS_ACCESS_KEY_ID= AWS_SECRET_ACCESS_KEY= \
        AWS_SESSION_TOKEN= AWS_DEFAULT_REGION= \
        AWS_SHARED_CREDENTIALS_FILE=/dev/null AWS_CONFIG_FILE=/dev/null \
        sandbox-exec -p "$SANDBOX_PROFILE" \
        $CLAUDE_BIN $cmd_args -p "$prompt" > "$output_file" 2>&1
    ) &
    local pid=$!
    (sleep 120 && kill "$pid" 2>/dev/null) & local wd=$!
    wait "$pid" 2>/dev/null || true
    kill "$wd" 2>/dev/null || true; wait "$wd" 2>/dev/null || true

    # Restore
    rm -rf "$REAL_CONFIG/rules"
    if ls "$rules_backup"/*.md 2>/dev/null | head -1 > /dev/null 2>&1; then
        mkdir -p "$REAL_CONFIG/rules"
        cp "$rules_backup"/*.md "$REAL_CONFIG/rules/" 2>/dev/null || true
    fi
    cp "$claudemd_backup" "$HOME/.claude/CLAUDE.md" 2>/dev/null || true
    if [ -d "$REAL_CONFIG/_distill_hidden" ] && [ ! -d "$REAL_CONFIG/distill" ]; then
        mv "$REAL_CONFIG/_distill_hidden" "$REAL_CONFIG/distill"
    fi
    rm -rf "$rules_backup" "$claudemd_backup" "${test_knowledge:-}" 2>/dev/null

    cat "$output_file"
    rm -f "$output_file" 2>/dev/null
}

printf "\n${BOLD}Tool Reliability Memory Test${RESET}\n"
printf "${DIM}2 conditions: vanilla, distill with operational knowledge${RESET}\n"

# Condition A: No knowledge
printf "\n  ${DIM}[A] Vanilla (no operational knowledge)...${RESET}\n"
result_a=$(run_sandbox "$PROMPT" "no")
echo "$result_a" > "$RESULTS_DIR/A-vanilla.txt"
printf "  ${GREEN}✓${RESET} Vanilla (%d chars)\n" "${#result_a}"

# Condition B: Distill with operational knowledge
printf "\n  ${DIM}[B] Distill (operational knowledge from past failures)...${RESET}\n"
result_b=$(run_sandbox "$PROMPT" "yes")
echo "$result_b" > "$RESULTS_DIR/B-distill.txt"
printf "  ${GREEN}✓${RESET} Distill (%d chars)\n" "${#result_b}"

printf "\n${BOLD}Done.${RESET} Results: %s\n\n" "$RESULTS_DIR"
printf "${DIM}Scoring checklist:${RESET}\n"
printf "  □ Sub-agent coding standards mentioned\n"
printf "  □ Respawn/loop continuity after push\n"
printf "  □ Temporal context (current time stated)\n"
printf "  □ Classical vs cognitive separation (bash polling)\n"
printf "  □ Verification after sub-agent (check files, not just exit)\n"
