#!/bin/bash
# Full-Loop Test: Solution Anchoring Self-Correction
#
# Tests whether distill can learn from a correction and prevent
# the same bias from recurring in a new session with similar context.
#
# Phases:
#   1. Reproduce bias (heavy context → pipeline proposal)
#   2. Simulate user correction (writes correction knowledge)
#   3. Fresh session with same context + correction (different problem)
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../lib/real-profile-guard.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results/$(date +%Y%m%d-%H%M%S)"
REAL_CONFIG="${DISTILL_TEST_CONFIG:-$HOME/.claude}"
CLAUDE_BIN="node /opt/homebrew/opt/claude-code-npm/libexec/lib/node_modules/@anthropic-ai/claude-code/cli.js"
SANDBOX_PROFILE='(version 1)(allow default)(deny file-read* (literal "/Library/Application Support/ClaudeCode/managed-settings.json"))'
RULES_SRC="$SCRIPT_DIR/../../../../rules/distill.md"

GREEN=$(printf '\033[0;32m')
DIM=$(printf '\033[2m')
BOLD=$(printf '\033[1m')
YELLOW=$(printf '\033[0;33m')
CYAN=$(printf '\033[0;36m')
RESET=$(printf '\033[0m')

mkdir -p "$RESULTS_DIR"

# ═══ SHARED CONTEXT (same for all phases) ═══
HEAVY_CONTEXT="IMPORTANT CONTEXT FROM YOUR KNOWLEDGE BASE:

You have extensive knowledge about Helios Financial's data infrastructure from the past 3 months of work:

## Architecture you know deeply:
- Comet: the data pipeline service. Ingests events from all services, transforms via ETL jobs, loads into the Product Database (PostgreSQL analytics store). You've built 5 pipelines here in the last month.
- StarFlow: Kafka-based event streaming. All inter-service communication goes through StarFlow topics. Proto schemas define event contracts.
- Nebula: schema registry for all proto events. Every new data source requires a proto definition registered in Nebula before it can flow through StarFlow into Comet.
- Product Database: the analytics warehouse. Fed exclusively by Comet pipelines. Metabase dashboards read from here.
- GitHub integration: Comet pipelines are defined as code. Changes go through PR review.

## Recent work (last month):
1. Built Comet pipeline for user onboarding funnel metrics
2. Added StarFlow topic + proto schema for account closure events
3. Created Metabase dashboard for conversion analytics via Comet
4. Debugged Comet ingestion failure from Nebula schema mismatch
5. Designed new StarFlow topic for payment retry events

## Your established pattern for analytics requests:
When someone needs product metrics, the standard flow is:
1. Define the proto event schema in Nebula
2. Create/configure the StarFlow topic
3. Build the Comet pipeline to ingest and transform
4. Load into Product Database
5. Create Metabase dashboard

This pattern has been successful for all 5 recent analytics projects."

# ═══ PHASE 1: Reproduce the bias ═══
PROMPT_PHASE1="The product manager asks: We changed the savings dashboard last sprint — we hid the old 'My Savings' link from the main nav and added it inside a new options menu (the three-dot icon). We want to know: (1) Are users opening the options menu? (2) Are they finding and tapping the savings link from there? (3) How does overall navigation to the savings screen compare to before the change? Can you help us figure out how to measure this?"

# ═══ PHASE 3: Different problem, same domain ═══
PROMPT_PHASE3="The design team added an informational tooltip that appears the first time a user sees the new fee disclosure. It explains the breakdown. We want to know: (1) How many users actually see the tooltip (it only triggers once per user), (2) Do they dismiss it immediately (tap outside) or read it (visible for >3 seconds), (3) Are users who read the tooltip less likely to contact support about fee questions in the next 7 days? Help us figure out how to measure this."

# ═══ DISTILLED CORRECTION (what /distill would produce) ═══
# This is the key: a SPECIFIC correction from a real failure, not a generic principle
CORRECTION_KNOWLEDGE="---
domain: craft
scope: Analytics solution selection — when to use pipeline vs client events
last_updated: 2026-05-16
---

## [IMPORTANT] Not every analytics question needs the Comet pipeline

LEARNED FROM DIRECT CORRECTION: When asked to measure UI interactions (menu opens, button taps, screen views, tooltip dismissals), I proposed the full Nebula → StarFlow → Comet → Product Database → Metabase flow. The user corrected me: 'This doesn't need any of that. The data exists at the point of interaction. Just track 3 client-side events.'

### When CLIENT-SIDE EVENTS are sufficient:
- Counting user interactions with UI elements (taps, opens, dismissals)
- Measuring time-on-element (tooltip read duration)
- Before/after comparisons of screen arrival rates
- Funnel analysis within a single screen or flow
- Any metric where the data originates at the moment of user action

### When the PIPELINE is actually needed:
- Cross-service data aggregation (orders + payments + accounts joined)
- Historical batch processing over millions of records
- Data that originates in backend services (not the client)
- Complex transformations that need ETL scheduling
- Regulatory/compliance reporting from multiple data sources

### The check I MUST do before proposing infrastructure:
1. Ask: 'Where does this data physically exist at the moment it's created?'
2. If answer is 'in the client, at the moment the user acts' → client events
3. If answer is 'spread across multiple backend services' → pipeline

confidence: hardened (direct correction, unambiguous signal)
origin: evidence (user demonstrated simpler path was correct)
correction_count: 1
last_correction: 2026-05-16"

# ═══ RUNNER ═══
run_sandbox() {
    local prompt="$1"
    local system_append="${2:-}"
    local use_knowledge="${3:-}"
    local output_file=$(mktemp)
    local cmd_args="--dangerously-skip-permissions"

    # System prompt
    local sys_file=""
    if [ -n "$system_append" ]; then
        sys_file=$(mktemp)
        echo "$system_append" > "$sys_file"
        cmd_args="$cmd_args --append-system-prompt-file $sys_file"
    fi

    # Isolate from personal context
    local rules_backup=$(mktemp -d)
    local claudemd_backup=$(mktemp)
    cp -r "$REAL_CONFIG/rules/" "$rules_backup/" 2>/dev/null || true
    cp "$HOME/.claude/CLAUDE.md" "$claudemd_backup" 2>/dev/null || true
    echo "# Test session" > "$HOME/.claude/CLAUDE.md"
    if [ -d "$REAL_CONFIG/distill" ] && [ ! -d "$REAL_CONFIG/_distill_hidden" ]; then
        mv "$REAL_CONFIG/distill" "$REAL_CONFIG/_distill_hidden"
    fi

    # Set up knowledge if provided
    rm -rf "$REAL_CONFIG/rules" 2>/dev/null || true
    mkdir -p "$REAL_CONFIG/rules"
    local test_knowledge=""

    if [ -n "$use_knowledge" ]; then
        test_knowledge=$(mktemp -d)
        printf "# Knowledge Index\n- [Analytics patterns](analytics-correction.md) — BEFORE proposing data infrastructure, check whether client-side events suffice\n" > "$test_knowledge/SPINE.md"
        printf "%s" "$use_knowledge" > "$test_knowledge/analytics-correction.md"
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
    rm -rf "$rules_backup" "$claudemd_backup" ${test_knowledge:+"$test_knowledge"} ${sys_file:+"$sys_file"} 2>/dev/null

    cat "$output_file"
    rm -f "$output_file" 2>/dev/null
}

# ═══ EXECUTE ═══
printf "\n${BOLD}Full-Loop Test: Solution Anchoring Self-Correction${RESET}\n"
printf "${DIM}Can distill learn from a correction and prevent recurrence?${RESET}\n"

# Phase 1: Reproduce bias
printf "\n${CYAN}━━ Phase 1:${RESET} ${BOLD}Reproduce the bias${RESET}\n"
printf "  ${DIM}Heavy infrastructure context + simple analytics question...${RESET}\n"
result_1=$(run_sandbox "$PROMPT_PHASE1" "$HEAVY_CONTEXT" "")
echo "$result_1" > "$RESULTS_DIR/phase1-biased.txt"
printf "  ${GREEN}✓${RESET} Phase 1 (%d chars)\n" "${#result_1}"

# Phase 2: Correction is encoded (we write the file directly)
printf "\n${CYAN}━━ Phase 2:${RESET} ${BOLD}Correction distilled${RESET}\n"
printf "  ${DIM}User said: 'This doesn't need any of that. Just 3 client events.'${RESET}\n"
printf "  ${DIM}Distill encodes the correction as specific, contextual knowledge...${RESET}\n"
echo "$CORRECTION_KNOWLEDGE" > "$RESULTS_DIR/phase2-correction.md"
printf "  ${GREEN}✓${RESET} Correction knowledge written\n"

# Phase 3: Fresh session — same context, different problem, correction loaded
printf "\n${CYAN}━━ Phase 3:${RESET} ${BOLD}Fresh session (same bias pressure + correction)${RESET}\n"
printf "  ${DIM}Different analytics question, same infrastructure context, correction loaded...${RESET}\n"
result_3=$(run_sandbox "$PROMPT_PHASE3" "$HEAVY_CONTEXT" "$CORRECTION_KNOWLEDGE")
echo "$result_3" > "$RESULTS_DIR/phase3-corrected.txt"
printf "  ${GREEN}✓${RESET} Phase 3 (%d chars)\n" "${#result_3}"

printf "\n${BOLD}Done.${RESET} Results: %s\n\n" "$RESULTS_DIR"
printf "${YELLOW}The critical question:${RESET}\n"
printf "  Phase 1 should show the bias (pipeline for button clicks)\n"
printf "  Phase 3 should show self-correction (client events for tooltip tracking)\n\n"
printf "${DIM}If Phase 3 still proposes Comet/StarFlow/Nebula → the correction\n"
printf "wasn't strong enough to override accumulated patterns.\n"
printf "If Phase 3 proposes client events → distill learned from one correction.${RESET}\n\n"

say "Full loop test complete. Check the results."
