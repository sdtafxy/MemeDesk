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
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"

if ! command -v swift >/dev/null 2>&1; then
  echo "error: swift not found. Install the Xcode Command Line Tools: xcode-select --install" >&2
  exit 1
fi

# ⚠️ **必须双架构（universal）**。
#
# 只出 arm64 的话，Intel Mac 装上会直接"此应用无法在此 Mac 上运行" ——
# 而 README 只说"macOS 13 及以上"，Ventura 有大量 Intel 机器；
# CI 又跑在 arm64 runner 上，**永远发现不了**这个问题。
# 本项目零第三方依赖，双架构构建没有额外代价（只是产物大一倍）。
echo "==> Building $APP_NAME (release, arm64 + x86_64)"
swift build -c release --package-path "$ROOT" --arch arm64 --arch x86_64

# ⚠️ **不要相信 `.build/release` 这个软链**。
#
# 它指向的是"上一次构建"的产物目录。而本机/CI 上如果之前跑过一次**单架构**
# `swift build`，那次用的是旧的原生构建系统，产物落在别处；随后 `--arch` 多架构
# 构建走的是新版 `swiftbuild`，两处不是一个目录 —— 软链还指着旧的 arm64 那份。
# 实测（CI run 35830983650）：日志里明明有 "Create universal binary MemeDesk"、
# "Build succeeded"，`cp` 到的却是单架构文件，架构断言当场炸掉。
#
# 所以直接按**内容**找：`lipo` 同时报出 arm64 与 x86_64 的那个才是真产物。
# ⚠️ 必须跳过 `.dSYM`：符号文件里那份 DWARF **也是**双架构 Mach-O，名字还一样，
# 不管的话会把它当成可执行文件拷进 MacOS/（实测踩过一次）。
BIN=""
while IFS= read -r f; do
  case "$f" in *.dSYM/*) continue ;; esac
  archs="$(lipo -archs "$f" 2>/dev/null || true)"
  case "$archs" in
    *arm64*x86_64*|*x86_64*arm64*) BIN="$f"; break ;;
  esac
done < <(find "$ROOT/.build" -type f -name "$APP_NAME" 2>/dev/null)

if [ -z "$BIN" ]; then
  echo "error: 在 $ROOT/.build 里找不到双架构的 $APP_NAME。" >&2
  echo "       构建看似成功了，但产物不是 universal —— Intel Mac 装不上。" >&2
  exit 1
fi
echo "    binary: ${BIN#"$ROOT"/}"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN" "$CONTENTS/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# 双架构是"能装"的前提，别让它悄悄退化成单架构（上面那行参数被人删掉就会）。
archs="$(lipo -archs "$CONTENTS/MacOS/$APP_NAME" 2>/dev/null || true)"
case "$archs" in
  *arm64*x86_64*|*x86_64*arm64*) echo "    architectures: $archs" ;;
  *) echo "error: $APP_NAME 不是 universal —— lipo 报告 '$archs'" >&2
     echo "       Intel Mac 装不上。检查上面 swift build 的 --arch 参数。" >&2
     exit 1 ;;
esac

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
