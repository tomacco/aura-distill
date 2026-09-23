# ADR 0001: Legacy updater compatibility before a software major

- Status: proposed (discovery output for [#76](https://github.com/tomacco/aura-distill/issues/76), part of [#74](https://github.com/tomacco/aura-distill/issues/74); implementation belongs to #79; the channel manifest schema and the beta channel are amended by [ADR 0002](0002-release-channels.md))
- Date: 2026-09-11
- Reproductions: `bash tests/updater-compat/run.sh`

## Context

Everything in this section was verified in the repository on 2026-09-11 at `origin/main` = `f257a4e` (VERSION 1.1.17). Proposals are kept out of this section.

### Shipped update paths

1. **The `/distill` dispatcher updates itself from fixed `main` URLs.** `distill.md:27` runs the version check on the first `/distill` of a session. `distill.md:214` fetches `https://raw.githubusercontent.com/tomacco/aura-distill/main/VERSION`. When the two versions differ and `feedback/preferences.md` holds `enabled: true` under `## Auto-update` (`distill.md:228-232`, `distill.md:246-260`), the agent updates silently. The update block (`distill.md:236-242`) is:

   ```
   curl -sL https://raw.githubusercontent.com/tomacco/aura-distill/main/distill.md -o ~/.claude/commands/distill.md
   curl -sL https://raw.githubusercontent.com/tomacco/aura-distill/main/distill-process.md -o {DISTILL_DIR}/distill-process.md
   curl -sL https://raw.githubusercontent.com/tomacco/aura-distill/main/distill-monitor.md -o {DISTILL_DIR}/distill-monitor.md
   mkdir -p {DISTILL_DIR}/data {DISTILL_DIR}/inbox
   echo "NEW_VERSION" > {DISTILL_DIR}/.version
   ```

   The block is prose executed by a language model, not by a script. Nothing in the client compares major versions, reads a manifest, or validates what it downloaded.

2. **`install.sh` and `install.ps1` fetch payloads from `main`.** `install.sh:13` sets `REPO="${AURA_DISTILL_REPO:-https://raw.githubusercontent.com/tomacco/aura-distill/main}"`; `install.sh:71-74` (`fetch_file`) reads a local path or runs `curl -fsL`; `install.sh:237,241,245` fetch the three core files, `install.sh:279` fetches `rules/distill.md`, `install.sh:327` fetches `agents/<name>.md`. `install.ps1:11` sets `$Repo` the same way; `install.ps1:79-89` (`Get-File`) copies a local path or runs `Invoke-WebRequest`; `install.ps1:130-136,186,234` fetch the same files. The installer scripts themselves are documented as `curl -sL .../main/install.sh | bash` (`README.md:53`, `INSTALL.md:23`, `docs/index.html:1852,2356`) and `irm .../main/install.ps1 | iex` (`README.md:58`, `install.ps1:5`, `docs/index.html:1856,2357`), so a user always runs the current installer and the current payload.

3. **The Homebrew formula pins the installer, not the payload.** `homebrew/Formula/aura-distill.rb:4-5` pins the `v1.0.0` tarball and its sha256; `:25-27` exec the tarball's `install.sh`. That `install.sh` (`git show v1.0.0:install.sh`) hardcodes `REPO="https://raw.githubusercontent.com/tomacco/aura-distill/main"` at line 13, has no override and no local-path branch, and fetches `distill.md`, `distill-process.md`, `distill-monitor.md`, `rules/distill.md` from `main` at lines 214, 218, 222, 244. Its store path is `~/.claude/distill` (line 190) and it writes `.version` = `1.0.1` (line 10, 226). The `libexec` copies of the distill files (`formula :12-15`) are never used by the installer. Result: a "pinned" Homebrew install installs whatever `main` serves today, into the legacy store layout, and then the dispatcher's version check reports 1.0.1 vs 1.1.17 and offers the same `main` update.

4. **Codex and Antigravity have no updater of their own.** The Codex managed block (`install.sh:379-398`) points at `distill-monitor.md` and `distill-process.md` in the store and carries no fetch instructions; neither `distill-process.md` nor `distill-monitor.md` contains a URL. The Antigravity plugin (`plugins/aura-distill/`) contains no fetch, curl or version text. These clients receive new payloads only when someone re-runs an installer (path 2) or when a Claude session on the same store runs path 1, since `distill-process.md` and `distill-monitor.md` are shared files in `~/.aura-distill`.

5. **The manual method fetches `main` too.** `INSTALL.md:66-79` download the four files from `main`; `INSTALL.md:112` sets `.version` from `main/VERSION`.

### Release mechanics

- **Every merge to `main` is live at the raw URLs immediately; most also bump `VERSION`.** `.github/workflows/bump-version.yml` runs on push to `main` unless every changed path is in its `paths-ignore` list (version-synced files, `.github/**`, `research/**`, and since #79 `docs/adr/**` and `tests/**`), bumps the patch number, rewrites `VERSION`, `install.sh`, `install.ps1`, `README.md`, `docs/header.svg`, `docs/index.html`, and pushes a `[version-bump]` commit. Content therefore reaches the raw URLs before `VERSION` changes, in two commits a few seconds apart. There is no staging branch, no release approval step, and no way to hold content back from the raw URLs once merged.
- **Tags and releases.** There is exactly one tag, `v1.0.0` (commit `7dcbd7f`, 2026-05-17, whose `VERSION` file reads `1.0.1`), and one GitHub release with the same name and no assets. Seventy-six commits and nineteen `[version-bump]` commits have shipped since without a tag. `CHANGELOG.md` has carried an `[Unreleased]` section for the entire 1.x line; the auto-update mechanism itself is listed under 0.5.0.
- **Raw caching.** `raw.githubusercontent.com` answered `Cache-Control: max-age=300` for `main/VERSION` on 2026-09-11. Each file is cached independently, so a client can observe a fresh `VERSION` with stale content files, or the reverse.
- **The pre-rename URL still works.** `https://raw.githubusercontent.com/tomacco/claude-distill/main/VERSION` returned HTTP 200 on 2026-09-11. Clients installed before the rename (commit `0292f23`, 2026-05-17) keep using that host path.

### What each shipped version of the dispatcher actually did

Built from `git log -p -- distill.md` (VERSION read from the same commit):

| Commit | VERSION | Update instructions as shipped |
|---|---|---|
| `7603b2a` 2026-05-06 | 0.1.0 | First version check. Fetches `tomacco/claude-distill/main/VERSION`; on "auto-update" the agent is told to "fetch and overwrite `~/.claude/commands/distill.md` and `distill-process.md` from the repo" with no URL given. Persistent auto-update preference introduced. |
| `476b093` 2026-05-07 | 0.3.1 | Explicit curl block: `claude-distill/main/{distill.md,distill-process.md,distill-monitor.md}` written to `~/.claude/commands/` and `~/.claude/distill/`. Silent update when preference is on. |
| `012baaa` 2026-05-17 | 0.9.14 | Store paths become `{DISTILL_DIR}` (resolved by `install.sh` at install time). Dispatcher path stays hardcoded `~/.claude/commands/distill.md`. |
| `0292f23` 2026-05-17 | 1.0.0 | URLs move to `tomacco/aura-distill/main/...`. This is the block in tag `v1.0.0`. |
| `6797a19` 2026-07-31 | 1.1.10 | Store default moves to `~/.aura-distill`; block unchanged. Installers gain `AURA_DISTILL_REPO` and local-path fetch. |
| `87a6b64` 2026-08-02 | 1.1.14 | Adds `mkdir -p {DISTILL_DIR}/data {DISTILL_DIR}/inbox`. Block unchanged since, through 1.1.23. |

Across every version, the client's decision is "is `main/VERSION` different from my `.version`?", and its action is "overwrite my three files from `main`". No shipped client can distinguish a patch from a major.

### Latent defects observed (facts, not decisions)

- The dispatcher block writes `curl -sL ... -o <live file>` with no download-to-temp and no content validation, so a 404 body or a truncated response overwrites the live file (the installers fixed this for `rules/distill.md` and agents in 1.1.8; the dispatcher block was left as is, recorded as an open follow-up on PR #39).
- The block downloads `distill.md` raw, so the 24 `{DISTILL_DIR}` occurrences in it are never resolved on an auto-update (`install.sh:237` resolves them with `sed`; `distill.md:237` does not). Whether the agent resolves them is left to the model.
- The block writes `~/.claude/commands/distill.md` regardless of a `--profile` install (`install.sh:144-155` resolves `~/.claude-<name>`).

These do not change the decision below; they are listed because #79 will touch the same lines.

## Compatibility matrix

"Major payload at `main`" means a software-edition dispatcher/process/monitor published at the historical `main` root paths, with or without a consent gate written into the new text. The reproductions in `tests/updater-compat/run.sh` section (a) execute the captured blocks against such an endpoint and section (b) against the decided layout.

| Released updater path | What it fetches | If `main` carried a software-major payload | Under the decided layout (section Decision) |
|---|---|---|---|
| Dispatcher 0.1.0 (`7603b2a`) | `claude-distill/main/VERSION`, then "overwrite from the repo" (model improvises URLs) | Overwrites itself with the payload; any gate in the new text is read only after the overwrite | Gets the files-only line; never learns of the channel unless the notice reaches it |
| Dispatcher 0.3.1 to 1.0.0-pre (`476b093`..`012baaa`) | `claude-distill/main/{VERSION,distill.md,distill-process.md,distill-monitor.md}` into `~/.claude/distill` | Same. Reproduced: `.version`=2.0.0, all three files are the payload, no consent recorded | Reproduced: stays on files-only, `.version` follows the files-only line, zero requests to the channel |
| Dispatcher 1.0.0 to 1.1.9 (`0292f23`..) | `aura-distill/main/...` into `~/.claude/distill` | Same, reproduced | Same, reproduced |
| Dispatcher 1.1.10 to 1.1.17 | `aura-distill/main/...` into `~/.aura-distill`; 1.1.14+ also `mkdir data inbox` | Same, reproduced | Same, reproduced |
| `install.sh`/`install.ps1` 0.x to 1.0.x (curl-pipe or irm-pipe from `main`) | The installer itself from `main`, then the four payload files from `main` | User runs the current installer, so this row becomes whatever the current installer does; the payload files are the current `main` files | Current installer is part of the files-only line and fetches only `main` |
| `install.sh`/`install.ps1` 1.1.10 to 1.1.17 (`AURA_DISTILL_REPO` override, local-path fetch, agents) | Same plus `agents/scribe.md`, `agents/scout.md` | Reproduced with the checked-in `install.sh`: installs the payload including `rules/distill.md`, no gate | Reproduced: installs the files-only bridge, zero requests to the channel |
| Homebrew formula (tarball `v1.0.0`, `aura-distill install`) | `v1.0.0` `install.sh`, hardcoded `main`, legacy store layout, `.version`=1.0.1 | Reproduced with the captured fetch block: installs the payload including `rules/distill.md` | Reproduced: installs the files-only bridge |
| Manual method (`INSTALL.md`) | Four files plus `VERSION` from `main`, by hand | Installs the payload | Installs the files-only line |
| Codex adapter, Antigravity plugin | Nothing on their own; consume the shared store files written by rows above | Inherit whatever a Claude session or installer wrote | Inherit files-only |
| `AURA_DISTILL_REPO` pointing at a fork or mirror | Whatever that base serves | Outside this repository's control | Outside this repository's control; documented as such |
| Stale/mixed cache (any row) | Fresh `VERSION`, cached files, or the reverse | Cannot help: a stale payload is still a payload once the cache turns over | Reproduced (section c): a client may record a `.version` it does not have, or see `2.0.0` in `VERSION` with files-only content; neither yields a software payload, and `.version` is proven unreliable as a channel input |

**Oldest-supported client that skips straight to the future major announcement:** dispatcher 0.1.0 (`7603b2a`, 2026-05-06) with auto-update on, store at `~/.claude/distill`, URLs under `tomacco/claude-distill`. It is supported in the sense that matters here: it behaves identically to 1.1.17 (fetch `main/VERSION`, overwrite from `main`), so any protection that works for it is endpoint-side and works for every later client. Nothing older exists; `f10e622` (initial release) had no version check.

The matrix has one conclusion. Every released path resolves to "install what `main` serves". Protection cannot live in the client.

## Options considered

Each option was treated as a hypothesis and checked against the matrix and the reproductions.

1. **Preserved legacy endpoints.** Keep every historical `main` root URL serving the files-only line forever, and publish the software major somewhere no shipped client references. Verified by section (b): all captured blocks and both installers stay on files-only with zero requests to the channel. On its own this option is silent: skipped-release clients never learn that a software edition exists. It is the only option that protects clients that never update again, so it is necessary.

2. **Channel manifest.** A machine-readable file (proposed `channels/manifest.json` at `main`) listing the files-only line and the software line with version, base URL, status, requirements, guide URL and `auto_update: never`. Section (b) confirms no shipped block ever requests it, so it is inert for old clients and cannot protect them by itself. It is valuable as the single source that a channel-aware dispatcher and future installers read, and as the thing CI can check `main/VERSION` against.

3. **Safe bootstrap notice.** A files-only "bridge" release on `main` whose dispatcher reads the manifest and prints a notice about the software edition, without fetching from it. Old clients with auto-update on adopt the bridge on their next `/distill` because it is an ordinary files-only patch. Clients that never run `/distill` again never see it, which is acceptable because option 1 keeps them safe. The notice is informative, never protective, and must not be an instruction the model could act on.

4. **Separately distributed major.** The software edition ships from its own branch (or repository), its own installer entry point and its own Homebrew formula name; nothing on `main` root ever contains it. This is option 1 seen from the publisher's side. It fails if anyone ever merges software content to `main` root, so it needs an enforced guard, not a convention.

5. **Gate inside the new updater text** (the implicit status quo). Rejected by section (a): the gate arrives inside the payload it is meant to guard, after the overwrite, and no client evaluates it before installing.

6. **Bump `main/VERSION` to the software major so old clients "notice".** Rejected by section (c): old clients only compare strings, so they would update anyway, and `.version` would record a version whose files they do not hold.

Decision: combine options 1 to 4. None of them is sufficient alone; together they cover clients that never update, clients that update blindly, and publishers who might merge the wrong thing.

## Decision

### Historical URLs that stay safe forever

The following raw paths are legacy endpoints. Whatever they serve must be safe for any client from 0.1.0 up to blindly overwrite itself with. "Safe" means: files-only, no new mandatory executable, runtime, daemon, service, connector, account or network dependency, and any prompt at these paths must handle both legacy store layouts (`~/.claude/distill`, `~/.aura-distill`) with explicit consent before any migration.

- `https://raw.githubusercontent.com/tomacco/aura-distill/main/VERSION`
- `.../main/distill.md`, `.../main/distill-process.md`, `.../main/distill-monitor.md`
- `.../main/install.sh`, `.../main/install.ps1`, `.../main/INSTALL.md`
- `.../main/rules/distill.md`, `.../main/agents/scribe.md`, `.../main/agents/scout.md`
- the same paths under `https://raw.githubusercontent.com/tomacco/claude-distill/main/` (rename redirect; the repository must never be renamed again without a redirect)
- `https://github.com/tomacco/aura-distill/archive/refs/tags/v1.0.0.tar.gz` and the Homebrew tap: `brew install tomacco/aura-distill/aura-distill` resolves to the separate repository [`tomacco/homebrew-aura-distill`](https://github.com/tomacco/homebrew-aura-distill), `Formula/aura-distill.rb`, not to the in-repo copy under `homebrew/`. Both copies pin that tarball and also declare `head "https://github.com/tomacco/aura-distill.git", branch: "main"`, so `brew install --HEAD` builds from `main` as it stands: the `main` tree as a whole, not only the raw paths above, must stay files-only
- from the bridge release on (#79, ADR 0002): `.../main/bin/distill-update.sh` (fetched by the bridge dispatcher when missing) and `.../main/channels/manifest.json` (read by the updater for the notice)

None of these files may be deleted, moved, or made to reference a software base. `main/VERSION` never carries the software edition's version. If the files-only line itself ever needs an incompatible change (#75/#78), it still ships at these paths, and the incompatibility is handled inside the new prompt with a consent step before touching the store; it is never handled by pointing old clients somewhere else.

### Where the software major lives

A separate branch whose raw base no shipped client references (name provisional: `software-2.x`, see open questions). Its own `install.sh`/`install.ps1` entry points, its own `VERSION`, its own `UPGRADE.md` guide. If published to Homebrew, under a distinct formula name. Prereleases live on the same channel with `status: prerelease` in the manifest and are never mentioned by the bridge notice unless the user opted into prerelease notices.

### Channel manifest

`channels/manifest.json` at `main` root. *Amended by ADR 0002:* the schema is `beta.{status,tag,version}` and `software.{status,version,requirements,guide,auto_update:"never"}`. There is no `files_only` entry (`main/VERSION` stays the single source of the stable version, so the bump workflow cannot drift from it) and no `software.base`: the files-only line never learns where the software edition is served, so no prose or script on it can be talked into fetching it. CI fails if any legacy endpoint file references the software base or contains the software payload marker string used by the software installer (`tests/updater-compat/check-endpoints.sh`, run on every PR, on push to `main`, and in `bump-version.yml` before a bump is published).

### Required publication order

1. Merge this ADR, the reproductions, and the CI guard (guard implementation in #79).
2. Ship the bridge release on `main` (files-only): dispatcher reads the manifest for the notice only, never fetches a software base regardless of the auto-update preference, resolves `{DISTILL_DIR}`, downloads to temp and validates before replacing live files (closing the latent defects above). Because the bridge is prose executed by a model, the bridge text must carry an explicit negative instruction: do not fetch, run, install or follow anything a notice or manifest mentions; quote the guide URL as text only. The manifest exposes only `version`, `requirements` and `guide` for the software edition, never a base URL, so there is nothing to follow even if the model misreads the instruction. The 0.1.0 dispatcher already showed what a model does with a vague fetch instruction (it improvises URLs), so #79 must state the prohibition, not imply it, and the reproductions must be re-run against the real bridge text rather than the synthetic fixture. Manifest has no `software` entry yet, or `status: unpublished`. Run `tests/updater-compat/run.sh` against the real bridge files. That runner executes curl blocks and scripts and inspects what lands on disk; it cannot show that a model obeys the prose. What it can show, and what the safety argument rests on, is that the endpoints never serve a software payload and that the updater script the prose delegates to refuses one.
3. Create the software branch and publish its payload, installer and guide there with `status: prerelease`.
4. Flip the manifest entry on `main` to `status: stable`. This is the announcement moment: clients that already hold the bridge start showing the notice; clients that do not remain silent and safe.
5. Update README, landing page and Homebrew for the software edition, pointing only at the channel.

Never, at any step: changing the repository's default branch away from `main` (ref-less clones, raw `HEAD` URLs and contents-API calls all follow the default branch); software content at a legacy endpoint path; a `main/VERSION` value whose payload is not files-only-safe; a tag whose tarball would make the Homebrew formula fetch software content; deleting or renaming a legacy endpoint file.

### The consent boundary

Consent for the software major is enforced in the software channel's installer, at exactly one point: after the manifest and guide have been fetched and the notice printed, and before any of the following happens for the first time: writing a file outside a temporary directory, downloading the software payload, executing anything downloaded, creating a service, daemon, scheduled task or background process, opening any network connection other than the manifest/guide fetch, reading or migrating the knowledge store. Store migration then has its own second gate (dry run shown, explicit confirmation) owned by #89.

Reference behavior: `tests/updater-compat/fixtures/consent-gate.sh`, asserted in section (d).

The existing auto-update preference in `feedback/preferences.md` is scoped to the files-only line. It never authorizes a software channel fetch. No installer or dispatcher may treat it, or any earlier "yes", as consent to the software edition.

### User notice text

Bridge dispatcher, once per session, after the version check, only when the manifest lists `software.status: stable`, and only as text (no question, no command executed):

> aura-distill: a separate software edition (v2.0.0) is available. Auto-update does not install it and will not. It requires: <requirements from manifest>. Your files-only installation stays supported and unchanged. If you want it, read <guide URL> first and run its installer yourself. No reply is needed.

Software installer, before the consent boundary:

> aura-distill software edition v2.0.0 is a major change from files-only. Installing it will: <side effects from manifest>. Read <guide URL> before continuing. Your files-only installation stays supported and is not changed unless you consent here.
> Type "adopt 2.0.0" to continue, or press Enter to keep files-only:

### Non-interactive rule

If stdin or stdout is not a terminal, the input is empty, the read times out, or the answer is anything other than the exact phrase naming the version: print "Kept files-only. Nothing was installed or changed.", write nothing, exit with code 2. Piped input (including a piped "yes" or a piped "adopt 2.0.0") is not a terminal and is refused. Both stdin and stdout must be terminals, so `installer | tee log` is refused as well; this is deliberate (a redirected run is a scripted run) and #79 should document it rather than relax it. There is no flag, environment variable or preference file that substitutes for the interactive answer in this ADR; see open questions for provisioning. No response means files-only, never consent.

Company approval processes are respected by construction: the installer states what it will do and stops; it never asserts that anything is approved, never installs silently, and never retries on its own.

## Consequences

- `main` root becomes a frozen compatibility surface. Any file listed above is a public API with an unknown number of consumers, and refactors that would move or rename them are off the table.
- The files-only line keeps getting patch releases through the existing bump workflow. That workflow is safe by construction as long as software content never enters `main`; the CI guard turns that from a rule into a check.
- Users who never run `/distill` again, or who pinned an old installer, are protected without telemetry and without ever hearing from us. That is the intended trade: safety without reach.
- The Homebrew formula's pin is cosmetic today. Fixing it (a formula that installs from its own tarball) is desirable but independent of this decision, because even a fixed formula would still run an `install.sh` that fetches `main`.
- The bridge release must also fix the three latent defects, since it is the last dispatcher many clients will ever fetch blindly; after it, download-to-temp plus validation protects them from truncated or 404 bodies.
- `.version` stays a display value. Channel and consent logic must key on content markers and the manifest, never on `.version`.
- Two release channels means two changelogs, two version numbers and two installers to maintain. The roadmap already accepts this.

## Open questions

| Question | Owner | Needed by |
|---|---|---|
| Branch name and host for the software channel (`software-2.x` branch in this repo, or a separate repository) | Ivan | #79 before step 3 |
| Homebrew: distinct formula name for the software edition, and whether to fix the `aura-distill` formula so `brew` installs from its tarball | Ivan | #88 |
| Provisioning use case: is there any acceptable non-interactive consent (for example a consent record created interactively once, then honored by a scripted reinstall of the same major on the same machine)? This ADR says no; a later ADR may narrow it | Ivan | #79 |
| Does the files-only redesign (#75/#78) change the store layout incompatibly? If yes, the bridge prompt must carry legacy-layout handling with a consent step | #75 owner | before step 2 |
| Prerelease notices: opt-in preference key name and wording | #79 | answered by ADR 0002: installing the beta channel is the opt-in; no separate key |
| Fix the three latent dispatcher defects (unvalidated overwrite, unresolved `{DISTILL_DIR}`, hardcoded `~/.claude/commands`) in the bridge; one issue per defect or one bridge issue | Ivan | addressed in #79 by `bin/distill-update.sh` (stages and validates, resolves the placeholder, reads `.command-path`) |
| Coexistence: after a user adopts the software edition, a files-only dispatcher on the same store (another client, or a profile that kept 1.x with auto-update on) keeps replacing the shared `distill-process.md`/`distill-monitor.md`. Does the software installer retire the files-only updater (for example by writing a store marker the updater honours), or do the editions keep separate stores? | #88 owner | before step 4 |
| Independent review of this ADR and the reproductions (acceptance criterion 5 of #76): done on PR #94 per REVIEW-PROTOCOL.md (verdict REQUEST CHANGES; one isolation defect in the runner and four factual corrections, all addressed in the same PR; the decision itself was upheld). Remaining: Ivan's acceptance of the decision before #79 starts | Ivan | before #79 starts |
| This ADR is published with the GitHub Pages site (`docs/` is the Pages root); confirm that is intended or move `docs/adr/` out of the published tree | Ivan | before merge |
