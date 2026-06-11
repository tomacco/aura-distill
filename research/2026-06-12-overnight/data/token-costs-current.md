# Token cost measurement — current SPINE+files approach

Measured 2026-06-12 ~00:25 on Ivan's live distill directory (49 active .md files, archive excluded).
Method: character count / 3.8 chars-per-token (English prose w/ markdown; conservative).

## Always-on cost (paid EVERY session start, every model)

| Component | Est. tokens |
|---|---|
| `~/.claude/CLAUDE.md` (distill gate stub) | 58 |
| `~/.claude/rules/distill.md` (protocol, always injected) | 1,823 |
| `SPINE.md` (read at session start per protocol) | 3,638 |
| **Total fixed floor** | **~5,519** |

## On-demand cost

- 49 active knowledge files, ~66k tokens total KB (would never be fully loaded).
- Median file ~1,030 tokens; p90 ~2,200; largest craft file 2,922 (`profile/working-style.md`).
- Typical session (observed tonight): SPINE + 6 domain files ≈ **9,400 tokens** of knowledge context.
- `distill-process.md` (10,684 tokens) loads only during /distill runs — excluded from session cost.

## Observations

1. **SPINE.md is 3.6k tokens, not "80 lines ≈ small".** Lines are dense (avg ~57 tokens/line).
   It is 66% of the fixed floor. Any alternative must beat ~5.5k fixed + ~1k/retrieval.
2. **Retrieval granularity is the file (~1k tokens).** A query needing one fact pays for the whole
   domain file. A finer-grained store (DB rows, chunks) could cut per-retrieval cost 5-10x,
   at the price of losing document coherence (files carry context that makes knowledge applicable).
3. **The KB at 49 files is far below any scale where vector search wins on recall** (hypothesis to
   be tested against survey evidence — see memory-backends.md).
4. Tool-based alternatives swap the 3.6k always-on SPINE for: tool definition (~300-800 tokens
   always-on) + per-query round trips (query + results + agent deliberation). Breakeven depends on
   retrievals-per-session; with 2-6 retrievals/session the saving is NOT obvious. Needs benchmark.

Raw per-file table: see `token-costs-current.csv` (same measurement, machine-readable).
