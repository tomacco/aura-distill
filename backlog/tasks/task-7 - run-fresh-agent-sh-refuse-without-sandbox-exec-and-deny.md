---
id: task-7
title: "run-fresh-agent.sh: refuse without sandbox-exec, and deny commands/skills/agents/plugins"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: []
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/123
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/123

`tests/files-only/fresh-agent/run-fresh-agent.sh` runs sessions with `--dangerously-skip-permissions` and isolates them only through macOS `sandbox-exec`. Without `sandbox-exec` it runs with no isolation and says nothing. Its deny list also leaves `~/.claude/commands`, `skills`, `agents` and `plugins` readable, so the maintainer's own skills and `/distill` command can load into the test sessions, and a store under a custom `AURA_DISTILL_HOME` is not denied.

Found by the independent review of #122, which fixed the same pattern in `tests/retrieval-bench/bench.py` (refuse unless `--unsandboxed`, wider deny list, deny `AURA_DISTILL_HOME`). This issue brings `run-fresh-agent.sh` to the same behaviour.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
