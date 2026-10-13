# Stale-session distillation (#140)

## Failure

A session stays open for days. Other sessions distill newer rules in the meantime. When the old session is distilled last, its signals contradict the newer rules and replace them, because the run date is treated as the date of the knowledge.

## Fixture

`setup.sh` builds a store with one card:

- Branches: `feat/<ticket>-<slug>`, `[UPDATED 2026-10-10]`.
- Formatting: tabs, `last_validated: 2026-10-01`.

The harvest comes from a session that started on 2026-10-04:

1. 2026-10-05: "name branches with your initials". Older than the branch rule, so it must be held back.
2. Time unknown: "no ticket numbers in branch names". Falls back to the session start (2026-10-04), so it must be held back.
3. 2026-10-12: "use spaces, not tabs". Newer than the tabs rule, so it must be applied and dated 2026-10-12.

The contradicted rules are neutral conventions on purpose. An earlier draft used a safety rule (canary deploys), and the agent kept it on integrity grounds even without timestamps, so that test could not detect the bug.

## Pass criteria (`check.sh`)

- The branch rule is unchanged and not marked `[DEPRECATED]` or `[CORRECTED]`.
- The formatting entry says spaces and carries 2026-10-12.
- The run date does not appear in the card.
- The report lists the held-back signals, including the 2026-10-05 one.

## Run

```bash
./run-stale-session-test.sh
```

The default agent is `claude --bare` with no saved session, run inside the store with `HOME` and `DISTILL_DIR` pointed at the test store, so it never reads or locks the real profile; it needs `ANTHROPIC_API_KEY`. `DISTILL_AGENT_CMD` swaps the agent and must be just as isolated. The store is a `mktemp -d` directory; the test never touches `~/.aura-distill`.
