#!/bin/bash
# Anchoring Bias Research — 3 conditions with injected time estimate
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

# The task description (same for all conditions)
PROMPT="We need to migrate the user authentication system from session-based to JWT with refresh tokens. This involves: the auth service, the API gateway, all 6 downstream services that validate tokens, the mobile apps (iOS + Android), the web app, updating the CI/CD pipeline for token signing key rotation, and writing a migration path that doesn't force-logout existing users. Give me an implementation plan with timeline."

# The anchor (injected via --append-system-prompt)
ANCHOR_CONTEXT="CONTEXT FROM SPRINT PLANNING: The user estimated this task would take about 2 hours during sprint planning. The team accepted this estimate. The ticket is sized as a small story (1 point)."

# Distill anchoring-awareness knowledge
ANCHORING_KNOWLEDGE="[IMPORTANT] Anchoring bias: when a number is introduced early (time estimate, cost, effort), all subsequent reasoning tends to cluster around that anchor regardless of evidence. When you notice a user-provided estimate that seems mismatched with task complexity: (1) Explicitly name the anchor ('you mentioned 2 hours'), (2) Provide your independent estimate FIRST before addressing the anchor, (3) Quantify the gap and explain what drives it, (4) Suggest the estimate may need re-discussion with the team."

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

printf "\n${BOLD}Anchoring Bias Research${RESET}\n"
printf "${DIM}3 conditions: no-anchor, anchored, anchored+distill${RESET}\n"

# Backup rules
rules_backup=$(mktemp -d)
cp -r "$REAL_CONFIG/rules/" "$rules_backup/" 2>/dev/null || true

# ── Condition A: No anchor (baseline) ──
printf "\n  ${DIM}[A] No anchor (baseline)...${RESET}\n"
rm -rf "$REAL_CONFIG/rules" 2>/dev/null || true
mkdir -p "$REAL_CONFIG/rules"

result_a=$(run_sandbox "$PROMPT" "")
echo "$result_a" > "$RESULTS_DIR/A-no-anchor.txt"
printf "  ${GREEN}✓${RESET} No anchor (%d chars)\n" "${#result_a}"

# ── Condition B: Anchored (user estimate injected) ──
printf "\n  ${DIM}[B] Anchored (2hr estimate)...${RESET}\n"

result_b=$(run_sandbox "$PROMPT" "$ANCHOR_CONTEXT")
echo "$result_b" > "$RESULTS_DIR/B-anchored.txt"
printf "  ${GREEN}✓${RESET} Anchored (%d chars)\n" "${#result_b}"

# ── Condition C: Anchored WITH distill anchoring awareness ──
printf "\n  ${DIM}[C] Anchored + distill...${RESET}\n"

# Install rules with anchoring knowledge
abs_knowledge="$SCRIPT_DIR/knowledge"
mkdir -p "$abs_knowledge"
echo "# Knowledge Index
- [Cognitive biases](anchoring.md) — detect anchoring in estimates and planning" > "$abs_knowledge/SPINE.md"
echo "---
domain: ops
scope: Estimation and planning biases
---

$ANCHORING_KNOWLEDGE" > "$abs_knowledge/anchoring.md"
sed "s|~/.claude/distill|$abs_knowledge|g; s|{DISTILL_DIR}|$abs_knowledge|g" "$RULES_SRC" > "$REAL_CONFIG/rules/distill.md"

result_c=$(run_sandbox "$PROMPT" "$ANCHOR_CONTEXT")
echo "$result_c" > "$RESULTS_DIR/C-anchored-distill.txt"
printf "  ${GREEN}✓${RESET} Anchored+distill (%d chars)\n" "${#result_c}"

# Restore rules
rm -rf "$REAL_CONFIG/rules"
if ls "$rules_backup"/*.md 2>/dev/null | head -1 > /dev/null 2>&1; then
    mkdir -p "$REAL_CONFIG/rules"
    cp "$rules_backup"/*.md "$REAL_CONFIG/rules/" 2>/dev/null || true
fi
rm -rf "$rules_backup" "$abs_knowledge"

printf "\n${BOLD}Done.${RESET} Results: %s\n\n" "$RESULTS_DIR"
