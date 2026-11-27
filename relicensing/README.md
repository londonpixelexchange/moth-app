# GPLv3 transition record

Prepared for Moth 0.28.3 on 27 November 2026. The maintainer has confirmed that the
necessary contributor permissions for GPL-3.0-or-later are in place.

## Applied changes

- Full, unmodified GNU GPLv3 text, with GPL-3.0-or-later grants in notices,
  README files and Moth-owned source headers. Finder copyright metadata
  also identifies GPL-3.0-or-later. GitHub should detect GPLv3 from the root
  `LICENSE` after the change is applied and pushed; no separate licence
  setting has been changed.
- MIT vendored code, third-party notices and all font binaries retained.
- DCO sign-offs required in the contribution guide and PR checklist,
  alongside the existing cryptographic signature requirement. No CLA.
- Separate fork branding policy covering name, icon and logo. No charging
  restriction is added to the GPL code.
- Supplied proprietary Wumpus permission, with a definition of "Fork",
  placed both at the repository root and alongside the separate font files.
  The existing app packaging already copies those fonts as resources.
- Website homepage, metadata, credits and development/font documentation
  updated. Marked's full MIT notice is included for the website.
- Original code and font terms archived at versioned paths in both projects.
  Existing release notes and installer binaries remain unchanged.
- Moth 0.28.3 (build 72) release notes and changelog.

See [third-party audit](third-party-audit.md) and
[draft announcement](announcement.md).

## Application and release

Applied from the prepared patches against these unchanged base commits:

- App: `bdb8a8d0a359966c43185e5fcfec8e29860b29c2`
- Website: `bb12d55f24ebb60dd111302a169fa18acf7f8a0e`

The patches passed applicability checks in both working checkouts before
application. Their resulting files were checked against the validated
candidate. The preparation patches have been removed after application;
the working diffs are the reviewable change.

Follow the existing signed-commit and PR workflow. Add the unreleased entry
to the actual next release’s bundled and website release notes when its
version is selected. Preserve existing tags. Ship the signed, notarised
release with the exact corresponding source, then publish the website and
announcement together so the advertised GPL download matches the released
app. 

## Validation

After application, `./build.sh` passed in the app checkout and the resulting
`Build/Moth.app` was checked for all five notices, matching adjacent font
terms, fourteen separate Wumpus font resources and GPL copyright metadata.
The website was rebuilt in its actual checkout and its complete `npm test`
suite passed. Tracked changes and new licence files match the previously
tested candidate byte for byte. Shell syntax checks and `git diff --check`
also passed.

The candidate was previously validated in `/tmp/moth-relicensing-review/`:

- App release build passed; 511/511 existing app checks passed.
- Website `npm run build` and complete `npm test` passed, including editorial,
  links/anchors, release metadata, publisher and download checks.
- Generated homepage, credits and development copy reviewed, including
  metadata, font terms and historical links. No browser layout review was
  performed for these text-only edits.
- Bundle resources match all five repository notices byte for byte. All 14
  Wumpus font resources remain separate files; their adjacent permission
  matches `FONT-PERMISSION`. Both projects use the identical official GPL text.
- Vendored code, font sources and font binaries are unchanged. Terminal-core
  tests were not repeated because those files have no changes.
- `git diff --check` and patch applicability checked for both projects.

Canonical GPL text: https://www.gnu.org/licenses/gpl-3.0.txt

SHA-256: `3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986`

## Terms to keep clear

The GPL permits commercial redistribution. It does not require all sellers
to give source to the entire public for free; they must meet its source
provision requirements for the distribution method used. Recipients may
redistribute their copies under the GPL. See the
[GNU GPL FAQ](https://www.gnu.org/licenses/gpl-faq.html#DoesTheGPLAllowMoney)
and [GPLv3 section 6](https://www.gnu.org/licenses/gpl-3.0.html#section6).

The earlier Wumpus permission already grants standalone use, modification
and free redistribution of supplied copies. New wording must not be presented
as revoking those earlier grants. The candidate retains the exact old text
and limits the new permission to copies supplied under it. Someone holding
an older copy may still have broader rights to that copy. The app font grant
does not grant use of the website's webfonts or the retail font family.
