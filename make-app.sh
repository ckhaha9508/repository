#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
CONFIG="${1:-debug}"
BUILD_ARCH="${2:-native}"

case "$CONFIG" in
    release|debug) ;;
    *) echo "Usage: $0 [debug|release] [native|universal|arm64|x86_64]" >&2; exit 2 ;;
esac

BUILD_FLAGS=(-c "$CONFIG")
case "$BUILD_ARCH" in
    native) ;;
    universal) BUILD_FLAGS+=(--arch arm64 --arch x86_64) ;;
    arm64|x86_64) BUILD_FLAGS+=(--arch "$BUILD_ARCH") ;;
    *) echo "Invalid architecture: $BUILD_ARCH" >&2; exit 2 ;;
esac

SWIFT_BIN="${SWIFT_BIN:-/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift}"
SWIFTUI_MACROS_PLUGIN="${SWIFTUI_MACROS_PLUGIN:-/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib}"

if [[ -x "$SWIFT_BIN" && -f "$SWIFTUI_MACROS_PLUGIN" ]]; then
    export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
    BUILD_FLAGS+=(-Xswiftc -load-plugin-library -Xswiftc "$SWIFTUI_MACROS_PLUGIN")
else
    SWIFT_BIN=$(command -v swift)
fi
"$SWIFT_BIN" build "${BUILD_FLAGS[@]}"

BIN="$("$SWIFT_BIN" build "${BUILD_FLAGS[@]}" --show-bin-path)/NestLauncher"
if [[ "$BUILD_ARCH" == "universal" ]]; then
    BUILT_ARCHS=" $(lipo "$BIN" -archs) "
    if [[ "$BUILT_ARCHS" != *" arm64 "* || "$BUILT_ARCHS" != *" x86_64 "* ]]; then
        echo "Universal build is missing an architecture: $BUILT_ARCHS" >&2
        exit 1
    fi
fi

APP="$ROOT/dist/Nest Launcher.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/NestLauncher"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

cp "$ROOT/Resources/NestLauncher.icns" "$APP/Contents/Resources/NestLauncher.icns"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE"
ditto "$(dirname "$BIN")/NestLauncher_NestLauncher.bundle" "$APP/Contents/Resources/NestLauncher_NestLauncher.bundle"

codesign --force --deep --sign - "$APP"
echo "Created $APP"
