# Release pages

Every version gets a page at `docs/releases/<version>/index.html`, published at
`https://tomacco.github.io/aura-distill/releases/<version>/` (DECISIONS.md D-2026-09-23-5).
The list of all releases is `docs/releases/index.html`.

Files:

| file | what it is |
|---|---|
| `index.html` | the release list, newest first |
| `_template/index.html` | one release page with every slot marked `<!-- SLOT: … -->` |
| `releases.css` | small additions on top of `../assets/ne-editorial.css` (list rows, copy button) |
| `releases.js` | EN/ES toggle, theme toggle, copy buttons |

`_template/` starts with an underscore, so GitHub Pages (Jekyll) does not publish it. Open it locally.

## How to make a release page

Do this in the release PR, before it merges. Pages only go live once they are on `main`
(D-2026-09-23-3).

1. **Copy the template.** `cp -R docs/releases/_template docs/releases/<version>` (for example
   `1.2.0-beta.1`). Paths inside the template (`../releases.css`, `../../assets/…`) already work from there.
2. **Collect the sources.** You need three things, and nothing else:
   - `CHANGELOG.md` → the `[Unreleased]` section that this release ships (Added, Changed, Fixed, Privacy);
   - its `### Known risks` entries (REVIEW-PROTOCOL.md rule 6);
   - the release PR: number, merged PRs, review rounds, reviewer models, release-gate verdict.
3. **Fill every slot.** Work top to bottom through the `<!-- SLOT: … -->` comments:
   - **version, date, channel.** The wordmark is the short version (`1.2.0`), and `-beta.N` goes in the
     badge and the h1. Keep only one channel badge.
   - **one-sentence answer** (h1). What changes for the reader, 20 words or fewer.
   - **lead.** Who should install this version and who should wait.
   - **stats** (optional). Only measured numbers with unit and n, linked in the evidence section.
     If you have none, delete the block. Never make a number up.
   - **what changes for you.** 3–5 numbered takeaways written from the reader's side.
   - **install / upgrade.** Keep the stable **or** the beta variant. For beta, copy the exact opt-in
     command from the release PR or the beta branch README; never guess a flag.
   - **known risks.** Required. One entry per `### Known risks` item: what, who it affects, what to do,
     tracking issue. If there are none, keep the "None known" note and delete the list.
   - **what stays the same.** Only claims you can point to in the diff.
   - **measured evidence.** Links to test runs, CI, research pages. Aggregates only.
   - **changelog excerpt.** The changelog section, copied as written.
   - **roll back / opt out.** How to go back and how to switch off new behaviour. Say whether knowledge
     files are touched.
   - **review trail.** One row per PR: rounds, author model, reviewer model, verdict. Include the release gate.
   - Every English block has a Spanish twin (`data-lang="es"`). Write it yourself in plain Spanish;
     do not insert machine translation at runtime.
4. **Check nothing is left.** This must print nothing:
   ```bash
   grep -n 'X\.Y\.Z\|YYYY-MM-DD\|DD-MM-YYYY\|NNN\|{{' docs/releases/<version>/index.html
   ```
5. **Add it to the list.** Also update the "Updated" date in the kicker and the footer date of `docs/releases/index.html`. In `docs/releases/index.html`, add one `<li>` at the **top** of `<ul class="rl">`:
   version, date, channel badge (`ne-badge` = stable, `ne-badge ne-badge--outline` = beta), a one-line
   summary in EN and ES, and a link to `<version>/`. Update the lead and the "current stable" stat when a
   stable version ships.
6. **Screenshot and look.** Take 360 px and 1280 px wide shots, in EN and ES, in light and dark (8 per page),
   and open every one. Check that nothing scrolls sideways at 360 px, the wordmark fits on one line,
   both languages are complete, and dark mode is readable. On macOS, headless Chrome will not lay out
   narrower than about 500 px, so render the 360 px shot inside a 360 px iframe:
   ```bash
   CH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
   PAGE="file://$PWD/docs/releases/<version>/index.html?lang=es"   # ?lang=en|es forces the language
   # 1280, light (preferredColorScheme=1) / dark (=0)
   "$CH" --headless=new --hide-scrollbars --blink-settings=preferredColorScheme=1 \
     --window-size=1280,3400 --virtual-time-budget=4000 --screenshot=/tmp/rel-1280-es-light.png "$PAGE"
   # 360: centred 360px iframe in a 600px window, then centre-crop to 360
   printf '<body style="margin:0"><iframe src="%s" width=360 height=5200 style="border:0;display:block;margin-left:120px"></iframe>' "$PAGE" > /tmp/frame.html
   "$CH" --headless=new --hide-scrollbars --blink-settings=preferredColorScheme=0 \
     --window-size=600,5200 --virtual-time-budget=4000 --screenshot=/tmp/rel-360-es-dark.png file:///tmp/frame.html
   sips -c 5200 360 /tmp/rel-360-es-dark.png
   ```
   Keep the screenshots out of the repo. Attach them to the PR if a reviewer needs them.
7. **Privacy gate.** Before you commit, check that the page contains no personal data:
   - no absolute home paths (`/Users/…`, `/home/…`, `C:\Users\…`) and no usernames or email addresses;
   - no knowledge-store content, file names, quotes, project or session identifiers. Real data appears
     only as counts, sizes, ratios and pass/fail (D-2026-09-23-4);
   - no tokens, keys or internal URLs.
   ```bash
   grep -nE '/Users/|/home/|C:\\Users|@[a-z0-9-]+\.[a-z]{2,}|sk-[A-Za-z0-9]|ghp_' docs/releases/<version>/index.html
   ```
   The grep must print nothing. Review anything it finds by hand, then read the page once more as a
   stranger would.
8. **Style.** Follow the monochrome editorial style already used by
   `docs/research/files-only-redesign.html`: no colour, no radii, no shadows, conclusion first, numbered
   sections, every caveat in a boxed note. Write short, plain sentences.

## Rules that do not bend

- The **Known risks** section is always there. "None known" is a valid answer, and an empty section is not.
- A page never claims a number, a review or a test that is not linked from the page.
- Do not make pages for versions before 1.2. The 1.1 line has one summary on the list page, because its
  patch numbers were bumped automatically on every merge.
