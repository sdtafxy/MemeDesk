#!/usr/bin/env bash
# Build a runnable MemeDesk.app with nothing but the Xcode Command Line Tools.
#
#   xcode-select --install
#   ./Scripts/build.sh
#
# Output: dist/MemeDesk.app
set -euo pipefail

# 只装了 Xcode Command Line Tools 时，SwiftUI 的宏插件（libSwiftUIMacros.dylib）
# 不在编译器搜索路径里，构建会报 "plugin for module 'SwiftUIMacros' not found"。
# 若本机装了完整 Xcode，就把开发者目录切过去 —— 不用 sudo 改系统设置。
if [ -z "${DEVELOPER_DIR:-}" ] \
   && [ "$(xcode-select -p 2>/dev/null || true)" = "/Library/Developer/CommandLineTools" ] \
   && [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  echo "==> xcode-select 指向 CommandLineTools，改用 $DEVELOPER_DIR"
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MemeDesk"
BUILD_DIR="$ROOT/.build/release"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"

if ! command -v swift >/dev/null 2>&1; then
  echo "error: swift not found. Install the Xcode Command Line Tools: xcode-select --install" >&2
  exit 1
fi

echo "==> Building $APP_NAME (release)"
swift build -c release --package-path "$ROOT"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BUILD_DIR/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
  echo "    app icon: $(wc -c < "$CONTENTS/Resources/AppIcon.icns" | tr -d ' ') bytes"
else
  echo "warning: Resources/AppIcon.icns missing, run: python3 Scripts/make_icon.py" >&2
fi

# 程序内（欢迎页 / 菜单栏面板 / 设置页）也要读同一枚图标
if [ -f "$ROOT/Resources/AppIcon.png" ]; then
  cp "$ROOT/Resources/AppIcon.png" "$CONTENTS/Resources/AppIcon.png"
fi

if [ -d "$ROOT/Resources/Samples" ] && [ -n "$(ls -A "$ROOT/Resources/Samples" 2>/dev/null)" ]; then
  mkdir -p "$CONTENTS/Resources/Samples"
  cp -R "$ROOT/Resources/Samples/." "$CONTENTS/Resources/Samples/"
  echo "    bundled $(ls -1 "$ROOT/Resources/Samples" | wc -l | tr -d ' ') sample stickers"
fi

echo "==> Signing (ad-hoc)"
if command -v codesign >/dev/null 2>&1; then
  if [ -f "$ROOT/Resources/Entitlements.plist" ]; then
    codesign --force --deep --sign - --entitlements "$ROOT/Resources/Entitlements.plist" \
             --timestamp=none "$APP" || echo "warning: signing failed; the app still runs locally"
  else
    codesign --force --deep --sign - --timestamp=none "$APP" || true
  fi
else
  echo "warning: codesign not found, skipping"
fi

echo "==> Done: $APP"
