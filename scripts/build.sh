#!/bin/bash
# Builds LiveWall.app into ./build without needing Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."

# UNIVERSAL=1 builds for Intel Macs too (releases do).
ARCHS=()
[ "${UNIVERSAL:-0}" = 1 ] && ARCHS=(--arch arm64 --arch x86_64)
# ${ARCHS[@]+…}: macOS's bash 3.2 calls an empty array unbound under `set -u`.
swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/LiveWall"

APP="build/LiveWall.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LiveWall"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --options runtime --sign - "$APP" >/dev/null
echo "Built $(pwd)/$APP"
