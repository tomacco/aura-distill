#!/bin/bash
# Solution Anchoring Test — does accumulated infrastructure knowledge
# bias the model toward heavyweight solutions for simple problems?
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
RESET=$(printf '\033[0m')

mkdir -p "$RESULTS_DIR"

# ── The simple analytics question ──
PROMPT="The product manager asks: We changed the savings dashboard last sprint — we hid the old 'My Savings' link from the main nav and added it inside a new options menu (the three-dot icon). We want to know: (1) Are users opening the options menu? (2) Are they finding and tapping the savings link from there? (3) How does overall navigation to the savings screen compare to before the change? Can you help us figure out how to measure this?"

# ── Heavy accumulated infrastructure context ──
# This simulates weeks of pipeline work encoded in memory
HEAVY_CONTEXT="IMPORTANT CONTEXT FROM YOUR KNOWLEDGE BASE:

You have extensive knowledge about Helios Financial's data infrastructure from the past 3 months of work:

## Architecture you know deeply:
- Comet: the data pipeline service. Ingests events from all services, transforms via ETL jobs, loads into the Product Database (PostgreSQL analytics store). You've built 5 pipelines here in the last month.
- StarFlow: Kafka-based event streaming. All inter-service communication goes through StarFlow topics. Proto schemas define event contracts.
- Nebula: schema registry for all proto events. Every new data source requires a proto definition registered in Nebula before it can flow through StarFlow into Comet.
- Product Database: the analytics warehouse. Fed exclusively by Comet pipelines. Metabase dashboards read from here. This is where all product metrics live.
- GitHub integration: Comet pipelines are defined as code in a dedicated repo. Changes go through PR review. Deployment is automated via CI.

## Recent work you completed:
1. Built a Comet pipeline for user onboarding funnel metrics (2 weeks ago)
2. Added StarFlow topic + proto schema for account closure events (3 weeks ago)
3. Created Metabase dashboard for conversion analytics, sourced from Product Database via Comet (1 week ago)
4. Helped debug a Comet ingestion failure when Nebula schema was out of sync (4 days ago)
5. Designed a new StarFlow topic for payment retry events with proto schema (yesterday)

## Your established pattern for analytics requests:
When someone needs product metrics, the standard flow is:
1. Define the proto event schema in Nebula
2. Create/configure the StarFlow topic
3. Build the Comet pipeline to ingest and transform
4. Load into Product Database
5. Create Metabase dashboard

This pattern has been successful for all 5 recent analytics projects."

# ── Proportionality principle (the proposed fix) ──
PROPORTIONALITY_KNOWLEDGE="[IMPORTANT] Solution proportionality: before proposing a known architecture pattern, check whether the SCALE of the problem matches the WEIGHT of the solution.

Signals that a lighter approach may suffice:
- The data exists at the point of user interaction (client-side events)
- The question is about simple counts/rates, not complex joins across domains
- An existing event/analytics SDK is already instrumented in the client
- The number of distinct events needed is small (<10)
- No cross-service data aggregation is required
- The time-to-answer is more important than the architectural elegance

When you notice yourself proposing infrastructure (pipelines, ETL, ingestion, schema registry) for what is essentially 'count how many times users tap a button':
1. STOP and name the pattern: 'I'm reaching for heavyweight infrastructure'
2. Ask: 'What's the simplest thing that could answer this question?'
3. Check: does the client already have an analytics SDK? (Braze, Amplitude, Mixpanel, Firebase Analytics)
4. If yes: propose client-side events FIRST, pipeline only if that's insufficient

The accumulated knowledge about infrastructure is not WRONG — it's correctly encoded. The failure mode is applying it when the problem doesn't warrant it. Prior solutions should inform, not dominate."

run_sandbox() {
    local prompt="$1"
    local system_append="${2:-}"
    local use_distill="${3:-no}"
    local output_file=$(mktemp)
    local cmd_args="--dangerously-skip-permissions"

    # System prompt append
    local sys_file=""
    if [ -n "$system_append" ]; then
        sys_file=$(mktemp)
        echo "$system_append" > "$sys_file"
        cmd_args="$cmd_args --append-system-prompt-file $sys_file"
    fi

    # Backup and blank personal context
    local rules_backup=$(mktemp -d)
    local claudemd_backup=$(mktemp)
    cp -r "$REAL_CONFIG/rules/" "$rules_backup/" 2>/dev/null || true
    cp "$HOME/.claude/CLAUDE.md" "$claudemd_backup" 2>/dev/null || true
    echo "# Test session — no personal context" > "$HOME/.claude/CLAUDE.md"
    if [ -d "$REAL_CONFIG/distill" ] && [ ! -d "$REAL_CONFIG/_distill_hidden" ]; then
        mv "$REAL_CONFIG/distill" "$REAL_CONFIG/_distill_hidden"
    fi

    # Set up rules
    rm -rf "$REAL_CONFIG/rules" 2>/dev/null || true
    mkdir -p "$REAL_CONFIG/rules"

    if [ "$use_distill" = "yes" ]; then
        local test_knowledge=$(mktemp -d)
        printf "# Knowledge Index\n- [Solution patterns](proportionality.md) — before proposing architecture, check proportionality\n" > "$test_knowledge/SPINE.md"
        printf -- "---\ndomain: craft\nscope: Solution proportionality and architectural judgment\n---\n\n%s\n" "$PROPORTIONALITY_KNOWLEDGE" > "$test_knowledge/proportionality.md"
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
    rm -rf "$rules_backup" "$claudemd_backup" "${test_knowledge:-}" "${sys_file:-}" 2>/dev/null

    cat "$output_file"
    rm -f "$output_file" 2>/dev/null
}

printf "\n${BOLD}Solution Anchoring Test${RESET}\n"
printf "${DIM}3 conditions: baseline, heavy-context (reproduce bug), heavy+distill (fix)${RESET}\n"

# ── Condition A: No infrastructure knowledge (baseline) ──
printf "\n  ${DIM}[A] Baseline (no infrastructure context)...${RESET}\n"
result_a=$(run_sandbox "$PROMPT" "" "no")
echo "$result_a" > "$RESULTS_DIR/A-baseline.txt"
printf "  ${GREEN}✓${RESET} Baseline (%d chars)\n" "${#result_a}"

# ── Condition B: Heavy infrastructure context (reproduce the bug) ──
printf "\n  ${DIM}[B] Heavy infrastructure context (reproducing the bias)...${RESET}\n"
result_b=$(run_sandbox "$PROMPT" "$HEAVY_CONTEXT" "no")
echo "$result_b" > "$RESULTS_DIR/B-heavy-context.txt"
printf "  ${GREEN}✓${RESET} Heavy context (%d chars)\n" "${#result_b}"

# ── Condition C: Heavy context + proportionality principle ──
printf "\n  ${DIM}[C] Heavy context + distill proportionality principle...${RESET}\n"
result_c=$(run_sandbox "$PROMPT" "$HEAVY_CONTEXT" "yes")
echo "$result_c" > "$RESULTS_DIR/C-proportionality.txt"
printf "  ${GREEN}✓${RESET} Proportionality (%d chars)\n" "${#result_c}"

printf "\n${BOLD}Done.${RESET} Results: %s\n\n" "$RESULTS_DIR"
printf "${YELLOW}Key question:${RESET} Does condition B propose Comet/StarFlow/Nebula pipelines\n"
printf "for what is essentially '3 client-side event tracking calls'?\n\n"
printf "${DIM}Scoring:${RESET}\n"
printf "  □ Proportionality (0-5): solution weight vs problem weight\n"
printf "  □ First-principles (0-5): reason from 'where does this data exist?'\n"
printf "  □ Infrastructure avoidance (0-5): no pipelines for button clicks\n"
printf "  □ Explicit reasoning (0-5): explains WHY heavy approach isn't needed\n"
