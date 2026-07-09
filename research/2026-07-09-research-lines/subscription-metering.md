# Research line: subscription metering (what actually counts against Max limits?)

Status: COLLECTOR DEPLOYED 2026-07-09 (passive); analysis pending ~2 weeks of data.

## Problem
All our $ figures are API-equivalent counterfactuals. Actual billing is a Max subscription
whose metering is undocumented: official help-center language implies cache reads are
discounted/excluded from limits, but one detailed community telemetry case (claude-code
#24147) reports cache reads consuming 99.93% of quota. If cache reads are ~free on
subscription, context hygiene matters far less than the API math suggests; if they count,
it's the whole game. This single unknown scales every other economics conclusion.

## Observables (no private API access needed)
1. Per-request usage composition from local transcripts (fresh input, cache read, cache
   write, output) — we already mine this.
2. Limit events — two sources, both needed:
   (a) transcript plain-string error records (contamination-guarded: short string content
   only, never tool_result blobs — the limit string lives inside our own knowledge files);
   (b) the resume-watchdog log (fail-fast attempt timestamps). KNOWN LIMITATION: an
   interactive session freezing on a limit writes NO transcript record — (a) alone
   structurally under-counts; treat watchdog fail-fast bursts as the ground truth for
   interactive freezes.
3. 5h-window structure: session activity clustering reconstructable from timestamps.

## Method
Passive daily collector (deployed): mines all transcripts daily into an append-only CSV
(date, tokens by type, requests, sessions, limit-events). After 2+ weeks:
- Regress limit-hit occurrence against day composition: if cache-read-heavy days (marathon
  sessions, big resident context) hit limits at similar total-WORK levels as output-heavy
  days → cache reads count. If limit hits track (fresh input + output + cache writes) and
  ignore cache-read volume → reads are excluded/discounted.
- Natural experiments: post-/clear days vs marathon days; subagent-heavy vs main-loop-heavy.
Confound register: model mix (Fable vs Opus weighting unknown), plan-level changes,
Anthropic-side metering changes mid-window (date-stamp everything), weekly cap vs 5h cap
(two separate mechanisms — attribute events to the right one via reset-time strings).

## Decision mapping
- Reads count → context-hygiene levers keep their measured priority; publish correction to
  the token-economics page ($-counterfactual framing becomes directionally right for
  subscription too).
- Reads excluded → re-rank levers: output discipline + cache-WRITE avoidance (context
  growth) rise; resident-context size falls in priority. Update ops/model-tiering.md lever
  order with the subscription-metering caveat resolved.

## Collector spec (deployed)
Windows scheduled task `AuraDistill-MeteringCollector`, daily 23:45, absolute pwsh path,
test-fired at registration. Runs miner-lite over ~/.claude/projects → appends
research-branch-tracked CSV + limit-event log. Local only; nothing leaves the machine.
