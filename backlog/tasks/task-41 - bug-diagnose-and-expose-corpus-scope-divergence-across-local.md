---
id: task-41
title: "Bug: diagnose and expose corpus/scope divergence across local and MCP retrieval"
status: To Do
assignee: []
created_date: 2026-10-07
updated_date: 2026-10-07
labels: [bug, area:memory-service]
dependencies: []
source: https://github.com/tomacco/aura-distill/issues/65
---

## Description

Imported from https://github.com/tomacco/aura-distill/issues/65

## Execution update (2026-09-10)

Part of #74. Blocked by: None; independently actionable.

The current contract below supersedes conflicting mechanics or acceptance criteria in the historical proposal.

Keep this correctness bug independently actionable now. Diagnose which store, revision and authorized scope each path was intended to serve before concluding that their entire contents must match. A machine-local overlay may intentionally be absent remotely; fixing divergence must never upload excluded knowledge.

### Current acceptance

- [ ] Reproduce against synthetic local/shared/remote scopes and identify the actual source, sync behavior and intended scope for the reported path.
- [ ] Results expose store identity, revision, scope and freshness sufficient to distinguish an intentionally narrower corpus from stale or wrong shared data, without exposing excluded names/content.
- [ ] Same authorized shared corpus/revision yields equivalent facts across paths; stale/wrong-corpus and unknown-scope responses are explicit and cannot support a global absence claim.
- [ ] A regression test covers intentional local-only exclusion as well as genuine stale/wrong shared state.
- [ ] Deliver independently tested corpus identity/scope behavior and reusable regression fixtures; future #87 owns integration of those fixtures into the new API.

The local-filesystem-as-universal-authority workaround below is historical. #81 decides authority in line with #61; offline local snapshots must report their scope and freshness.

<details>
<summary>Original report and proposal (preserved historical context)</summary>

## Summary

During the 2026-08-18 retrieval benchmark (#62), the two MCP-path runs revealed that the **claude.ai aura-distill MCP connector serves a different corpus than the live local `~/.aura-distill` store** — and returns confidently wrong answers as a result. This is a correctness bug, strictly worse than any latency concern.

## Evidence (both from clean-context agents, same day, same machine)

- MCP `spine` returned **~21.5 KB** of index; the local `SPINE.md` is **7.3 KB**. Different content, not just formatting.
- MCP `search_knowledge` for `siemens` and `gitlab` returned **zero hits**, and the MCP spine has no Siemens entries — while the local store has `ops/siemens-systems.md`, `ops/siemens-access.md`, `profile/siemens-org.md`. The agent's conclusion: *"the knowledge base does not contain the Siemens GitLab URL"* — **wrong**.
- MCP `read_knowledge` served `craft/realtime-3d-rendering.md` and `projects/projector-stage.md` — files that exist **nowhere** on this machine (checked Windows store and the WSL Ubuntu distro, which has no `~/.aura-distill` at all).
- Latency, for the record: no win either — fixed ~4 s ToolSearch schema-load tax + 3.9–5.8 s per MCP call, comparable to local Reads.

The served corpus looks like a stale or foreign snapshot (different machine? old claude.ai-side sync?). Origin unknown — that's part of the bug.

## Why it matters

Any client that trusts the MCP path (claude.ai web/mobile sessions, remote agents without filesystem access) gets false negatives ("we never distilled X") and false positives (knowledge from a corpus that isn't the user's current one). Silent divergence is the worst failure mode for a memory system.

## Proposed actions

- [ ] Identify what the claude.ai connector actually serves and where/when it syncs from.
- [ ] Add a **store fingerprint** to `spine` output (version + content hash + last-modified) so any client can detect divergence against expectations, and mismatches are visible instead of silent.
- [ ] Until fixed: document that the MCP path is untrusted for retrieval when a local store exists; local filesystem is the source of truth.

---
Filed by `claude-fable-5-distill-tomacco` (Claude Fable 5, Claude Code CLI on Ivan's Windows box). Address me by sign-off name in comments.

</details>

## Acceptance Criteria

## Handoff

## Evidence

## Final Summary
