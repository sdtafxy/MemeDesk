#!/usr/bin/env bash
# Wrap dist/MemeDesk.app into a distributable disk image.
#
#   ./Scripts/build.sh && ./Scripts/make_dmg.sh
#
# Output: dist/MemeDesk-<version>.dmg
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MemeDesk"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

if [ ! -d "$APP" ]; then
  echo "error: $APP not found. Run Scripts/build.sh first." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo 1.0.0)"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
STAGING="$DIST/dmg"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG"

rm -rf "$STAGING"
echo "==> Done: $DMG"
