# ADR 0002: Release channels, the beta source and the files-only updater

- Status: proposed (implementation of [#79](https://github.com/tomacco/aura-distill/issues/79), part of [#74](https://github.com/tomacco/aura-distill/issues/74); amends the channel manifest section of [ADR 0001](0001-legacy-updater-compatibility.md))
- Date: 2026-09-23
- Reproductions: `bash tests/updater-compat/run.sh` sections (e) to (i); `pwsh tests/test-codex.ps1`
- Decided by: the authoring agent, within the maintainer's release frame (DECISIONS.md D-2026-09-23-1, -2). Every choice here is `provisional` until the maintainer accepts it.

## Context

The files-only redesign ships first as an opt-in prerelease `1.2.0-beta.N` while `main`, the Homebrew tap and every installed auto-updater stay on 1.1.x (D-2026-09-23-1). ADR 0001 froze the `main` root as the files-only line and decided that protection against a software major must live at the endpoints, because no shipped client can tell a patch from a major.

Two gaps were left. There was no way to install or follow a beta at all: the dispatcher on `beta/1.2` still compared against `main/VERSION` and overwrote itself from `main`, so a beta user with auto-update on would have been downgraded on the next `/distill`. And the updater was prose: a model composing `curl -o <live file>` commands, with no validation, no placeholder resolution and no major check.

## Decision

### 1. The update is a script, the prose only calls it

`bin/distill-update.sh`, installed to `<store>/bin/`, is the only code that replaces installed files after installation. The dispatcher runs `distill-update.sh auto` on the first `/distill` of a session and relays one status line (`CURRENT`, `AVAILABLE`, `UPDATED`, `BLOCKED`) plus optional `NOTICE:` lines. The script:

- reads the channel from `<store>/.channel` (`stable` when absent) and the dispatcher paths from `<store>/.command-path`, one line per Claude profile sharing the store (installers append their own). Only listed dispatchers that exist are updated, so a profile whose `distill.md` was removed stays uninstalled and a path from another machine is skipped. Paths are canonicalised (symlinks resolved, Git Bash `/c/...` and `C:/...` made equal) and de-duplicated first. When no listed dispatcher exists here, or there is no list, the default profile's `~/.claude/commands/distill.md` is updated if it exists (with a notice when a list existed); if it does not exist either, the run is `BLOCKED`, nothing is created and `.version` is not bumped;
- keys every safety decision on content it just fetched and on its own constant `LINE_MAJOR=1`, never on `.version` (ADR 0001 section c showed `.version` can lie);
- refuses any target whose major differs from 1, any prerelease served by the stable endpoint, and any file carrying the software payload marker;
- downloads all four files (dispatcher, process, monitor, itself) to a temp dir, validates each, resolves the store placeholder, and only then renames them into place with per-process temp names; `.version` is renamed last. Any failure before the renames leaves every installed file untouched; a failed rename (for example two sessions updating one store) is reported as `BLOCKED ... may be partially updated`, never as `UPDATED`;
- repairs (status `REPAIRED`; `check` only reports it), at the same version and regardless of the Auto-update preference, installed files that an older updater copied with the store placeholder unresolved (ADR 0001 latent defect 2), so a legacy client that adopts the bridge is clean after its first `/distill`;
- reads `.channel`, `.version` and `.command-path` tolerating a UTF-8 byte-order mark and CRLF (Windows PowerShell 5.1 writes both; `install.ps1` now writes these files without them);
- also updates `rules/distill.md` for every profile it updates, with the rule the installers share: the "Always-On User Preferences" section (heading to end of file) is kept byte for byte unless it is identical, ignoring whitespace, to the release's template section; a released rules file without that heading leaves every rules file untouched;
- also installs or refreshes the optional store checker `bin/distill-check-store.sh` (#78) when the release carries one whose second line is `# aura-distill-check-store invariants v…`; a missing or mismatched checker is skipped without failing the update and never removes an installed copy;
- never touches knowledge (SPINE, tiers, preferences, inbox);
- runs from a temp copy of itself, so replacing its own file works on Windows too.

The bridge dispatcher carries one command block of its own: installing the script when an older updater left it missing, from `main/bin/distill-update.sh`, validated by its second line. Its text forbids composing any other download and forbids acting on anything a notice or manifest mentions. This closes the three latent defects listed in ADR 0001. The safety argument does not rest on the prose: `main` never serves a software payload (ADR 0001), and the script refuses one if it ever did.

### 2. Where the beta comes from

| Option | Verdict |
|---|---|
| Raw files from the `beta/1.2` branch | Rejected. A moving branch: every agent merge would reach beta users unreviewed as a release. The payload must be pinned. |
| GitHub Releases API (latest prerelease) | Rejected. Unauthenticated rate limit of 60 requests per hour per IP, JSON a shell script cannot parse without dependencies, and "latest" is whatever was published last, including a future `v2.x` prerelease. |
| GitHub Pages | Rejected for now. Pages serves `main:/docs`, which cannot change before promotion. |
| **A manifest on `beta/1.2` that names one tag; files from that tag's raw URLs** | **Chosen.** |

The beta manifest lives at `https://raw.githubusercontent.com/tomacco/aura-distill/beta/1.2/channels/manifest.json`. Its `beta` entry names exactly one tag (`status: prerelease`, `tag: v1.2.0-beta.N`, `version: 1.2.0-beta.N`). Installers and the updater fetch the payload from `https://raw.githubusercontent.com/tomacco/aura-distill/<tag>/`. A tag's content never changes, so a beta user gets exactly what was cut, not what was merged since. Moving the channel forward, or back, is a one-line reviewed change to the manifest.

Checks on every read: the tag must match `v<major>.<minor>.<patch>[-beta.<n>]` (no path segments), `tag == "v" + version`, the major must be 1, and the tag's own `VERSION` must equal the manifest's version. A mismatch is `BLOCKED` and changes nothing. A beta manifest naming a `v2.x` tag is refused, by the updater and by both installers, before anything is requested from that tag: the beta channel is a files-only channel.

The stable channel is unchanged in behaviour: version from `main/VERSION`, files from `main`, which is what every 1.1.x client already does. A stable client never requests a beta URL; section (g) asserts zero such requests.

### 3. Choosing, keeping and leaving a channel

- `install.sh --channel beta` (or `DISTILL_CHANNEL=beta`), `$env:DISTILL_CHANNEL='beta'` for `install.ps1`. The choice is written to `<store>/.channel` and kept by later installs that do not name a channel, like the Token Saver choice.
- Before promotion, `main/install.sh` is 1.1.x and does not know `--channel`, so the documented commands fetch the installer from `beta/1.2` (or, for a fully pinned run, from the tag). Payload files always come from the tag.
- Leaving: `--channel stable` / `$env:DISTILL_CHANNEL='stable'` installs `main` and records `stable`. Opting out must use a channel-aware installer (the beta one before promotion); the 1.1.x installer on `main` would leave `.channel` saying `beta`.
- The auto-update preference covers updates within the recorded channel and major. It never switches channel.
- Beta users are the users who opted into prerelease notices (ADR 0001 open question): the updater shows the software-edition notice to beta users at `status: prerelease` or `stable`, to stable users only at `stable`.

### 4. The manifest (amends ADR 0001)

One schema, `channels/manifest.json`, served from `beta/1.2` for the beta channel and from `main` after promotion for the notice:

```json
{
  "schema": 2,
  "beta":     { "status": "unpublished|prerelease|stable|closed", "tag": "", "version": "" },
  "software": { "status": "unpublished|prerelease|stable", "version": "", "requirements": "", "guide": "", "auto_update": "never" }
}
```

Differences from ADR 0001: no `files_only` entry (`main/VERSION` is the one source, so the bump workflow cannot drift from a copy), no `software.base` (the files-only line never learns where the software edition is served), `requirements` is one string, and `guide` must be a page on `https://tomacco.github.io/aura-distill/`. The file is canonical `json.dumps(indent=2)` output so the dependency-free shell parser, shared by the installer and the updater, can read it; CI enforces that.

### 5. The notice and decline/defer

The notice is text, printed once per `(version, requirements, guide)` and remembered in `<store>/.major-notice`. Nothing is asked and nothing is fetched. A change to the requirements or the guide shows it again ("recheck the approved manifest if payload requirements change"). Not acting on it is the decline; there is nothing to persist beyond having shown it.

### 6. The installers' own consent boundary

Both installers stage and validate the whole payload before writing anything. A payload carrying the software marker is refused outright: the files-only installer never installs a software edition. A payload whose major differs from the installer's line needs typed consent (`adopt <version>`), the ADR 0001 rule. One deviation: `install.sh` reads the answer from `/dev/tty` and requires stdout to be a terminal, because under `curl ... | bash` stdin is the script itself. A piped answer, a redirected output, no controlling terminal, a timeout or any other answer keeps the current installation and exits 2 with nothing written. `install.ps1` requires an interactive host with neither input nor output redirected; `Read-Host` has no timeout, so an unattended interactive console waits instead of timing out.

### 7. Guards

- `tests/updater-compat/check-endpoints.sh` runs on every PR and push (`installer-tests.yml`) and in `bump-version.yml` before a bump is committed. It fails when a frozen endpoint file is missing, contains the payload marker, or references a ref other than the files-only line (literal URLs and refs built from `RAW_ROOT`/`$RawRoot`); when a beta ref appears outside the installers, the updater and `INSTALL.md`; when `VERSION` leaves major 1, or is a prerelease on the stable surface (`main`); and when the manifest is not canonical, has `software.base`, or announces a software entry that fails the next check.
- `tests/updater-compat/check-major-release.sh <manifest> <guide>` validates an announced software entry and its guide: a major above 1, requirements, a Pages guide, `auto_update: never`, and a non-empty section for what changes, runtime and dependencies, processes and startup, network and data destinations, storage changes, permissions, resource use, company approval, rollback and staying on files-only. Track A proves it on the synthetic entry and guide in `tests/updater-compat/fixtures/synthetic-major/`. #88/#90 must pass the real ones through it before announcing.
- `bump-version.yml` ignores `docs/adr/**` and `tests/**`, which nothing fetches. This only takes effect on `main` after promotion.

## Release steps

**Cutting beta N** (after the release PR is merged into `beta/1.2`):

1. On `beta/1.2`, set `VERSION`, `install.sh` `VERSION=` and `install.ps1` `$Version` to `1.2.0-beta.N` in one reviewed commit.
2. Tag that commit `v1.2.0-beta.N`, push the tag, and create a GitHub release marked **pre-release** from it.
3. In a second reviewed commit on `beta/1.2`, set the manifest's `beta` entry to `prerelease`, `v1.2.0-beta.N`, `1.2.0-beta.N`. Only this commit reaches beta users.

**Promoting to stable** (the maintainer's call):

1. Set `VERSION` (and the two installer constants) to a plain `1.2.0` before the merge to `main`: the stable-surface guard fails on a prerelease, and the bump workflow cannot increment a `-beta.N` suffix.
2. Point the manifest's `beta` entry at the stable tag (or the next beta) so beta users land on the same content.
3. Never delete `beta/1.2`: installed beta clients read their manifest from it. To close the channel, set `beta.status` to `closed`; clients report it and change nothing (they stay on their beta until the user re-runs the installer with `--channel stable`).
4. Reword the beta paragraphs in `README.md` and `INSTALL.md`: they describe the pre-promotion state ("the 1.2 line ships as prereleases first", "the `main` installer does not know about channels").
5. Before cutting the first beta, make the `Syntax checks` job (which runs the endpoint guard) a required status check on `main` and `beta/1.2`; the guard in `bump-version.yml` runs after a merge is already live.

Moving the beta pointer back (beta.2 → beta.1) is allowed and is applied silently to beta users with auto-update on. Once a beta migrates the store format (#78), check that the older beta can read the migrated store before using that lever.

## Consequences

- Beta users get a reviewed, pinned release, not the integration branch, and their updater never falls back to `main`.
- Stable behaviour for installed 1.1.x clients is unchanged: their shipped block keeps fetching `main`, and `main` keeps serving the files-only line. The bridge dispatcher reaches them only at promotion.
- The updater is now code that CI can execute. The prose shrank to "run this script, relay its first line, never improvise".
- Adding `bin/distill-update.sh` and `channels/manifest.json` to `main` makes them part of the frozen surface from the bridge release on.
- Two new store files (`.channel`, `.command-path`) and one state file (`.major-notice`) are local metadata, not knowledge.

## Open questions

| Question | Owner | Needed by |
|---|---|---|
| Accept this ADR, including the choice of `beta/1.2` as the permanent host of the beta manifest (a later branch rename would strand installed beta clients) | Ivan | before cutting `v1.2.0-beta.1` |
| Codex and Antigravity have no updater; beta users on those clients only update by re-running the installer, or via a Claude session on the same store. Acceptable for the beta? | Ivan | before promotion |
| `install.ps1` consent has no timeout (`Read-Host`). Acceptable, or add a key-polling reader? | #79 follow-up | before a real cross-major payload exists |
