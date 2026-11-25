# Release builds

Moth targets Apple silicon Macs running macOS 13 or later. Its distribution bundle identifier is `dev.getmoth.Moth`.

1. Update the version, build number and bundled release notes on a feature branch. Open a pull request, wait for all required checks and reviews, and squash-merge it. Use a one-line Conventional Commit title. Fetch and fast-forward the local `main` checkout to the merged commit before building. Administrators must also use pull requests; direct pushes to `main` are blocked.
2. Run `scripts/release.sh build` with the Developer ID Application identity available in Keychain. Override `MOTH_SIGNING_IDENTITY` when necessary.
3. Test `Build/ReleaseSigned/Moth.app`. For the isolated crash/relaunch test, set `MOTH_TEST_APP` to that app's absolute path and `MOTH_PRESERVE_SIGNATURE=1`, then run `python3 scripts/test-recovery-host.py`.
4. Install `dmgbuild` in a Python virtual environment and put its executable on `PATH`, or set `MOTH_DMGBUILD` to its absolute path. Run `scripts/release.sh notarize KEYCHAIN_PROFILE`, using a configured `notarytool` profile. Credentials stay in Keychain.
5. To revise only the installer artwork or layout, regenerate the backgrounds with `scripts/render-dmg-background.swift` and combine the 1× and 2× PNGs with `tiffutil -cathidpicheck`, then run `scripts/release.sh package KEYCHAIN_PROFILE`. This preserves the app signature and resubmits the disk image.
6. Review both notarisation logs in `Build/ReleaseSigned`, verify the mounted disk image, and retain its SHA-256 checksum. Publish the DMG only after verification. The notarisation ZIP is an intermediate submission, not a download artifact.

The release script preserves the local development app in `Build/Moth.app`. Signing uses hardened runtime and a secure timestamp. Both the app and disk image receive stapled notarisation tickets and Gatekeeper checks.

The signed build and publisher require the app checkout to match `origin/main`
exactly. Build after the release PR has merged: a squash merge creates a new
commit, and that exact commit must be recorded in the signed app. The publisher
only pushes the signed version tag for this repository, never app source commits.
Version tags cannot be moved or deleted.
