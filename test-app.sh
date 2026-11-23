#!/bin/bash
# Copyright (c) 2026 Thomas Edward Vaughan, trading as London Pixel Exchange.
# SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
# Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
MOTH_VALIDATION_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/moth-validation.XXXXXX")"
trap 'rm -rf "$MOTH_VALIDATION_ROOT"' EXIT
MOTH_VALIDATION_APP="$MOTH_VALIDATION_ROOT/Moth Validation.app"
MOTH_VALIDATION_RESULT="${MOTH_TEST_RESULT:-$ROOT/TestResults.json}"
ditto "${MOTH_TEST_APP:-$ROOT/Build/Moth.app}" "$MOTH_VALIDATION_APP"
/usr/libexec/PlistBuddy -c "Set CFBundleIdentifier com.thom.moth.validation.$$" "$MOTH_VALIDATION_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set CFBundleName Moth Validation' "$MOTH_VALIDATION_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set CFBundleDisplayName Moth Validation' "$MOTH_VALIDATION_APP/Contents/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Add CFBundleDisplayName string Moth Validation' "$MOTH_VALIDATION_APP/Contents/Info.plist"
codesign --force --deep --sign - --preserve-metadata=flags "$MOTH_VALIDATION_APP"
mkdir -p "$MOTH_VALIDATION_ROOT/results"
MOTH_LAUNCHED_RESULT="$MOTH_VALIDATION_ROOT/results/TestResults.json"
touch "$MOTH_VALIDATION_ROOT/started"
# Use the same macOS launch path as a user opening the app, including foreground activation.
/usr/bin/open -n -W "$MOTH_VALIDATION_APP" --stdout "$MOTH_VALIDATION_ROOT/stdout.log" --stderr "$MOTH_VALIDATION_ROOT/stderr.log" --env "MOTH_TEST_RESULT=$MOTH_LAUNCHED_RESULT" --args --self-test "$@"
cat "$MOTH_VALIDATION_ROOT/stdout.log" "$MOTH_VALIDATION_ROOT/stderr.log"
if [[ -s "$MOTH_LAUNCHED_RESULT" ]]; then
  cp "$MOTH_VALIDATION_ROOT/results/"* "$(dirname "$MOTH_VALIDATION_RESULT")/"
  if [[ "$MOTH_VALIDATION_RESULT" != "$(dirname "$MOTH_VALIDATION_RESULT")/TestResults.json" ]]; then cp "$MOTH_LAUNCHED_RESULT" "$MOTH_VALIDATION_RESULT"; fi
fi
# The launch result lives in a fresh mktemp directory. Checking that file avoids
# a same-second timestamp race in macOS Bash's -nt operator for fast checks.
if [[ ! -s "$MOTH_LAUNCHED_RESULT" || ! -s "$MOTH_VALIDATION_RESULT" ]]; then
  printf 'Validation exited without writing a fresh result.\n' >&2
  exit 1
fi

python3 - "$MOTH_VALIDATION_RESULT" <<'PYTEST'
import json, sys
with open(sys.argv[1]) as f:
    checks = json.load(f)
failed = [name for name, passed in checks.items() if passed is not True]
print(f"{len(checks)-len(failed)}/{len(checks)} app checks passed")
if failed:
    print("Failed: " + ", ".join(failed))
    sys.exit(1)
PYTEST
