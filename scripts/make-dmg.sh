#!/bin/bash
# Copyright (c) 2026 Thomas Edward Vaughan, trading as London Pixel Exchange.
# SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
# Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${1:?Supply the signed app path}"
: "${2:?Supply the output disk image path}"
APP="$1"
OUTPUT="$2"
codesign --verify --deep --strict "$APP"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/moth-dmg.XXXXXX")
MOUNT="$WORK/mount"
cleanup(){ if mount | grep -Fq " on $MOUNT ("; then hdiutil detach "$MOUNT" >/dev/null || true; fi; rm -rf "$WORK"; }
trap cleanup EXIT
mkdir -p "$WORK/stage/.background" "$MOUNT"
ditto "$APP" "$WORK/stage/Moth.app"
ln -s /Applications "$WORK/stage/Applications"
cp "$ROOT/Packaging/installer-background.tiff" "$WORK/stage/.background/installer-background.tiff"
cp "$APP/Contents/Resources/Moth.icns" "$WORK/stage/.VolumeIcon.icns"
SetFile -a C "$WORK/stage"
hdiutil create -volname Moth -srcfolder "$WORK/stage" -format UDRW "$WORK/writable.dmg"
hdiutil attach -readwrite -nobrowse -mountpoint "$MOUNT" "$WORK/writable.dmg"
osascript "$ROOT/Packaging/configure-dmg.applescript" "$MOUNT"
sync
hdiutil detach "$MOUNT"
hdiutil convert "$WORK/writable.dmg" -format UDZO -ov -o "$OUTPUT"
