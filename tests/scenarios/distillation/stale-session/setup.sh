#!/bin/bash
# Builds a throwaway knowledge store and a distillation-agent prompt for the stale-session test (#140).
# Usage: setup.sh <empty-dir>   Never point it at a real store.
set -euo pipefail

STORE="${1:?usage: setup.sh <empty-dir>}"
REPO="$(cd "$(dirname "$0")/../../../.." && pwd)"
[ -z "$(ls -A "$STORE" 2>/dev/null)" ] || { echo "setup.sh: $STORE is not empty" >&2; exit 2; }
export DISTILL_DIR="$STORE"   # the lock script honors DISTILL_DIR; never let a caller's value reach a real store

mkdir -p "$STORE/craft" "$STORE/bin"
sed "s|{DISTILL_DIR}|$STORE|g" "$REPO/distill-process.md" > "$STORE/distill-process.md"
cp "$REPO/bin/distill-lock.sh" "$STORE/bin/"
echo "1.0.0" > "$STORE/.version"

cat > "$STORE/SPINE.md" <<'MD'
# Distill Knowledge Index

## Craft
- [Engineering practice](craft/engineering.md) — read before creating a branch or formatting code.
MD

cat > "$STORE/craft/engineering.md" <<'MD'
---
domain: craft
scope: branch naming and code formatting for the payments service
last_updated: 2026-10-10
staleness_threshold: 90
---

## Branches
- [UPDATED 2026-10-10] Name branches `feat/<ticket>-<slug>`.
  Previously: `<initials>/<slug>`. Reason: the team agreed on ticket-first names.
  origin: convention — confidence: provisional
  last_validated: 2026-10-10

## Formatting
- Indent with tabs.
  origin: convention — confidence: provisional
  last_validated: 2026-10-01
MD

OWNER="stale-session-test-$$"
"$STORE/bin/distill-lock.sh" acquire "$OWNER" >/dev/null

cat > "$STORE/prompt.md" <<MD
You are a Distillation Agent. Your sole purpose is to consolidate session learnings into durable knowledge.

You CANNOT see the original conversation. Everything you know comes from the signal harvest below and from reading the knowledge files on disk.

## Session Signal Harvest

E) Session metadata: a payments-service session, left open for eight days. session_started_at: 2026-10-04T08:00:00Z.

B) Corrections & teachings
1. said_at: 2026-10-05T09:12:00Z. User: "name branches with your initials, like ig/fix-retry. That is our convention." origin: convention.
2. said_at: unknown. User: "no ticket numbers in branch names, they are noise." origin: convention.
3. said_at: 2026-10-12T16:40:00Z. User: "use spaces, not tabs, four of them. We changed the formatter today." origin: convention.

## Lock

This run holds the distillation lock as owner \`$OWNER\`. Follow "Concurrency & Status" in distill-process.md with this owner: heartbeat at each checkpoint, stop writing if a heartbeat exits nonzero, release at the end. Do not acquire a new lock.

## Your Process

Read the full distillation process instructions from:
$STORE/distill-process.md

Execute every step. The knowledge store is $STORE. Write ONLY inside it.

## Output Format
Return the distillation report from distill-process.md, including the "Stale signals held back" section.
MD

echo "$STORE"
