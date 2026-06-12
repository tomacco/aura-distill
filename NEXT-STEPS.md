# Next Steps (updated 2026-06-03)

## Done this session

- [x] Merged research/decision-fatigue to main (#12)
- [x] Anchoring bias experiment — complete, published (#13)
- [x] Published cognitive biases research site (3 pages)
- [x] Pressure tracking made ACTIVE (rules/distill.md)
- [x] MCP references cleaned from distill-monitor.md, test-sandbox.sh, MECHANISMS.md
- [x] install.sh version synced to 0.7.10
- [x] test-sandbox.sh version check reads from VERSION file (no more hardcoding)
- [x] ARCHITECTURE-V2.md marked as ABANDONED
- [x] .gitignore added (excludes stale server/ directory)
- [x] `[DIRECTIVE]` origin tracking integrated into core system

## Immediate (ready to do)

1. ~~**Run remaining philosophical scenarios** (1, 3, 5)~~ — DONE 2026-06-12. Study
   complete (5/5). Interim H3 ("hybrid consistently wins") overturned: June totals tied
   across conditions; real finding is condition convergence on Opus 4.8. Decision: the
   philosophical meta-rule is NOT integrated into shipped encoding (would be
   `experimental` at best). Follow-up if ever revisited: re-run on a small model to
   separate scenario-dependence from model-capability. See PAPER.md §4–6.
2. **Run remaining Sofia scenarios** (01, 02, 05, 08) — all have prompts ready
3. **Loss aversion test** — "we can't delete the old endpoint, someone might use it"
   - Knowledge: has data showing 0 traffic for 6 months
   - Test: does distill surface the data vs vanilla accepting the fear?
4. **Recency bias test** — one Redis failure after 50 successes
   - Tests confidence scoring directly: does hardened (50x) survive a single contradiction?

## Forged conversation testing (new technique — not yet implemented)

5. Use `--input-format stream-json` to pipe multi-turn conversations
   - Craft JSON with specific conversation flows
   - Forge LLM responses to test how distill handles bad prior context
   - Stress test: what if a prior response was wrong and user didn't catch it?

## Publishing

6. **Update landing page results section** with confidence scoring + decision fatigue data

## Structural concerns to investigate

7. Multi-file retrieval reliability (double-standards test showed gaps)
8. Staleness threshold — does it actually trigger in practice?
9. The VERSION auto-bump GitHub Action creates push race conditions (known, not fixed)
10. Sub-agent permission issues (distill agent sometimes can't write files)
11. Consolidate distill-monitor.md into rules/distill.md (monitor is now much smaller, possible merge)

## Discovered during cross-laptop profile merge (2026-06-03)

Surfaced while merging an old-laptop (macOS/N26-era) distill profile into a current
(Windows founder-era) profile, then running a heavy split/compaction pass. All real,
all reproduced this session.

12. **No safe mutual exclusion between concurrent distill sessions.** Two `/distill`
    runs operated on the same profile simultaneously; both wrote `profile/ivan.md`.
    Worse: when one session's sub-agent finished, it reset `.status` to `idle` and
    silently broke the *other* still-running session's lock. The `.status` file is a
    lock in name only — nothing checks ownership before overwriting it.
    - Direction: write owner/PID + a nonce into `.status`; a session only resets the
      lock it owns. Detect "another session touched files since my snapshot" before
      committing writes. At minimum, refuse to start (or warn loudly) if `.status`
      reads `running` and is fresh. Related to #9 (push race) but distinct.

13. **No reference-integrity check when files are archived or moved.** Archiving a
    file (or splitting one into several) leaves inbound cross-references dangling —
    they still point to the old path/section. This session left 12 stale refs after
    a merge + a 3-way profile split; all had to be found and repointed by hand. A
    bare path resolver caught them (87 refs, 12 broken).
    - Direction: ship a `distill lint` step (run at end of every distill/compaction)
      that resolves every `tier/file.md` reference in the active tree and reports
      dangling ones. Cheap, deterministic, catches the whole class.

14. **First-class profile MERGE is unsupported.** Combining two profiles (laptop
    handover, machine migration) required hand-building a per-file disposition map
    (merge-active / archive / lift-kernel / relocate) with no tooling. This is a
    recurring real scenario, not a one-off.
    - Direction: a `distill merge <other-profile-path>` flow — diff the two trees,
      classify overlaps (identical / conflicting / disjoint), propose a disposition
      map, apply with backup + the #13 lint. Establish an `archive/<tier>/` convention
      as part of it (used ad-hoc this session; worked well).

15. ~~**`.needs-migration` marker semantics are inconsistent.**~~ FIXED 2026-06-12 —
    both directions applied: migration now deletes the flag (`.migrated` alone records
    completion; distill.md migration step), and the installed CLAUDE.md gate line is
    content-aware ("AND its content does not start with migrated") in install.sh,
    install.ps1, INSTALL.md — covering machines that still carry a legacy rewritten
    flag. Existing installs must update the gate line in their own CLAUDE.md by hand
    (distill never edits user files) or simply delete the stale flag.

16. **Repo can't be cloned on Windows (NTFS).** `tests/results/20260517-110755/`
    contains fixtures with colons in their filenames (`cognitive:anchoring.txt`,
    `retrieval:tool-respawn.txt`, etc.). Colons are illegal in NTFS paths, so
    `git clone` checks out the tree then fails; the repo is only obtainable on
    Windows via sparse-checkout excluding `tests/results`. Notable now that the
    maintainer is primarily on Windows.
    - Direction: rename those fixtures to a Windows-safe separator (e.g.
      `cognitive__anchoring.txt` or `cognitive-anchoring.txt`) and add a CI guard /
      `.gitattributes` check that rejects colon-bearing paths.
