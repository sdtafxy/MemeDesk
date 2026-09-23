#!/usr/bin/env bash
# 发布产物自检。
#
#   ./Scripts/check_artifacts.sh
#
# 为什么需要：make_dmg.sh / make_zip.sh 是**唯一**的产出点，而产出之后
# 没有任何人复核过。历史上真出过这些事：产物只有 arm64 却写着支持 macOS 13；
# zip 顶层多套一层目录（更新器就找不到 .app）；sha256 与 zip 对不上。
# 这些在 arm64 的 CI runner 上全都"看起来绿"。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/MemeDesk.app"
PLIST="$APP/Contents/Info.plist"

fail=0
ok()   { echo "  ✓ $1"; }
bad()  { echo "  ✗ $1" >&2; fail=1; }
need() { if [ "$1" = 1 ]; then ok "$2"; else bad "$2"; fi; }

[ -d "$APP" ] || { echo "error: 找不到 ${APP}，先跑 Scripts/build.sh" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null || true)"
[ -n "$VERSION" ] || { echo "error: 读不出包内版本号" >&2; exit 1; }
echo "MemeDesk $VERSION"

# 1) 双架构 —— Intel Mac 能不能装，只看这一条。
archs="$(lipo -archs "$APP/Contents/MacOS/MemeDesk" 2>/dev/null || true)"
case "$archs" in
  *arm64*x86_64*|*x86_64*arm64*) need 1 "universal（${archs}）" ;;
  *) need 0 "universal —— lipo 报告 '$archs'，Intel Mac 装不上" ;;
esac

# 2) 二进制的最低系统版本要和 Info.plist 说的一致。
minos="$(otool -l "$APP/Contents/MacOS/MemeDesk" 2>/dev/null \
         | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print $2; exit}')"
lsmin="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST" 2>/dev/null || true)"
if [ -n "$minos" ] && [ "$minos" = "$lsmin" ]; then ok "最低系统 ${minos}（与 LSMinimumSystemVersion 一致）"
else bad "最低系统：二进制 $minos vs Info.plist $lsmin"; fi

# 3) 三个产物都在。
dmg="$DIST/MemeDesk-$VERSION.dmg"
zip="$DIST/MemeDesk-$VERSION.zip"
for f in "$dmg" "$zip" "$zip.sha256"; do
  [ -s "$f" ] && ok "$(basename "$f") ($(wc -c < "$f" | tr -d ' ') bytes)" || bad "缺少或为空：$(basename "$f")"
done

# 4) zip 顶层必须是 MemeDesk.app/（更新器靠它解压后找得到 .app）。
if [ -s "$zip" ]; then
  top="$(unzip -Z1 "$zip" 2>/dev/null | head -1)"
  [ "$top" = "MemeDesk.app/" ] && ok "zip 顶层是 MemeDesk.app/" || bad "zip 顶层是 '$top'，应为 'MemeDesk.app/'"
fi

# 5) sha256 得真的对得上。
if [ -s "$zip" ] && [ -s "$zip.sha256" ]; then
  want="$(cat "$zip.sha256")"
  got="$(shasum -a 256 "$zip" | awk '{print $1}')"
  [ "$want" = "$got" ] && ok "sha256 与 zip 一致" || bad "sha256 对不上：文件里是 ${want}，实际是 ${got}"
fi

# 6) dmg 能挂上。
if [ -s "$dmg" ]; then
  if hdiutil verify "$dmg" >/dev/null 2>&1; then ok "dmg 校验通过"; else bad "dmg 校验失败"; fi
fi

# 7) 签名文件的存在性必须和公钥配置一致（两头不能只做一半）。
key="$(/usr/libexec/PlistBuddy -c 'Print :MemeDeskUpdatePublicKey' "$PLIST" 2>/dev/null || true)"
if [ -n "$key" ]; then
  [ -s "$zip.ed25519" ] && ok "已配公钥且签了名" || bad "配了公钥但没出 .ed25519 —— App 会对每个更新硬失败"
else
  [ -e "$zip.ed25519" ] && bad "没配公钥却出了 .ed25519（没人会验，属于装饰）" || ok "未配公钥、未签名（自洽）"
fi

if [ "$fail" -ne 0 ]; then echo "产物自检失败。" >&2; exit 1; fi
echo "产物自检通过 ✓"
