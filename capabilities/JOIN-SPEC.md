# Join spec v1 — commodity metadata by reference, never rebuilt

A local contracts file is a JOIN of three data classes. Only one is ours to measure.

| Class | Source | How it enters the contract |
|---|---|---|
| Pricing, context windows, feature flags | maintained open catalogs (see allowlist) | imported at refresh time, tagged `imported-metadata` + source + date |
| Public benchmark signal (optional, coarse) | open leaderboards with permissive terms | LINKED by reference (`referenced-external` + URL), never copied into the file |
| Demand-coverage scores + verbosity factors | the LOCAL calibration battery (skill) | measured, tagged `measured` + battery version + n + date + expiry |

## Source allowlist (metadata imports)
- models.dev `models.json` (MIT) — provider/model metadata, pricing incl. cache rates,
  context/output limits, feature booleans.
- LiteLLM `model_prices_and_context_window.json` (repo license) — pricing incl. tiered
  rates, `supports_*` booleans.
- OpenRouter `/models` API (per its TOS) — pricing, context, modality, parameters.
Rules: record source + retrieval date per imported field; prefer the freshest source on
conflict and keep the disagreement visible; NEVER import from sources whose terms gate
redistribution (notably: Artificial Analysis free tier bans redistribution — link to it,
don't store it). Adding a source to this allowlist requires a license check in the PR.

## Cost representation
Store absolute prices as imported, but POLICY consumes ratios computed at decision time
against a FIXED reference unit (a stable named anchor recorded in the contracts file),
not against "the cheapest model" — re-basing on lineup changes would invalidate every
record at once.

## Contract record shape (local file, `{DISTILL_DIR}/data/capabilities-local.json`)
One record per model: identity (id, provider, aliases), imported metadata block,
referenced-external links, measured block (per-demand: score, n, dispersion, battery
version, measured_at, expires), verbosity factors (per demand), and a top-level
`freshness` the policy reads (fresh | stale | expired). Local files may contain private
models; the file never leaves the machine and is not part of the synced knowledge set.
