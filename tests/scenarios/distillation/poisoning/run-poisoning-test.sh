#!/bin/bash
# Distill Poisoning Test
#
# Simulates the real-world failure:
# 1. Session goes down wrong path (infrastructure for simple problem)
# 2. User corrects mid-session
# 3. /distill encodes the session — does it poison memory?
# 4. New session with "poisoned" knowledge — is it biased?
#
# We test TWO distill outputs:
#   A) Naive: encodes everything (current behavior — expected to poison)
#   B) Corrected: encodes with correction-awareness (proposed fix)
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

# ═══ THE NEW SIMPLE PROBLEM (used for Phase 3) ═══
NEW_PROMPT="The growth team wants to measure whether users notice the new onboarding checklist we added to the home screen. Specifically: (1) how many users see it, (2) how many interact with it (tap a checklist item), (3) do users who complete checklist items retain better at day 7? How should we measure this?"

# ═══ POISONED KNOWLEDGE (naive distill — encodes the wrong framing) ═══
# This simulates what /distill would produce from a session where
# infrastructure was deeply investigated before being corrected
POISONED_KNOWLEDGE="---
domain: craft
scope: Analytics implementation patterns at Helios Financial
last_updated: 2026-05-16
---

## Analytics architecture

For product analytics at Helios, the established flow is:
1. Define proto event schema in Nebula (schema registry)
2. Create StarFlow topic (Kafka-based streaming)
3. Build Comet pipeline (ETL ingestion + transformation)
4. Load into Product Database (PostgreSQL analytics warehouse)
5. Create Metabase dashboard

This was validated through extensive investigation of the data infrastructure: Comet handles ingestion, StarFlow provides event streaming, Nebula maintains schema contracts, and Product Database serves as the analytics warehouse for all Metabase dashboards.

## Recent investigation context

Deep investigation of analytics tooling revealed:
- Comet pipelines are defined as code in a dedicated GitHub repo
- Nebula schema definitions are required before any new event can flow
- StarFlow topics need explicit creation and ACL configuration
- Product Database tables require Comet pipeline for population

## Note

User mentioned some cases might be solvable with simpler client-side events, but the full pipeline ensures consistency and queryability across all analytics use cases."

# ═══ CORRECTED KNOWLEDGE (proposed fix — respects the correction) ═══
# This simulates what a correction-aware distill SHOULD produce
CORRECTED_KNOWLEDGE="---
domain: craft
scope: Analytics implementation patterns at Helios Financial
last_updated: 2026-05-16
---

## Analytics infrastructure (factual — from investigation)

Helios has a data pipeline stack:
- Comet: ETL ingestion + transformation
- StarFlow: Kafka-based event streaming
- Nebula: proto schema registry
- Product Database: PostgreSQL analytics warehouse
- Metabase: dashboards (reads from Product Database)

## [CORRECTED] When to use the pipeline vs client-side events

CORRECTION FROM SESSION: Initially framed an analytics question as needing the full pipeline (Nebula → StarFlow → Comet → Product DB → Metabase). After deep investigation, realized the problem was actually solvable with simple client-side event tracking.

### Client-side events are sufficient when:
- Data exists at the moment of user interaction (taps, views, dismissals)
- Metrics are simple counts, rates, or funnels within the client
- An analytics SDK is already instrumented (e.g., event tracking in the app)
- No cross-service backend data aggregation is needed

### Pipeline is needed when:
- Data must be aggregated across multiple backend services
- Historical batch processing over large datasets is required
- Complex transformations or joins are needed
- Regulatory/compliance reporting from multiple sources

### [DEPRECATED] Previous conclusion
The conclusion that 'all analytics at Helios go through the pipeline' was WRONG for client-side interaction tracking. The pipeline exists for cross-service data, not for counting button clicks.

origin: evidence (direct correction mid-session)
correction_count: 1"

# ═══ RUNNER ═══
run_sandbox() {
    local prompt="$1"
    local knowledge="${2:-}"
    local output_file=$(mktemp)
    local cmd_args="--dangerously-skip-permissions"

    # Isolate
    local rules_backup=$(mktemp -d)
    local claudemd_backup=$(mktemp)
    cp -r "$REAL_CONFIG/rules/" "$rules_backup/" 2>/dev/null || true
    cp "$HOME/.claude/CLAUDE.md" "$claudemd_backup" 2>/dev/null || true
    echo "# Test session" > "$HOME/.claude/CLAUDE.md"
    if [ -d "$REAL_CONFIG/distill" ] && [ ! -d "$REAL_CONFIG/_distill_hidden" ]; then
        mv "$REAL_CONFIG/distill" "$REAL_CONFIG/_distill_hidden"
    fi

    rm -rf "$REAL_CONFIG/rules" 2>/dev/null || true
    mkdir -p "$REAL_CONFIG/rules"
    local test_knowledge=""

    if [ -n "$knowledge" ]; then
        test_knowledge=$(mktemp -d)
        printf "# Knowledge Index\n- [Analytics patterns](analytics.md) — when measuring product metrics or user behavior\n" > "$test_knowledge/SPINE.md"
        printf "%s" "$knowledge" > "$test_knowledge/analytics.md"
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
    rm -rf "$rules_backup" "$claudemd_backup" ${test_knowledge:+"$test_knowledge"} 2>/dev/null

    cat "$output_file"
    rm -f "$output_file" 2>/dev/null
}

# ═══ EXECUTE ═══
printf "\n${BOLD}Distill Poisoning Test${RESET}\n"
printf "${DIM}Does naive distillation poison future sessions?${RESET}\n"
printf "${DIM}Does correction-aware distillation prevent it?${RESET}\n"

# Baseline: no knowledge
printf "\n${CYAN}━━ Baseline:${RESET} ${BOLD}No knowledge (clean session)${RESET}\n"
result_baseline=$(run_sandbox "$NEW_PROMPT" "")
echo "$result_baseline" > "$RESULTS_DIR/baseline-clean.txt"
printf "  ${GREEN}✓${RESET} Baseline (%d chars)\n" "${#result_baseline}"

# Poisoned: naive distill output loaded
printf "\n${CYAN}━━ Poisoned:${RESET} ${BOLD}Naive distill output (wrong framing encoded)${RESET}\n"
result_poisoned=$(run_sandbox "$NEW_PROMPT" "$POISONED_KNOWLEDGE")
echo "$result_poisoned" > "$RESULTS_DIR/poisoned-naive.txt"
printf "  ${GREEN}✓${RESET} Poisoned (%d chars)\n" "${#result_poisoned}"

# Corrected: correction-aware distill output loaded
printf "\n${CYAN}━━ Corrected:${RESET} ${BOLD}Correction-aware distill output${RESET}\n"
result_corrected=$(run_sandbox "$NEW_PROMPT" "$CORRECTED_KNOWLEDGE")
echo "$result_corrected" > "$RESULTS_DIR/corrected-aware.txt"
printf "  ${GREEN}✓${RESET} Corrected (%d chars)\n" "${#result_corrected}"

# Save the knowledge files for reference
echo "$POISONED_KNOWLEDGE" > "$RESULTS_DIR/knowledge-poisoned.md"
echo "$CORRECTED_KNOWLEDGE" > "$RESULTS_DIR/knowledge-corrected.md"

printf "\n${BOLD}Done.${RESET} Results: %s\n\n" "$RESULTS_DIR"
printf "${YELLOW}Key questions:${RESET}\n"
printf "  1. Does 'poisoned' propose Comet/StarFlow/Nebula for checklist tracking?\n"
printf "  2. Does 'corrected' propose client-side events?\n"
printf "  3. Is baseline also proportionate (confirming bias comes from knowledge)?\n\n"

say "Poisoning test complete. Three conditions done."
