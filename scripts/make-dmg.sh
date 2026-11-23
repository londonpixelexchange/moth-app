#!/bin/bash
# Copyright (c) 2026 T E Vaughan.
# SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
# Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${1:?Supply the signed app path}"
: "${2:?Supply the output disk image path}"
APP="$1"
OUTPUT="$2"
codesign --verify --deep --strict "$APP"
DMGBUILD="${MOTH_DMGBUILD:-dmgbuild}"
command -v "$DMGBUILD" >/dev/null || {
    echo 'Install dmgbuild or set MOTH_DMGBUILD to its executable path.' >&2
    exit 1
}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/moth-dmg.XXXXXX")
MOUNT="$WORK/mount"
cleanup() {
    if [[ -f "$MOUNT/.DS_Store" || -d "$MOUNT/Moth.app" ]]; then
        hdiutil detach "$MOUNT" >/dev/null || return
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT
mkdir "$MOUNT"
"$DMGBUILD" -s "$ROOT/Packaging/dmg-settings.py" \
    -D "app=$APP" -D "background=$ROOT/Packaging/installer-background.tiff" \
    Moth "$WORK/installer.dmg"
hdiutil verify "$WORK/installer.dmg"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$WORK/installer.dmg"
if [[ ! -s "$MOUNT/.DS_Store" ]] || ! LC_ALL=C grep -aq 'backgroundImageAlias' "$MOUNT/.DS_Store"; then
    echo 'Installer is missing its Finder background reference.' >&2
    exit 1
fi
hdiutil detach "$MOUNT"
mv -f "$WORK/installer.dmg" "$OUTPUT"
