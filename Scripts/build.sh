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

# ⚠️ **只发 arm64**（0.1.8 起的既定策略，用户决定）。
#
# 0.1.7 发过一次双架构，代价是下载体积 1.76×（zip 0.76MB → 1.34MB）——
# 而 Intel 机器上 macOS 13 已经是最后一个受支持的版本，不值得为此让所有人多下一倍。
# Intel 用户改为从源码构建（README 里写明了）。
#
# 要改回双架构：把下面这行换成 `--arch arm64 --arch x86_64`，
# 并同步改 `Scripts/check_artifacts.sh` 里的期望架构。
echo "==> Building $APP_NAME (release, arm64)"
swift build -c release --package-path "$ROOT" --arch arm64

# ⚠️ **不要相信 `.build/release` 这个软链**。
#
# 它指向"上一次构建"的产物目录，而**构建系统会变**：CI runner 上朴素的
# `swift build -c release` 走旧的原生系统、`--arch …` 走新版 swiftbuild，
# 两处产物目录不同，软链还指着旧那份。0.1.7 第一次 CI 就是这么挂的：
# 日志里明明有 "Create universal binary" + "Build succeeded"，
# `cp` 到的却是单架构文件。
#
# 所以：先问 SwiftPM 要路径，再按**内容**确认；两条都不可信就在 `.build` 里按内容找。
# ⚠️ 两个必须跳过的：
#   · `*.dSYM/*` —— 里面的 DWARF 也是 Mach-O、basename 一模一样；
#   · `*Intermediate*` —— 中间产物同样是"架构正确"的，但它不是最终链接结果。
EXPECTED_ARCH="arm64"
BIN=""
CANDIDATE="$(swift build -c release --package-path "$ROOT" --arch arm64 --show-bin-path 2>/dev/null | tail -1)/$APP_NAME"
if [ -f "$CANDIDATE" ] && lipo -archs "$CANDIDATE" 2>/dev/null | grep -q "$EXPECTED_ARCH"; then
  BIN="$CANDIDATE"
else
  while IFS= read -r f; do
    case "$f" in *.dSYM/*|*Intermediate*) continue ;; esac
    if lipo -archs "$f" 2>/dev/null | grep -q "$EXPECTED_ARCH"; then BIN="$f"; break; fi
  done < <(find "$ROOT/.build" -type f -name "$APP_NAME" 2>/dev/null)
fi

if [ -z "$BIN" ]; then
  echo "error: 在 $ROOT/.build 里找不到 $EXPECTED_ARCH 的 $APP_NAME。" >&2
  echo "       构建看似成功了，但没有可用的产物。" >&2
  exit 1
fi
echo "    binary: ${BIN#"$ROOT"/}"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN" "$CONTENTS/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# ⚠️ `strip` 必须在 **codesign 之前** —— 签完名再改二进制会把签名弄坏。
#
# 去掉的是本地符号（Swift 泛型实例化堆出来的那一大堆名字），运行时不依赖它们；
# 调试符号在单独生成的 `.dSYM` 里，崩溃符号化不受影响。
# 实测：单 slice 2.23 MB → 0.96 MB（**−57%**），压缩进 zip 后仍有约 −32%。
# 符号表原本占二进制的一大半（`__LINKEDIT` 约 63%），不 strip 等于白背着。
before="$(wc -c < "$CONTENTS/MacOS/$APP_NAME" | tr -d ' ')"
strip -x "$CONTENTS/MacOS/$APP_NAME"
after="$(wc -c < "$CONTENTS/MacOS/$APP_NAME" | tr -d ' ')"
echo "    strip: $before → $after bytes（−$(( (before - after) * 100 / before ))%）"

# 架构是"能不能装"的前提，别让它悄悄变成别的（上面那行参数被人改掉就会）。
archs="$(lipo -archs "$CONTENTS/MacOS/$APP_NAME" 2>/dev/null || true)"
if [ "$archs" = "$EXPECTED_ARCH" ]; then
  echo "    architectures: $archs"
else
  echo "error: $APP_NAME 的架构是 '$archs'，期望 '$EXPECTED_ARCH'" >&2
  echo "       要改发布架构，请同时改本脚本的 EXPECTED_ARCH 与 Scripts/check_artifacts.sh。" >&2
  exit 1
fi

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
