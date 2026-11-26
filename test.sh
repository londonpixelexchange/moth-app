#!/bin/bash
# Copyright (c) 2026 T E Vaughan.
# SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
# Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ ! -x "$ROOT/Build/Moth.app/Contents/MacOS/Moth" ]]; then "$ROOT/build.sh"; fi
MOTH_TEST_RESULT="${MOTH_TEST_RESULT:-$ROOT/test-artifacts/TestResults.json}"
export MOTH_TEST_RESULT
"$ROOT/test-app.sh"
cat "$MOTH_TEST_RESULT"
"$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" test --package-path "$ROOT/Vendor/SwiftTerm" --scratch-path "$ROOT/Build/CoreTests" --filter 'MothAlternateHistoryTests|MothSearchTests|ImageTrackingTests|ImageTests|ColorTests|SelectionTests|UnicodeTests|KittyGraphicsLifecycleTests'
