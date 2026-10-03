# Retrieval benchmark pilot data, 2026-10-03

Output of the variance pilot described in `tests/retrieval-bench/PILOT.md` (#77, #62): `manifest.json`, one line per run in `results.jsonl`, the post-review judge verdicts in `rejudged.jsonl`, and `report.json`. Absolute paths are replaced with `<out>` and `~`, and the account email with `<account-email>`. Raw stream traces are not published.

Re-derive the report from a checkout: copy this directory, then `python3 tests/retrieval-bench/bench.py report <copy>`.

The `pass` column in `results.jsonl` is the grading at run time. `report` re-grades with the committed cases and applies `rejudged.jsonl`, which is how PILOT.md reaches 18/18 per cell.
