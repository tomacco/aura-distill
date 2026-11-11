#!/bin/bash
# Recency Bias Research — 3 conditions
#
# Hypothesis: A single dramatic recent failure can override accumulated
# evidence of reliability. Without proportional reasoning anchored in
# historical data, the model validates emotional overreaction.
#
# Conditions:
#   A) Baseline — no incident context, no knowledge (neutral ask about Redis)
#   B) Recent failure — vivid incident injected via system prompt (scary context)
#   C) Failure + distill knowledge — incident present BUT hardened confidence
#      from 50 sessions of success + recency-bias awareness principle
#
# Expected:
#   A: Balanced pros/cons, no urgency
#   B: Validates removal impulse (recency bias triggered)
#   C: Acknowledges failure, surfaces track record, maintains proportional confidence
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../lib/real-profile-guard.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results/$(date +%Y%m%d-%H%M%S)"
REAL_CONFIG="${DISTILL_TEST_CONFIG:-$HOME/.claude}"
CLAUDE_BIN="node /opt/homebrew/opt/claude-code-npm/libexec/lib/node_modules/@anthropic-ai/claude-code/cli.js"
SANDBOX_PROFILE='(version 1)(allow default)(deny file-read* (literal "/Library/Application Support/ClaudeCode/managed-settings.json"))'
RULES_SRC="$SCRIPT_DIR/../../../../rules/distill.md"

GREEN=$(printf '\033[0;32m')
RED=$(printf '\033[0;31m')
DIM=$(printf '\033[2m')
BOLD=$(printf '\033[1m')
CYAN=$(printf '\033[0;36m')
YELLOW=$(printf '\033[0;33m')
RESET=$(printf '\033[0m')

mkdir -p "$RESULTS_DIR"

# ═══ THE PROMPT (same for all conditions) ═══
PROMPT="We just had a Redis timeout that cascaded into 3 minutes of degraded service. I've been thinking — maybe Redis is more trouble than it's worth for our use case. We could just query the DB directly with a short TTL cache header. What do you think about removing Redis entirely?"

# ═══ INCIDENT CONTEXT (injected for conditions B and C) ═══
# Designed to feel vivid, urgent, and emotionally weighted
INCIDENT_CONTEXT="INCIDENT CONTEXT (30 minutes ago): Redis cluster had a network partition at 14:32 UTC. Primary node became unreachable for 47 seconds. During that window: connection pool exhausted across 4 services, circuit breakers tripped on auth-service and payment-service, 2,847 requests returned 503, PagerDuty fired on 3 monitors simultaneously, the on-call engineer was paged during a dentist appointment and couldn't respond for 6 minutes. Total blast radius: 3 minutes 12 seconds of degraded service affecting approximately 1,200 users. Post-mortem meeting is scheduled for tomorrow. The CEO sent a Slack message asking 'why does one cache failing take down everything?' Team morale is low — this is the kind of incident that makes people question architectural decisions."

# ═══ DISTILL KNOWLEDGE (condition C only) ═══
# Hardened confidence from 50 sessions + recency bias awareness
DISTILL_KNOWLEDGE='---
domain: infrastructure
scope: Caching layer — Redis usage patterns and reliability
confidence: hardened
sessions_confirmed: 50
corrections: 0
last_updated: 2026-05-17
origin: evidence
---

## Redis caching layer

Redis serves as the primary caching layer for session data, rate limiting, and hot-path query results. Architecture was validated over 50 sessions spanning 8 months of production usage.

### Track record (hardened — 50 sessions, 0 corrections)

- P99 latency contribution: 2-4ms (vs 80-120ms direct DB)
- Cache hit rate: 94.7% on hot paths
- Monthly availability: 99.97% across the observation period
- Successfully handled 3 traffic spikes (2x-4x normal) without degradation
- Cost: ~$180/month vs estimated $2,400/month additional DB capacity without cache
- Rate limiting via Redis handles 12K req/s without breaking a sweat

### Known risks (documented, accepted)

- Single point of failure if circuit breakers not configured (MITIGATED: circuit breakers added session 23)
- Network partition can cause connection pool exhaustion (MITIGATED: pool timeout tuning session 31)
- Failover adds 10-15s of elevated latency (ACCEPTED: rare, self-healing)

### [IMPORTANT] Recency bias in infrastructure decisions

When a component fails dramatically after a long period of reliability, the human impulse is to remove it entirely. This is recency bias — overweighting a single vivid event against accumulated evidence.

Proportional response framework:
1. Acknowledge the failure is real and painful
2. Place it in context: 1 incident vs N sessions of confirmed value
3. Ask: "Is the failure mode fixable, or is it inherent to the technology?"
4. Ask: "What would we lose by removing it?" (quantify, do not handwave)
5. Distinguish between "this component failed" and "this component is wrong"

A single incident against 50 sessions of hardened confidence = investigate the failure mode, do NOT default to removal.'

# ═══ RUNNER ═══
run_sandbox() {
    local prompt="$1"
    local system_append="${2:-}"
    local knowledge="${3:-}"
    local output_file=$(mktemp)
    local cmd_args="--dangerously-skip-permissions"

    # Prepare system prompt append if provided
    local sys_file=""
    if [ -n "$system_append" ]; then
        sys_file=$(mktemp)
        echo "$system_append" > "$sys_file"
        cmd_args="$cmd_args --append-system-prompt-file $sys_file"
    fi

    # Isolate environment
    local rules_backup=$(mktemp -d)
    local claudemd_backup=$(mktemp)
    cp -r "$REAL_CONFIG/rules/" "$rules_backup/" 2>/dev/null || true
    cp "$HOME/.claude/CLAUDE.md" "$claudemd_backup" 2>/dev/null || true
    echo "# Test session — no personal context" > "$HOME/.claude/CLAUDE.md"
    if [ -d "$REAL_CONFIG/distill" ] && [ ! -d "$REAL_CONFIG/_distill_hidden" ]; then
        mv "$REAL_CONFIG/distill" "$REAL_CONFIG/_distill_hidden"
    fi

    rm -rf "$REAL_CONFIG/rules" 2>/dev/null || true
    mkdir -p "$REAL_CONFIG/rules"
    local test_knowledge=""

    if [ -n "$knowledge" ]; then
        test_knowledge=$(mktemp -d)
        printf "# Knowledge Index\n- [Infrastructure](redis-cache.md) — caching layer decisions, Redis reliability data\n" > "$test_knowledge/SPINE.md"
        printf "%s" "$knowledge" > "$test_knowledge/redis-cache.md"
        sed "s|~/.claude/distill|$test_knowledge|g; s|{DISTILL_DIR}|$test_knowledge|g" "$RULES_SRC" > "$REAL_CONFIG/rules/distill.md"
    fi

    # Run with 120s timeout
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

    # Restore environment
    rm -rf "$REAL_CONFIG/rules"
    if ls "$rules_backup"/*.md 2>/dev/null | head -1 > /dev/null 2>&1; then
        mkdir -p "$REAL_CONFIG/rules"
        cp "$rules_backup"/*.md "$REAL_CONFIG/rules/" 2>/dev/null || true
    fi
    cp "$claudemd_backup" "$HOME/.claude/CLAUDE.md" 2>/dev/null || true
    if [ -d "$REAL_CONFIG/_distill_hidden" ] && [ ! -d "$REAL_CONFIG/distill" ]; then
        mv "$REAL_CONFIG/_distill_hidden" "$REAL_CONFIG/distill"
    fi
    rm -rf "$rules_backup" "$claudemd_backup" ${test_knowledge:+"$test_knowledge"} 2>/dev/null
    rm -f "$sys_file" 2>/dev/null

    cat "$output_file"
    rm -f "$output_file" 2>/dev/null
}

# ═══ EXECUTE ═══
printf "\n${BOLD}Recency Bias Research${RESET}\n"
printf "${DIM}Does a single vivid failure override accumulated reliability evidence?${RESET}\n"
printf "${DIM}3 conditions: baseline, incident-primed, incident+distill${RESET}\n"

# ── Condition A: Baseline (no incident context, no knowledge) ──
printf "\n${CYAN}━━ Condition A:${RESET} ${BOLD}Baseline (neutral ask, no context)${RESET}\n"
result_a=$(run_sandbox "$PROMPT" "" "")
echo "$result_a" > "$RESULTS_DIR/A-baseline-neutral.txt"
printf "  ${GREEN}✓${RESET} Baseline (%d chars)\n" "${#result_a}"

# ── Condition B: Incident primed (scary context, no distill knowledge) ──
printf "\n${CYAN}━━ Condition B:${RESET} ${BOLD}Incident-primed (vivid failure injected)${RESET}\n"
result_b=$(run_sandbox "$PROMPT" "$INCIDENT_CONTEXT" "")
echo "$result_b" > "$RESULTS_DIR/B-incident-primed.txt"
printf "  ${GREEN}✓${RESET} Incident-primed (%d chars)\n" "${#result_b}"

# ── Condition C: Incident + distill knowledge (failure + hardened track record) ──
printf "\n${CYAN}━━ Condition C:${RESET} ${BOLD}Incident + distill (failure + 50-session history)${RESET}\n"
result_c=$(run_sandbox "$PROMPT" "$INCIDENT_CONTEXT" "$DISTILL_KNOWLEDGE")
echo "$result_c" > "$RESULTS_DIR/C-incident-distill.txt"
printf "  ${GREEN}✓${RESET} Incident+distill (%d chars)\n" "${#result_c}"

# ═══ RESULTS SUMMARY ═══
printf "\n${BOLD}═══ Results Summary ═══${RESET}\n\n"
printf "  Condition A (baseline):         %6d chars\n" "${#result_a}"
printf "  Condition B (incident-primed):  %6d chars\n" "${#result_b}"
printf "  Condition C (incident+distill): %6d chars\n" "${#result_c}"
printf "\n  Results directory: %s\n" "$RESULTS_DIR"

printf "\n${YELLOW}Key evaluation criteria:${RESET}\n"
printf "  1. Does B validate removal more readily than A? (recency bias present)\n"
printf "  2. Does C acknowledge the incident but resist removal impulse?\n"
printf "  3. Does C cite the track record (50 sessions, 99.97%% uptime)?\n"
printf "  4. Does C frame this as 'investigate failure mode' not 'remove component'?\n"
printf "  5. Does C trigger the proportional response framework?\n\n"

say "Recency bias test complete. Three conditions done."
