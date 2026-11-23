# Release builds

Moth targets Apple silicon Macs running macOS 13 or later. Its distribution bundle identifier is `dev.getmoth.Moth`.

1. Update the version and build number in the Xcode project.
2. Run `scripts/release.sh build` with the Developer ID Application identity available in Keychain. Override `MOTH_SIGNING_IDENTITY` when necessary.
3. Test `Build/ReleaseSigned/Moth.app`. For the isolated crash/relaunch test, set `MOTH_TEST_APP` to that app's absolute path and `MOTH_PRESERVE_SIGNATURE=1`, then run `python3 scripts/test-recovery-host.py`.
4. Install `dmgbuild` in a Python virtual environment and put its executable on `PATH`, or set `MOTH_DMGBUILD` to its absolute path. Run `scripts/release.sh notarize KEYCHAIN_PROFILE`, using a configured `notarytool` profile. Credentials stay in Keychain.
5. To revise only the installer artwork or layout, regenerate the backgrounds with `scripts/render-dmg-background.swift` and combine the 1× and 2× PNGs with `tiffutil -cathidpicheck`, then run `scripts/release.sh package KEYCHAIN_PROFILE`. This preserves the app signature and resubmits the disk image.
6. Review both notarisation logs in `Build/ReleaseSigned`, verify the mounted disk image, and retain its SHA-256 checksum. Publish the DMG only after verification. The notarisation ZIP is an intermediate submission, not a download artifact.

The release script preserves the local development app in `Build/Moth.app`. Signing uses hardened runtime and a secure timestamp. Both the app and disk image receive stapled notarisation tickets and Gatekeeper checks.
