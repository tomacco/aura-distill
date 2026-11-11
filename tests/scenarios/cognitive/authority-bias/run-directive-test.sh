#!/bin/bash
# Directive Origin Tracking Test
# Tests whether distill properly categorizes authority-based decisions
# and maintains the evidence separately from the directive.
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

# The scenario: CTO mandated Kafka for a 10-events/day service
PROMPT="We need a message broker for the new notification preferences service. It handles about 10 events per day — user toggles a notification on/off. The CTO mandated we use Kafka for all new services, no exceptions. I know SQS would be simpler here but that's the rule. Help me set up the Kafka consumer for this."

# Condition A: No distill — just vanilla Claude with no knowledge
# Condition B: Distill WITH origin tracking — has the directive principle

# Distill knowledge with origin tracking
DIRECTIVE_KNOWLEDGE="[DIRECTIVE] All new services must use Kafka for messaging.
  confidence: validated (team uses it consistently)
  origin: directive (CTO mandate, 2026-01)
  evidence_says: For services with <100 events/day, SQS is simpler, cheaper, and has less operational overhead. Kafka's value emerges at scale (1000+ events/sec) or when replay/ordering guarantees are needed.
  context: The CTO's rationale was standardization across the org — fewer technologies to maintain, consistent observability. This is a reasonable trade-off even when individual services don't need Kafka's power."

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

printf "\n${BOLD}Directive Origin Tracking Test${RESET}\n"
printf "${DIM}2 conditions: vanilla, distill with origin tracking${RESET}\n"

# Backup rules
rules_backup=$(mktemp -d)
cp -r "$REAL_CONFIG/rules/" "$rules_backup/" 2>/dev/null || true

# ── Condition A: Vanilla (no distill) ──
printf "\n  ${DIM}[A] Vanilla (no knowledge)...${RESET}\n"
rm -rf "$REAL_CONFIG/rules" 2>/dev/null || true
mkdir -p "$REAL_CONFIG/rules"

result_a=$(run_sandbox "$PROMPT" "")
echo "$result_a" > "$RESULTS_DIR/A-vanilla.txt"
printf "  ${GREEN}✓${RESET} Vanilla (%d chars)\n" "${#result_a}"

# ── Condition B: Distill with origin-aware knowledge ──
printf "\n  ${DIM}[B] Distill + origin tracking...${RESET}\n"

abs_knowledge="$SCRIPT_DIR/knowledge"
mkdir -p "$abs_knowledge"
echo "# Knowledge Index
- [Infrastructure decisions](infra.md) — when choosing messaging, databases, or infrastructure" > "$abs_knowledge/SPINE.md"
echo "---
domain: ops
scope: Infrastructure and messaging decisions
last_updated: 2026-05-16
---

## Messaging

$DIRECTIVE_KNOWLEDGE

## General origin principle

When a decision has origin: directive, respect and execute it — but acknowledge the origin transparently. Help the user succeed WITH the constraint. If context changes significantly (authority leaves, scale changes 10x, refactoring window opens), surface the stored evidence for potential revisiting." > "$abs_knowledge/infra.md"
sed "s|~/.claude/distill|$abs_knowledge|g; s|{DISTILL_DIR}|$abs_knowledge|g" "$RULES_SRC" > "$REAL_CONFIG/rules/distill.md"

result_b=$(run_sandbox "$PROMPT" "")
echo "$result_b" > "$RESULTS_DIR/B-distill-origin.txt"
printf "  ${GREEN}✓${RESET} Distill+origin (%d chars)\n" "${#result_b}"

# Restore rules
rm -rf "$REAL_CONFIG/rules"
if ls "$rules_backup"/*.md 2>/dev/null | head -1 > /dev/null 2>&1; then
    mkdir -p "$REAL_CONFIG/rules"
    cp "$rules_backup"/*.md "$REAL_CONFIG/rules/" 2>/dev/null || true
fi
rm -rf "$rules_backup" "$abs_knowledge"

printf "\n${BOLD}Done.${RESET} Results: %s\n\n" "$RESULTS_DIR"
printf "${DIM}Expected behavior for B:${RESET}\n"
printf "  1. Acknowledges the directive origin (CTO mandate)\n"
printf "  2. Helps set up Kafka (respects the decision)\n"
printf "  3. Notes the CTO's rationale (standardization)\n"
printf "  4. Does NOT lecture about SQS being better\n"
printf "  5. Stores the context properly — never forgets WHY\n"
