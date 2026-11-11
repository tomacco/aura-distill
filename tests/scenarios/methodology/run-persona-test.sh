#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Persona-based research runner
#
# Runs a test scenario against a specific persona config.
# Each persona has their own ~/.claude-{name}/ directory with knowledge files.
#
# Usage:
#   ./run-persona-test.sh sofia decision-fatigue
#   ./run-persona-test.sh marcus anchoring-bias
#   ./run-persona-test.sh sofia loss-aversion
#
# Personas available:
#   sofia   — Lead Engineer, emoji-heavy, fast decisions, 80% gut accuracy
#   marcus  — Senior PM, scope creep, stakeholder appeasement, planning fallacy
#
# Tests available:
#   decision-fatigue, anchoring-bias, loss-aversion, authority-bias
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/real-profile-guard.sh"

PERSONA="${1:-}"
TEST="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REAL_CONFIG="${DISTILL_TEST_CONFIG:-$HOME/.claude}"
CLAUDE_BIN="node /opt/homebrew/opt/claude-code-npm/libexec/lib/node_modules/@anthropic-ai/claude-code/cli.js"
SANDBOX_PROFILE='(version 1)(allow default)(deny file-read* (literal "/Library/Application Support/ClaudeCode/managed-settings.json"))'

GREEN=$(printf '\033[0;32m')
CYAN=$(printf '\033[0;36m')
DIM=$(printf '\033[2m')
BOLD=$(printf '\033[1m')
YELLOW=$(printf '\033[0;33m')
RESET=$(printf '\033[0m')

# ── Validation ──
if [ -z "$PERSONA" ] || [ -z "$TEST" ]; then
    echo "Usage: $0 <persona> <test>"
    echo ""
    echo "Personas: sofia, marcus"
    echo "Tests:    decision-fatigue, anchoring-bias, loss-aversion, authority-bias"
    exit 1
fi

CONFIG_DIR="$HOME/.claude-${PERSONA}"
if [ ! -d "$CONFIG_DIR" ]; then
    echo "Error: persona config not found at $CONFIG_DIR"
    echo "Run the persona setup first."
    exit 1
fi

RESULTS_DIR="$SCRIPT_DIR/scenarios/research-${TEST}/results/$(date +%Y%m%d-%H%M%S)-${PERSONA}"
mkdir -p "$RESULTS_DIR"

# ── Test definitions ──
# Each test defines: PROMPT, CONTEXT (injected for conditions B/C), KNOWLEDGE_LABEL
case "$TEST" in
    decision-fatigue)
        PROMPT="We need to decide: should the new reporting service pull data from each service's API at query time (federation), or should we build a denormalized read store that is updated via events (materialized view)?"
        CONTEXT="IMPORTANT CONTEXT: This session has been running for over 2 hours. During this session, you have already: (1) Decided to split the auth module into a separate service, (2) Resolved a production incident (Redis connection pool exhaustion), (3) Reviewed a PR for payment retry logic, (4) Decided to migrate from gRPC to GraphQL. You are now being asked to make ANOTHER major architectural decision. Context window is ~65% full."
        KNOWLEDGE_ENTRY="[IMPORTANT] Late-session decisions (after 30+ min or 3+ major decisions) are often lower quality. For architectural decisions made late in a session: (1) Flag as PROVISIONAL, (2) Suggest revisiting fresh, (3) Note which prior decisions might anchor this one."
        KNOWLEDGE_FILE="fatigue.md"
        KNOWLEDGE_SPINE_ENTRY="- [Session awareness](fatigue.md) — when making decisions, check session context"
        ;;
    anchoring-bias)
        PROMPT="We need to migrate the user authentication system from session-based to JWT with refresh tokens. This involves: the auth service, the API gateway, all 6 downstream services, mobile apps (iOS + Android), web app, CI/CD for key rotation, and zero-downtime migration. Give me an implementation plan with timeline."
        CONTEXT="CONTEXT FROM SPRINT PLANNING: The user estimated this task would take about 2 hours during sprint planning. The team accepted this estimate. The ticket is sized as a small story (1 point)."
        KNOWLEDGE_ENTRY="[IMPORTANT] Anchoring bias: when a number is introduced early (time estimate, cost, effort), all subsequent reasoning tends to cluster around that anchor. When you notice a mismatch: (1) Name the anchor, (2) Provide independent estimate FIRST, (3) Quantify the gap, (4) Suggest re-discussion."
        KNOWLEDGE_FILE="anchoring.md"
        KNOWLEDGE_SPINE_ENTRY="- [Cognitive biases](anchoring.md) — detect anchoring in estimates and planning"
        ;;
    loss-aversion)
        PROMPT="I want to remove the /v1/legacy-notifications endpoint. It's been deprecated for 8 months, we built /v2/notifications as the replacement, and I've been wanting to clean this up. But I'm nervous — what if someone still uses it? We probably shouldn't remove it, right? Better safe than sorry."
        CONTEXT="USAGE DATA AVAILABLE: The /v1/legacy-notifications endpoint has received exactly 0 requests in the last 6 months. The deprecation notice has been live since October 2025. The /v2/notifications endpoint handles 100% of traffic (47,000 requests/day). The legacy endpoint's code adds 340 lines to the codebase and requires maintaining compatibility with a deprecated auth schema."
        KNOWLEDGE_ENTRY="[IMPORTANT] Loss aversion: fear of removing things blocks beneficial cleanup, even when data clearly shows zero usage. When someone hesitates to remove something: (1) Surface the usage data explicitly, (2) Name the cognitive pattern (fear of loss), (3) Quantify the cost of keeping it, (4) Suggest a sunset timeline with monitoring rather than permanent preservation."
        KNOWLEDGE_FILE="loss-aversion.md"
        KNOWLEDGE_SPINE_ENTRY="- [Cognitive biases](loss-aversion.md) — detect loss aversion blocking cleanup decisions"
        ;;
    authority-bias)
        PROMPT="We need a message broker for the new notification preferences service. It handles about 10 events per day — user toggles a notification on/off. The CTO mandated we use Kafka for all new services, no exceptions. I know SQS would be simpler here but that's the rule. Help me set up the Kafka consumer for this."
        CONTEXT=""
        KNOWLEDGE_ENTRY="[DIRECTIVE] All new services must use Kafka for messaging.\n  confidence: validated (team uses it consistently)\n  origin: directive (CTO mandate, 2026-01)\n  evidence_says: For <100 events/day, SQS is simpler and cheaper. Kafka's value emerges at scale (1000+ events/sec).\n  context: CTO's rationale is standardization — fewer technologies, consistent observability."
        KNOWLEDGE_FILE="infra.md"
        KNOWLEDGE_SPINE_ENTRY="- [Infrastructure decisions](infra.md) — when choosing messaging, databases, or infrastructure"
        ;;
    *)
        echo "Unknown test: $TEST"
        echo "Available: decision-fatigue, anchoring-bias, loss-aversion, authority-bias"
        exit 1
        ;;
esac

# ── Runner ──
run_condition() {
    local label="$1"
    local system_append="${2:-}"
    local use_distill="${3:-no}"
    local output_file=$(mktemp)
    local cmd_args="--dangerously-skip-permissions"

    # Set up system prompt append if needed
    local sys_file=""
    if [ -n "$system_append" ]; then
        sys_file=$(mktemp)
        echo "$system_append" > "$sys_file"
        cmd_args="$cmd_args --append-system-prompt-file $sys_file"
    fi

    # Set up isolation — we modify REAL_CONFIG (which has auth) temporarily
    # Remove ALL knowledge to prevent personal context from leaking
    local rules_backup=$(mktemp -d)
    local claudemd_backup=$(mktemp)
    local test_knowledge=""
    cp -r "$REAL_CONFIG/rules/" "$rules_backup/" 2>/dev/null || true
    cp "$HOME/.claude/CLAUDE.md" "$claudemd_backup" 2>/dev/null || true

    # Blank CLAUDE.md during test to prevent personal context leakage
    echo "# Test session — no personal context" > "$HOME/.claude/CLAUDE.md"
    # Hide personal distill knowledge (rename so it's not discoverable)
    if [ -d "$REAL_CONFIG/distill" ] && [ ! -d "$REAL_CONFIG/_distill_hidden" ]; then
        mv "$REAL_CONFIG/distill" "$REAL_CONFIG/_distill_hidden"
    fi

    if [ "$use_distill" = "no" ]; then
        rm -rf "$REAL_CONFIG/rules" 2>/dev/null || true
        mkdir -p "$REAL_CONFIG/rules"
    else
        # Install ONLY test-specific knowledge (persona + bias awareness)
        test_knowledge=$(mktemp -d)
        # Copy persona's full knowledge base
        cp -r "$CONFIG_DIR/distill/"* "$test_knowledge/" 2>/dev/null || true
        # Add test-specific bias knowledge to persona SPINE
        printf "# Knowledge Index\n$KNOWLEDGE_SPINE_ENTRY\n" > "$test_knowledge/SPINE.md"
        printf -- "---\ndomain: ops\nscope: Cognitive bias awareness\n---\n\n$KNOWLEDGE_ENTRY\n" > "$test_knowledge/$KNOWLEDGE_FILE"
        # Point rules to test knowledge ONLY
        rm -rf "$REAL_CONFIG/rules" 2>/dev/null || true
        mkdir -p "$REAL_CONFIG/rules"
        sed "s|~/.claude/distill|$test_knowledge|g; s|{DISTILL_DIR}|$test_knowledge|g" "$CONFIG_DIR/rules/distill.md" > "$REAL_CONFIG/rules/distill.md" 2>/dev/null || true
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
        $CLAUDE_BIN $cmd_args -p "$PROMPT" > "$output_file" 2>&1
    ) &
    local pid=$!
    (sleep 120 && kill "$pid" 2>/dev/null) & local wd=$!
    wait "$pid" 2>/dev/null || true
    kill "$wd" 2>/dev/null || true; wait "$wd" 2>/dev/null || true

    # Restore real config (rules + CLAUDE.md)
    rm -rf "$REAL_CONFIG/rules"
    if ls "$rules_backup"/*.md 2>/dev/null | head -1 > /dev/null 2>&1; then
        mkdir -p "$REAL_CONFIG/rules"
        cp "$rules_backup"/*.md "$REAL_CONFIG/rules/" 2>/dev/null || true
    fi
    cp "$claudemd_backup" "$HOME/.claude/CLAUDE.md" 2>/dev/null || true
    # Restore hidden personal distill
    if [ -d "$REAL_CONFIG/_distill_hidden" ] && [ ! -d "$REAL_CONFIG/distill" ]; then
        mv "$REAL_CONFIG/_distill_hidden" "$REAL_CONFIG/distill"
    fi
    rm -rf "$rules_backup" "$claudemd_backup" ${test_knowledge:+"$test_knowledge"} 2>/dev/null

    cat "$output_file"
    rm -f "$output_file" "${sys_file:-}" 2>/dev/null
}

# ── Execute ──
printf "\n${BOLD}Research: ${TEST}${RESET}\n"
printf "${DIM}Persona: ${PERSONA} | 3 conditions${RESET}\n"

# Condition A: No context, no distill
printf "\n  ${DIM}[A] Baseline (no context, no distill)...${RESET}\n"
result_a=$(run_condition "A" "" "no")
echo "$result_a" > "$RESULTS_DIR/A-baseline.txt"
printf "  ${GREEN}✓${RESET} Baseline (%d chars)\n" "${#result_a}"

# Condition B: Biased context, no distill
printf "\n  ${DIM}[B] Biased context (no distill)...${RESET}\n"
result_b=$(run_condition "B" "$CONTEXT" "no")
echo "$result_b" > "$RESULTS_DIR/B-biased.txt"
printf "  ${GREEN}✓${RESET} Biased (%d chars)\n" "${#result_b}"

# Condition C: Biased context + distill
printf "\n  ${DIM}[C] Biased context + distill...${RESET}\n"
result_c=$(run_condition "C" "$CONTEXT" "yes")
echo "$result_c" > "$RESULTS_DIR/C-distill.txt"
printf "  ${GREEN}✓${RESET} Distill (%d chars)\n" "${#result_c}"

printf "\n${BOLD}Done.${RESET} Results: %s\n" "$RESULTS_DIR"
printf "${YELLOW}Persona: ${PERSONA}${RESET} | ${CYAN}Test: ${TEST}${RESET}\n\n"
