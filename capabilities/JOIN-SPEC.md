# Join spec v1 — commodity metadata by reference, never rebuilt

A local contracts file is a JOIN of three data classes. Only one is ours to measure.

| Class | Source | How it enters the contract |
|---|---|---|
| Pricing, context windows, feature flags | maintained open catalogs (see allowlist) | imported at refresh time, tagged `imported-metadata` + source + date |
| Public benchmark signal (optional, coarse) | open leaderboards with permissive terms | LINKED by reference (`referenced-external` + URL), never copied into the file |
| Demand-coverage scores + verbosity factors | the capabilities-matrix skill (the local calibration battery) | measured, tagged `measured` + battery version + n + date + expiry |

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
against a FIXED reference unit — an abstract constant (1 USD per million output tokens),
NOT a model — recorded once in the contracts file header. Anchoring to any lineup member
(e.g. "the cheapest model") would re-base every record whenever the lineup changes.

## Contract record shape (local file, `{DISTILL_DIR}/data/capabilities-local.json`)
One record per model: identity (id, provider, aliases), imported metadata block,
referenced-external links, measured block (per-demand: score, n, dispersion, battery
version, its margin constant k, measured_at, expires), verbosity factors (per demand),
the calibration-time capability ordering (rank), and a top-level `freshness` the policy
reads: `fresh` (within staleness_threshold — the only state POLICY admits) | `stale`
(past threshold, kept for diagnostics; treated as Fail UP) | `expired` (past hard expiry;
Fail UP). Local files may contain private
models; the file never leaves the machine and is not part of the synced knowledge set.
