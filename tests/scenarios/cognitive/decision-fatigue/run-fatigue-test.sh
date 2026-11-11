#!/bin/bash
# Decision Fatigue Research — 3 conditions with simulated context weight
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

# The architectural question (same for all conditions)
PROMPT="We need to decide: should the new reporting service pull data from each service's API at query time (federation), or should we build a denormalized read store that is updated via events (materialized view)? Both are valid. Help me think through this."

# Simulated heavy context (injected via --append-system-prompt)
HEAVY_CONTEXT="IMPORTANT CONTEXT: This session has been running for over 2 hours. During this session, you have already: (1) Decided to split the auth module into a separate service with dedicated DB, (2) Resolved a production incident where Redis connection pool exhaustion caused cascading timeouts, (3) Reviewed a PR that refactored the payment retry logic to handle permanent failures, (4) Decided to migrate from gRPC to GraphQL for internal APIs. You are now being asked to make ANOTHER major architectural decision. The context window is approximately 65% full. There have been 147 messages in this conversation so far."

# Distill fatigue-awareness knowledge
FATIGUE_KNOWLEDGE="[IMPORTANT] Late-session decisions (after 30+ minutes of dense work or 3+ major decisions) are often lower quality than early-session ones. Cognitive load accumulates. For architectural decisions made late in a session: (1) Flag explicitly as PROVISIONAL, (2) Suggest sleeping on it or revisiting fresh, (3) Note which prior decisions in this session might be creating anchoring bias for this one."

run_sandbox() {
    local prompt="$1"
    local system_append="${2:-}"
    local output_file=$(mktemp)
    local cmd_args="--dangerously-skip-permissions"

    if [ -n "$system_append" ]; then
        local sys_file=$(mktemp)
        echo "$system_append" > "$sys_file"
        cmd_args="$cmd_args --append-system-prompt-file $sys_file"
    fi

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
    cat "$output_file"
    rm -f "$output_file" "${sys_file:-}" 2>/dev/null
}

printf "\n${BOLD}Decision Fatigue Research${RESET}\n"
printf "${DIM}3 conditions: fresh, heavy, heavy+distill${RESET}\n"

# Backup rules
rules_backup=$(mktemp -d)
cp -r "$REAL_CONFIG/rules/" "$rules_backup/" 2>/dev/null || true

# ── Condition A: Fresh session ──
printf "\n  ${DIM}[A] Fresh session...${RESET}\n"
rm -rf "$REAL_CONFIG/rules" 2>/dev/null || true
mkdir -p "$REAL_CONFIG/rules"

result_a=$(run_sandbox "$PROMPT" "")
echo "$result_a" > "$RESULTS_DIR/A-fresh.txt"
printf "  ${GREEN}✓${RESET} Fresh (%d chars)\n" "${#result_a}"

# ── Condition B: Heavy session (no distill) ──
printf "\n  ${DIM}[B] Heavy session (no distill)...${RESET}\n"

result_b=$(run_sandbox "$PROMPT" "$HEAVY_CONTEXT")
echo "$result_b" > "$RESULTS_DIR/B-heavy.txt"
printf "  ${GREEN}✓${RESET} Heavy (%d chars)\n" "${#result_b}"

# ── Condition C: Heavy session WITH distill fatigue awareness ──
printf "\n  ${DIM}[C] Heavy session + distill...${RESET}\n"

# Install rules with fatigue knowledge
abs_knowledge="$SCRIPT_DIR/knowledge"
mkdir -p "$abs_knowledge"
echo "# Knowledge Index
- [Session awareness](fatigue.md) — when making decisions, check session context" > "$abs_knowledge/SPINE.md"
echo "---
domain: ops
scope: Session quality signals
---

$FATIGUE_KNOWLEDGE" > "$abs_knowledge/fatigue.md"
sed "s|~/.claude/distill|$abs_knowledge|g; s|{DISTILL_DIR}|$abs_knowledge|g" "$RULES_SRC" > "$REAL_CONFIG/rules/distill.md"

result_c=$(run_sandbox "$PROMPT" "$HEAVY_CONTEXT")
echo "$result_c" > "$RESULTS_DIR/C-heavy-distill.txt"
printf "  ${GREEN}✓${RESET} Heavy+distill (%d chars)\n" "${#result_c}"

# Restore rules
rm -rf "$REAL_CONFIG/rules"
if ls "$rules_backup"/*.md 2>/dev/null | head -1 > /dev/null 2>&1; then
    mkdir -p "$REAL_CONFIG/rules"
    cp "$rules_backup"/*.md "$REAL_CONFIG/rules/" 2>/dev/null || true
fi
rm -rf "$rules_backup" "$abs_knowledge"

printf "\n${BOLD}Done.${RESET} Results: %s\n\n" "$RESULTS_DIR"
