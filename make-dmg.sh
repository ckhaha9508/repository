#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
BUILD_ARCH="${1:-universal}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")
if [[ "$BUILD_ARCH" == "native" ]]; then ARCH=$(uname -m); else ARCH="$BUILD_ARCH"; fi
case "$BUILD_ARCH" in native|universal|arm64|x86_64) ;; *) echo "Invalid architecture: $BUILD_ARCH" >&2; exit 2 ;; esac

APP="$ROOT/dist/Nest Launcher.app"
OUTPUT="$ROOT/dist/Nest-Launcher-${VERSION}-${ARCH}.dmg"
if [[ -e "$OUTPUT" ]]; then
    echo "Already exists: $OUTPUT (move it aside before rebuilding)" >&2
    exit 1
fi
bash "$ROOT/make-app.sh" release "$BUILD_ARCH"

STAGING=$(mktemp -d /private/tmp/nest-launcher-dmg.XXXXXX)
trap 'if [[ "$STAGING" == /private/tmp/nest-launcher-dmg.* && -d "$STAGING" ]]; then rm -rf "$STAGING"; fi' EXIT
ditto "$APP" "$STAGING/Nest Launcher.app"
cp "$ROOT/LICENSE" "$STAGING/LICENSE"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "Nest Launcher" -srcfolder "$STAGING" \
    -format UDZO -ov "$OUTPUT"
hdiutil verify "$OUTPUT"
echo "Created $OUTPUT"
