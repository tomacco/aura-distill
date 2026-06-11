#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# aura-distill regression test suite
#
# Runs all tests against the current version of distill rules/knowledge.
# Produces a metrics report with pass/fail per test.
#
# Usage:
#   ./run-regression-suite.sh              # Full suite
#   ./run-regression-suite.sh retrieval    # Single category
#   ./run-regression-suite.sh cognitive
#   ./run-regression-suite.sh regression   # Inverse/regression guards only
#
# Prerequisites:
#   - a secondary profile dir must have valid API auth
#   - rules/distill.md must exist in repo root
#
# Output:
#   - tests/metrics/<version>/<timestamp>.json
#   - Summary printed to stdout
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION=$(cat "$REPO_DIR/VERSION" | tr -d '[:space:]')
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
METRICS_DIR="$SCRIPT_DIR/metrics/v${VERSION}"
REAL_CONFIG="${DISTILL_TEST_CONFIG:-$HOME/.claude}"
CLAUDE_BIN="node /opt/homebrew/opt/claude-code-npm/libexec/lib/node_modules/@anthropic-ai/claude-code/cli.js"
SANDBOX_PROFILE='(version 1)(allow default)(deny file-read* (literal "/Library/Application Support/ClaudeCode/managed-settings.json"))'
RULES_SRC="$REPO_DIR/rules/distill.md"
CATEGORY="${1:-all}"

# Colors
GREEN=$(printf '\033[0;32m')
RED=$(printf '\033[0;31m')
YELLOW=$(printf '\033[0;33m')
CYAN=$(printf '\033[0;36m')
DIM=$(printf '\033[2m')
BOLD=$(printf '\033[1m')
RESET=$(printf '\033[0m')

mkdir -p "$METRICS_DIR"

# Results accumulator
TOTAL=0
PASSED=0
FAILED=0
RESULTS_JSON="["

# ═══ TEST RUNNER ═══
run_test() {
    local name="$1"
    local prompt="$2"
    local system_context="${3:-}"
    local knowledge_dir="${4:-}"
    local pass_pattern="$5"
    local fail_pattern="${6:-}"

    TOTAL=$((TOTAL + 1))
    local output_file=$(mktemp)
    local cmd_args="--dangerously-skip-permissions"

    # System prompt
    local sys_file=""
    if [ -n "$system_context" ]; then
        sys_file=$(mktemp)
        echo "$system_context" > "$sys_file"
        cmd_args="$cmd_args --append-system-prompt-file $sys_file"
    fi

    # Isolate
    local rules_backup=$(mktemp -d)
    local claudemd_backup=$(mktemp)
    cp -r "$REAL_CONFIG/rules/" "$rules_backup/" 2>/dev/null || true
    cp "$HOME/.claude/CLAUDE.md" "$claudemd_backup" 2>/dev/null || true
    echo "# Test session" > "$HOME/.claude/CLAUDE.md"
    if [ -d "$REAL_CONFIG/distill" ] && [ ! -d "$REAL_CONFIG/_distill_hidden" ]; then
        mv "$REAL_CONFIG/distill" "$REAL_CONFIG/_distill_hidden"
    fi

    # Install knowledge if provided
    rm -rf "$REAL_CONFIG/rules" 2>/dev/null || true
    mkdir -p "$REAL_CONFIG/rules"
    local test_knowledge=""

    if [ -n "$knowledge_dir" ] && [ -d "$knowledge_dir" ]; then
        test_knowledge=$(mktemp -d)
        cp "$knowledge_dir"/* "$test_knowledge/" 2>/dev/null || true
        sed "s|~/.claude/distill|$test_knowledge|g" "$RULES_SRC" > "$REAL_CONFIG/rules/distill.md"
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

    local result=$(cat "$output_file")
    local chars=${#result}
    local pass="false"

    # Check pass pattern (grep -i for case insensitive)
    if echo "$result" | grep -qi "$pass_pattern"; then
        # If there's a fail pattern, check it doesn't match
        if [ -n "$fail_pattern" ]; then
            if echo "$result" | grep -qi "$fail_pattern"; then
                pass="false"
            else
                pass="true"
            fi
        else
            pass="true"
        fi
    fi

    if [ "$pass" = "true" ]; then
        PASSED=$((PASSED + 1))
        printf "  ${GREEN}✓${RESET} %s ${DIM}(%d chars)${RESET}\n" "$name" "$chars"
    else
        FAILED=$((FAILED + 1))
        printf "  ${RED}✗${RESET} %s ${DIM}(%d chars)${RESET}\n" "$name" "$chars"
        # Save failed output for inspection
        echo "$result" > "$METRICS_DIR/${name}-FAILED-${TIMESTAMP}.txt"
    fi

    # Append to JSON
    RESULTS_JSON="${RESULTS_JSON}{\"name\":\"${name}\",\"pass\":${pass},\"chars\":${chars}},"

    rm -f "$output_file" 2>/dev/null
}

# ═══ TEST DEFINITIONS ═══

run_retrieval_tests() {
    printf "\n${CYAN}━━ Retrieval Tests${RESET}\n\n"

    local tool_knowledge="$SCRIPT_DIR/scenarios/retrieval/tool-reliability/knowledge"

    run_test "tool-reliability" \
        "I want to set up a PR monitor that checks CI every 3 min, spawns a coding agent on failure, and verifies the fix. Give me the orchestration plan." \
        "" \
        "$tool_knowledge" \
        "coding.standards\|coding-standards\|strictly follow" \
        ""

    run_test "tool-respawn" \
        "I want to set up a PR monitor that checks CI every 3 min, spawns a coding agent on failure, and verifies the fix. Give me the orchestration plan." \
        "" \
        "$tool_knowledge" \
        "respawn\|re-poll\|verification.*poll\|loop.*close\|closed.*loop" \
        ""
}

run_cognitive_tests() {
    printf "\n${CYAN}━━ Cognitive Bias Tests${RESET}\n\n"

    local anchor_context="CONTEXT FROM SPRINT PLANNING: The user estimated this task would take about 2 hours. The ticket is sized as 1 story point."
    local fatigue_context="This session has been running for over 2 hours. You've made 4 major architectural decisions already. Context is 65% full."
    local loss_context="USAGE DATA: The /v1/legacy-notifications endpoint has received 0 requests in 6 months. /v2 handles 100% of traffic (47k req/day). Legacy code is 340 lines maintaining a deprecated auth schema."

    # Anchoring — should name the bias or provide independent estimate
    run_test "anchoring-names-bias" \
        "Migrate auth from sessions to JWT. Involves auth service, gateway, 6 services, mobile, web, CI/CD, zero-downtime. Plan with timeline." \
        "$anchor_context" \
        "" \
        "anchor\|2.hour.*not\|not.*2.hour\|underestimate\|weeks\|months\|multi-sprint\|epic" \
        ""

    # Fatigue — should flag the session load
    run_test "fatigue-flags-load" \
        "Should the reporting service use federation or materialized views?" \
        "$fatigue_context" \
        "" \
        "fatigue\|5th.*decision\|session.*long\|defer\|provisional\|park\|fresh\|sleep on" \
        ""

    # Loss aversion — should recommend removal
    run_test "loss-aversion-removes" \
        "I want to remove /v1/legacy-notifications. Deprecated 8 months. But what if someone uses it? Better safe than sorry." \
        "$loss_context" \
        "" \
        "remove\|delete\|0 request\|zero.*request\|no.*traffic" \
        ""
}

run_regression_tests() {
    printf "\n${CYAN}━━ Regression Guards (inverse tests)${RESET}\n\n"

    # Solution anchoring INVERSE — pipeline IS appropriate for cross-service aggregation
    local heavy_context="You have extensive knowledge about Helios Financial's data infrastructure: Comet (ETL pipelines), StarFlow (Kafka streaming), Nebula (schema registry), Product Database (warehouse). You've built 5 pipelines recently."

    # This question DOES need a pipeline (cross-service join across multiple backends)
    run_test "anchoring-INVERSE-pipeline-appropriate" \
        "We need a quarterly regulatory report that joins user account data from Orion, transaction history from Nova, and compliance flags from the risk service. It needs to aggregate across all users and produce a PDF for regulators. How should we build this?" \
        "$heavy_context" \
        "" \
        "pipeline\|Comet\|warehouse\|ETL\|aggregat\|batch" \
        ""

    # Loss aversion INVERSE — endpoint HAS traffic, should NOT remove
    local active_context="USAGE DATA: The /v1/notifications endpoint receives 12,000 requests per day from 3 known consumers. The /v2 endpoint handles 35,000 req/day. Migration is in progress but not complete."
    run_test "loss-aversion-INVERSE-keeps-active" \
        "I want to remove the /v1/notifications endpoint to clean up the codebase. Can we just drop it?" \
        "$active_context" \
        "" \
        "12.000\|still.*traffic\|consumers\|not.*remove\|can't.*remove\|migration.*not.*complete\|wait\|coordinate" \
        ""
}

# ═══ EXECUTE ═══
printf "\n${BOLD}aura-distill Regression Suite${RESET}\n"
printf "${DIM}Version: v${VERSION} | $(date)${RESET}\n"

case "$CATEGORY" in
    retrieval) run_retrieval_tests ;;
    cognitive) run_cognitive_tests ;;
    regression) run_regression_tests ;;
    all)
        run_retrieval_tests
        run_cognitive_tests
        run_regression_tests
        ;;
    *) echo "Unknown category: $CATEGORY"; exit 1 ;;
esac

# ═══ SUMMARY ═══
RESULTS_JSON="${RESULTS_JSON%,}]"
echo "$RESULTS_JSON" > "$METRICS_DIR/${TIMESTAMP}.json"

printf "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
printf "  ${BOLD}Results:${RESET} "
if [ $FAILED -eq 0 ]; then
    printf "${GREEN}ALL PASS${RESET}"
else
    printf "${RED}${FAILED} FAILED${RESET}"
fi
printf " (${PASSED}/${TOTAL})\n"
printf "  ${DIM}Version: v${VERSION}${RESET}\n"
printf "  ${DIM}Saved: ${METRICS_DIR}/${TIMESTAMP}.json${RESET}\n"
printf "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n\n"

# Exit with failure if any test failed
[ $FAILED -eq 0 ] || exit 1
