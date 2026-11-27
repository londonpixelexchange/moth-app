#!/bin/bash
# Copyright (c) 2026 T E Vaughan.
# SPDX-License-Identifier: GPL-3.0-or-later
# Licensed under GNU GPL version 3 or later. See LICENSE.

# Build a Developer ID release, then notarise it using a named Keychain profile.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
IDENTITY="${MOTH_SIGNING_IDENTITY:-Developer ID Application: Thom Vaughan (2DGZBJB93C)}"
RELEASE="$ROOT/Build/ReleaseSigned"
APP="$RELEASE/Moth.app"
case "${1:-build}" in
build)
 if ! git -C "$ROOT" diff --quiet HEAD -- || [ -n "$(git -C "$ROOT" ls-files --others --exclude-standard -- Moth Vendor scripts Moth.xcodeproj build.sh)" ]; then
  echo 'Commit tracked changes before creating a signed release.' >&2; exit 1
 fi
 if [[ "$(git -C "$ROOT" branch --show-current)" != main ]]; then
  echo 'Merge the release pull request and check out main before signing.' >&2; exit 1
 fi
 git -C "$ROOT" fetch origin main
 if [[ "$(git -C "$ROOT" rev-parse HEAD)" != "$(git -C "$ROOT" rev-parse origin/main)" ]]; then
  echo 'Release signing requires the exact merged origin/main commit. Fast-forward main first.' >&2; exit 1
 fi
 mkdir -p "$RELEASE"
 "$DEVELOPER_DIR/usr/bin/xcodebuild" -project "$ROOT/Moth.xcodeproj" -scheme Moth -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$ROOT/Build/SignedDerivedData" build \
  ARCHS=arm64 CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=2DGZBJB93C \
  "CODE_SIGN_IDENTITY=$IDENTITY" ENABLE_HARDENED_RUNTIME=YES CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS=--timestamp
 ditto "$ROOT/Build/SignedDerivedData/Build/Products/Release/Moth.app" "$APP"
 codesign --verify --deep --strict --verbose=2 "$APP"
 codesign -d --verbose=4 "$APP" 2> "$RELEASE/signature.txt"
 /usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist"
 echo "Signed app: $APP"
 ;;
notarize|package)
 : "${2:?Supply a notarisation Keychain profile name}"
 PROFILE="$2"
 VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
 BUILD=$(python3 - "$APP/Contents/Resources/BuildIdentity.json" <<'PYBUILD'
import json,sys
identity=json.load(open(sys.argv[1]))
assert identity['dirty'] is False, 'A release must identify a clean commit'
value=identity['shortCommit']
assert 7 <= len(value) <= 64 and all(c in '0123456789abcdef' for c in value)
print(value)
PYBUILD
)
 ZIP="$RELEASE/Moth-$VERSION-$BUILD-notary.zip"
 DMG="$RELEASE/Moth-$VERSION-$BUILD-arm64.dmg"
 if [[ "$1" == notarize ]]; then
 ditto -c -k --keepParent "$APP" "$ZIP"
 xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait --output-format json > "$RELEASE/app-notarization.json"
 python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["status"] == "Accepted"' "$RELEASE/app-notarization.json"
 APP_SUBMISSION=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["id"])' "$RELEASE/app-notarization.json")
 xcrun notarytool log "$APP_SUBMISSION" --keychain-profile "$PROFILE" "$RELEASE/app-notary-log.json"
 xcrun stapler staple "$APP"
 fi
 xcrun stapler validate "$APP"
 codesign --verify --deep --strict --verbose=2 "$APP"
 "$ROOT/scripts/make-dmg.sh" "$APP" "$DMG"
 codesign --force --sign "$IDENTITY" --timestamp "$DMG"
 xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait --output-format json > "$RELEASE/dmg-notarization.json"
 python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["status"] == "Accepted"' "$RELEASE/dmg-notarization.json"
 DMG_SUBMISSION=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["id"])' "$RELEASE/dmg-notarization.json")
 xcrun notarytool log "$DMG_SUBMISSION" --keychain-profile "$PROFILE" "$RELEASE/dmg-notary-log.json"
 xcrun stapler staple "$DMG"
 xcrun stapler validate "$DMG"
 spctl --assess --type execute --verbose=2 "$APP"
 spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
 shasum -a 256 "$DMG" > "$DMG.sha256"
 echo "Notarised disk image: $DMG"
 ;;
*) echo 'Usage: release.sh build | release.sh notarize KEYCHAIN_PROFILE | release.sh package KEYCHAIN_PROFILE' >&2;exit 2;;
esac
