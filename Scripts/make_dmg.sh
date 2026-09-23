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

# ⚠️ 读不出就**报错退出**，不要回退一个假版本号。
# 以前这里回退 `1.0.0`、make_zip.sh 回退 `0.0.0`，同一个 release 里两个产物
# 文件名会差一个版本，而且掩盖了"Info.plist 坏了"这个真问题。
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || true)"
if [ -z "$VERSION" ]; then
  echo "error: 读不出 $APP/Contents/Info.plist 的 CFBundleShortVersionString" >&2
  exit 1
fi
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
# 自校验：产物得真的挂得上，别把坏 dmg 发出去。
hdiutil verify "$DMG" >/dev/null
echo "==> Done: $DMG ($(wc -c < "$DMG" | tr -d ' ') bytes, verify OK)"
