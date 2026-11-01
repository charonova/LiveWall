#!/bin/bash
# Builds dist/LiveWall.zip for a GitHub release: universal (Apple silicon and Intel), plus its
# SHA-256. With a Developer ID it's signed for distribution and notarized, so it opens without
# a warning however it was downloaded:
#
#   LIVEWALL_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   LIVEWALL_NOTARY_PROFILE=livewall   # once: xcrun notarytool store-credentials livewall
#
# Without them the app is signed ad hoc, which runs fine when installed with the README's
# Terminal command; a browser download needs "Open Anyway" once (see the README).
#
# The zip is always named LiveWall.zip, with no version: the README's install command downloads
# releases/latest/download/LiveWall.zip, and the app's updater looks for exactly that name.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
UNIVERSAL=1 ./scripts/build.sh
APP="build/LiveWall.app"
IDENTITY="${LIVEWALL_IDENTITY:-}"

if [ -n "$IDENTITY" ]; then
    codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP"
fi
codesign --verify --strict --deep "$APP"
BINARY="$APP/Contents/MacOS/LiveWall"
echo "LiveWall: $(lipo -archs "$BINARY"), macOS $(vtool -show-build "$BINARY" | awk '/minos/ {print $2; exit}')+"

mkdir -p dist
ZIP="dist/LiveWall.zip"
rm -f "$ZIP"
# No resource forks or extended attributes: as AppleDouble "._" files they'd land inside the
# bundle when unzipped by anything but ditto or Archive Utility, and break its signature.
ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ZIP"

if [ -n "$IDENTITY" ] && [ -n "${LIVEWALL_NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$ZIP" --keychain-profile "$LIVEWALL_NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
    ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ZIP"
    spctl --assess --type execute --verbose "$APP"
fi

(cd dist && shasum -a 256 LiveWall.zip > LiveWall.zip.sha256)
echo "LiveWall $VERSION → $ZIP ($(du -h "$ZIP" | cut -f1)), $(cut -c1-16 dist/LiveWall.zip.sha256)…"
