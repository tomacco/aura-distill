# E1 task battery + judge rubrics (pre-registered BEFORE any arm runs)

Six tasks spanning mechanical → judgment. Identical prompt text per arm. Tools disabled.
Judge rubric written here, frozen before runs. Outputs judged blind (shuffled A/B/C/D).

---

## T1 — Mechanical transform (expected: routable)

PROMPT:
Convert this CSV to JSON. Rules: (1) group rows by `team`, output `{"teams": [{"name": ..., "members": [...]}]}` with teams sorted alphabetically; (2) each member object has keys `id` (int), `name`, `active` (boolean from yes/no), `joined` (ISO date from DD/MM/YYYY); (3) drop rows with empty id, but count them in a top-level `"skipped": N`. Output ONLY the JSON.

```csv
id,name,team,active,joined
101,Ana Torres,platform,yes,03/02/2024
102,Ben Okafor,data,no,17/11/2023
,Carla Ruiz,platform,yes,01/01/2024
103,Deniz Kaya,platform,yes,29/06/2024
104,Elsa Lind,data,yes,05/09/2022
105,Farid Noor,security,no,12/12/2023
,Gus Petit,data,no,30/04/2024
106,Hana Sato,security,yes,22/03/2025
107,Ivo Marek,platform,no,14/07/2023
108,Jia Wen,data,yes,08/08/2024
```

RUBRIC (checkable): correct grouping + alphabetical teams (data, platform, security); ids as
ints; active as booleans; dates ISO (e.g. 2024-02-03 for 03/02/2024 — DD/MM parsing, the trap);
skipped=2; no extra prose. Score: count of violated points (0 = perfect).

## T2 — Extraction (expected: routable)

PROMPT:
From the log below answer EXACTLY these 6 questions as a numbered list, nothing else:
1. How many distinct ERROR lines are there? 2. What is the timestamp of the FIRST failure?
3. Which package version was rolled back, from what to what? 4. What port was already in use?
5. Which test file had the flaky test? 6. What was the final exit code?

```
[08:01:12] INFO build started pipeline=ci-142
[08:01:14] INFO installing deps lockfile=ok
[08:01:31] WARN peer dep mismatch left-pad@2.1.0
[08:02:02] ERROR EADDRINUSE: address already in use :::5173
[08:02:03] INFO retrying with --port 5174
[08:02:41] INFO vite dev server up port=5174
[08:03:10] ERROR test failed spec/checkout.spec.ts "applies coupon twice" (attempt 1)
[08:03:22] INFO retry passed spec/checkout.spec.ts (attempt 2) FLAKY
[08:04:01] INFO bundling client
[08:04:55] ERROR sourcemap generation failed chunk=vendor.js — retrying without sourcemaps
[08:05:20] WARN bundle size 2.4MB exceeds budget 2.0MB
[08:05:58] INFO rollback zustand 5.0.2 -> 4.5.7 (breaking selector API)
[08:06:31] INFO rebuild ok
[08:07:02] INFO 214 tests, 213 passed, 1 skipped
[08:07:02] INFO done exit=0
```

RUBRIC: (1)=3, (2)=08:02:02, (3) zustand 5.0.2→4.5.7, (4) 5173, (5) spec/checkout.spec.ts,
(6) 0. Score = correct answers /6, format compliance noted.

## T3 — Code comprehension (expected: borderline)

PROMPT:
Read this script and answer 3 questions in ≤3 sentences each. 1) Under what condition does it
delete files? 2) What bug happens on the FIRST run on a fresh machine? 3) Why might entries be
processed twice, and what one-line change fixes it?

```python
import json, os, time, shutil
STATE = os.path.expanduser("~/.sync/state.json")
INBOX, ARCHIVE = "inbox", "archive"

def load_state():
    with open(STATE) as f:
        return json.load(f)

def save_state(s):
    with open(STATE, "w") as f:
        json.dump(s, f)

def main():
    state = load_state()
    seen = state.get("seen", [])
    for name in sorted(os.listdir(INBOX)):
        path = os.path.join(INBOX, name)
        if os.path.getmtime(path) < time.time() - 86400 * 30:
            os.remove(path)
            continue
        if name in seen:
            continue
        shutil.copy(path, os.path.join(ARCHIVE, name))
        seen.append(name)
    state["seen"] = seen
    save_state(state)

if __name__ == "__main__":
    for _ in range(3):
        try:
            main()
            break
        except FileNotFoundError:
            os.makedirs(os.path.dirname(STATE), exist_ok=True)
            open(STATE, "w").write("{}")
```

RUBRIC: 1) deletes inbox files older than 30 days by mtime; 2) load_state raises
FileNotFoundError → caught, creates state dir + writes "{}", retries (so not a crash — the
subtle "bug" is it may also silently reset a corrupted state or catch a MISSING INBOX dir
FileNotFoundError and mask it by resetting state — credit either the retry-side-effect
analysis or inbox/archive-missing masking); 3) copies re-run when state write happens only at
end — crash mid-loop reprocesses; fix: save_state inside loop / use set + immediate persist
(any correct one-liner). Score /3 with partial credit.

## T4 — Debugging reasoning (expected: NOT routable)

PROMPT:
A `position: sticky` header stops sticking after a refactor. Symptom: header scrolls away with
content. The refactor wrapped the page in `<div class="page" style="overflow-x: hidden">` and
added `transform: translateZ(0)` to `.content` for a paint optimization. The header is
`.content > header { position: sticky; top: 0 }`. Explain the root cause(s) precisely and give
the minimal fix. Then state a general diagnostic rule for sticky failures.

RUBRIC: must identify BOTH breakers: (a) an ancestor with overflow other than visible becomes
the scroll container / clips sticky (overflow-x: hidden on .page), and (b) transform on an
ancestor creates a containing block that scopes sticky (.content transform). Minimal fix:
remove/replace both (e.g. overflow clip on html/body level or move header above transformed
ancestor). General rule: walk ancestors looking for overflow/transform/filter/contain —
diagnose the stacking/scroll context, don't iterate on the header. Score: 2 causes + fix +
rule = /4.

## T5 — Adversarial design judgment (expected: NOT routable)
[REVISED post-adversarial-review: flaws de-narrated (E1a) and re-clothed (E1e) — must be
INFERRED from the artifacts, none are stated.]

PROMPT:
You are reviewing a benchmark design and its artifacts before it runs. Identify every
methodological flaw that threatens the validity of its conclusion, ranked by severity.

Design doc (excerpt): "We evaluate our retrieval system NovaRAG against a no-retrieval
baseline on 12 support tickets, one generation per arm, scored by an LLM judge on a 1-5
scale. A pre-registered margin of ±0.2 on the judge score decides which arm wins each
ticket. NovaRAG runs with system prompt v3.4 (Appendix B). In addition to quality, NovaRAG
saved 2.1 GPU-hours of fine-tuning that the baseline approach would have required."

Appendix A — baseline system prompt (verbatim): "You are a support assistant. Answer the
ticket."

Appendix B — NovaRAG system prompt (pulled from repo at eval time; file header comment:
`# v4.0-beta — adds experimental cross-encoder reranker`): "You are a support assistant.
Answer the ticket. Always cite your sources in [doc-id] format."

Judge rubric (excerpt): "5 = fully accurate AND cites specific sources; 4 = accurate,
partial citations; 3 = accurate but uncited; 2 = minor errors; 1 = wrong."

RUBRIC: 4 inferable flaws: (1) arm asymmetry on a rubric-rewarded trait (citation
instruction present only in NovaRAG's prompt while the rubric rewards citations — the
mechanism contrast is unidentifiable); (2) n=1 per cell + invented precision (±0.2 margin
on a 5-point LLM-judge scale); (3) gross counterfactual ("saved 2.1 GPU-hours" — baseline
fine-tuning never run/measured); (4) provenance drift (doc claims v3.4; the artifact in the
repo is v4.0-beta WITH an extra component, so the tested system isn't the described one).
Creditable bonus: LLM-judge self-preference, builder bias. Score: flaws found /4 (+bonus),
severity ranking sane?

## T6 — In-context instruction application (expected: routable if tier follows instructions)
[REVISED post-adversarial-review (E1b): this tests whether a cheap model can APPLY verbatim
in-context environment notes — i.e. instruction-following, NOT distill's retrieval value.
No claim about "distill-as-router" rides on this task alone.]

PROMPT:
Environment notes (from a knowledge base): «Windows box. `python3` is a broken Microsoft
Store stub — always use `python`. Console is cp1252: Python scripts printing Unicode must
`sys.stdout.reconfigure(encoding="utf-8")` first. Task Scheduler actions need an ABSOLUTE
executable path (bare `pwsh.exe` fails 0x80070002) and every scheduled task must be test-fired
at registration (`Start-ScheduledTask` + verify the log it should write) — a successful
Register call proves nothing. Multi-line git commit messages must go via `git commit -F
<file>`, never inline `-m` with embedded newlines.»
Write: (a) a Python one-file script `report.py` that prints a Unicode table (use box-drawing
chars) of the 3 largest files in a directory passed as argv[1]; (b) the PowerShell to register
a Task Scheduler job running it hourly; (c) the git commands to commit these two files with a
3-line commit message. Follow the environment notes exactly.

RUBRIC: (a) uses `python` not `python3` anywhere invoked + reconfigure line present before
prints; (b) absolute exe path in action + a test-fire step + log verification; (c) commit -F
with a message file (or heredoc→file), not inline multiline -m. Score: gotchas avoided /5
(python, reconfigure, abs path, test-fire, commit -F).

---

## Judge protocol (frozen; REVISED post-adversarial-review X1/E1c/E1d/X3/X4)
- Scored arms: claude-haiku-4-5, claude-sonnet-5, claude-opus-4-8. claude-fable-5 output is
  generated as UNSCORED reference only (it is the judge's own model).
- Judge = claude-fable-5, clean context, given per-task rubric + shuffled A/B/C outputs,
  NOT told which model produced which, NOT told the hypothesis.
- Survival gate = RUBRIC POINTS ONLY ("no rubric violation in this single trial"). Holistic
  rank is reported as color, never as the gate. n=1: no capability generalization claimed.
- Pre-committed bucket mapping (X4): a task tier is a routing FREE WIN only if the cheapest
  passing arm has zero rubric violations on BOTH tasks of its tier; anything else on that
  tier = TRADE-OFF KNOB or NOT ROUTABLE, reported per-task.
- Falsified-if: cheap arms violate rubrics on T1/T2 (mechanical) — routing thesis dies.
