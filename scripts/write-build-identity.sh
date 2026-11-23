#!/bin/bash
# Copyright (c) 2026 Thomas Edward Vaughan, trading as London Pixel Exchange.
# SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
# Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

# Xcode runs this after copying resources and before code signing.
set -euo pipefail
MOTH_SOURCE_ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
MOTH_COMMIT="$(git -C "$MOTH_SOURCE_ROOT" rev-parse HEAD)"
MOTH_SHORT_COMMIT="$(git -C "$MOTH_SOURCE_ROOT" rev-parse --short=12 HEAD)"
MOTH_DIRTY=false
if ! git -C "$MOTH_SOURCE_ROOT" diff --quiet HEAD -- || [ -n "$(git -C "$MOTH_SOURCE_ROOT" ls-files --others --exclude-standard -- Moth Vendor scripts Moth.xcodeproj build.sh)" ]; then MOTH_DIRTY=true; fi
MOTH_IDENTITY_PATH="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/BuildIdentity.json"
mkdir -p "$(dirname "$MOTH_IDENTITY_PATH")"
printf '{"commit":"%s","shortCommit":"%s","dirty":%s}\n' "$MOTH_COMMIT" "$MOTH_SHORT_COMMIT" "$MOTH_DIRTY" > "$MOTH_IDENTITY_PATH"
