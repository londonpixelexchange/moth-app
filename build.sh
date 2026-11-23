#!/bin/bash
# Copyright (c) 2026 T E Vaughan.
# SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
# Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
MOTH_DERIVED_DATA="${MOTH_DERIVED_DATA:-$ROOT/Build/DerivedData}"
MOTH_ARCH="$(uname -m)"
"$DEVELOPER_DIR/usr/bin/xcodebuild" -project "$ROOT/Moth.xcodeproj" -scheme Moth -configuration Release -destination "platform=macOS,arch=$MOTH_ARCH" -derivedDataPath "$MOTH_DERIVED_DATA" build CODE_SIGNING_ALLOWED=NO "ARCHS=$MOTH_ARCH"
mkdir -p "$ROOT/Build"
MOTH_STAGED_APP="$ROOT/Build/.Moth-staged-$$.app"
ditto "$MOTH_DERIVED_DATA/Build/Products/Release/Moth.app" "$MOTH_STAGED_APP"
codesign --force --deep --sign - "$MOTH_STAGED_APP"
# Preserve a running build's executable rather than replacing its mapped file.
if [[ -d "$ROOT/Build/Moth.app" ]]; then
  mkdir -p "$ROOT/Build/Previous"
  mv "$ROOT/Build/Moth.app" "$ROOT/Build/Previous/Moth-$(date +%Y%m%d-%H%M%S)-$$.app"
fi
mv "$MOTH_STAGED_APP" "$ROOT/Build/Moth.app"
# Register the final stable location after moving the signed bundle into place.
# Archived running builds must not become Launch Services' preferred icon source.
touch "$ROOT/Build/Moth.app"
"/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister" -f "$ROOT/Build/Moth.app"
printf '\nBuilt: %s\n' "$ROOT/Build/Moth.app"
