#!/usr/bin/env bash
# 版本号必须在三处一致 —— 不一致就直接失败。
#
#   ./Scripts/check_version.sh            # 只查三处是否互相一致
#   ./Scripts/check_version.sh v0.1.7     # additionally 断言 tag 与它们一致
#
# 为什么必须有这个：版本号是三处手改的，而**没有任何地方在运行时校验它**。
# 一旦 tag 和 Info.plist 对不上（打了 v0.1.7 却忘改 plist），会发生：
#   · Release 名叫 v0.1.7，包里的 App 却报 0.1.6；
#   · 更新器 `release.version > current` 永远成立 → **每次启动都提示装同一个更新**，
#     开了「自动安装」就是重启循环。
# 这类错误 CI 本来完全看不见（它只编译，从不比较版本号）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST="$ROOT/Resources/Info.plist"
PROJ="$ROOT/Xcode/project.yml"
CHANGELOG="$ROOT/CHANGELOG.md"

die() { echo "error: $*" >&2; exit 1; }

[ -f "$PLIST" ]     || die "找不到 $PLIST"
[ -f "$PROJ" ]      || die "找不到 $PROJ"
[ -f "$CHANGELOG" ] || die "找不到 $CHANGELOG"

plist="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null || true)"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST" 2>/dev/null || true)"
proj="$(grep -E '^[[:space:]]*MARKETING_VERSION:' "$PROJ" | head -1 | sed -E 's/.*"([^"]*)".*/\1/')"
proj_build="$(grep -E '^[[:space:]]*CURRENT_PROJECT_VERSION:' "$PROJ" | head -1 | sed -E 's/.*"([^"]*)".*/\1/')"
log="$(grep -m1 -E '^## \[' "$CHANGELOG" | sed -E 's/^## \[([^]]*)\].*/\1/')"

[ -n "$plist" ] || die "读不出 Info.plist 的 CFBundleShortVersionString"
[ -n "$proj" ]  || die "读不出 project.yml 的 MARKETING_VERSION"
[ -n "$log" ]   || die "CHANGELOG.md 里找不到 '## [x.y.z]' 标题"

echo "Info.plist      : $plist (build $build)"
echo "Xcode/project.yml: $proj (build $proj_build)"
echo "CHANGELOG 最新   : $log"

fail=0
[ "$plist" = "$proj" ] || { echo "error: Info.plist 与 project.yml 的版本号不一致" >&2; fail=1; }
[ "$plist" = "$log" ]  || { echo "error: Info.plist 与 CHANGELOG 最新一条不一致" >&2; fail=1; }
[ "$build" = "$proj_build" ] || { echo "error: CFBundleVersion 与 CURRENT_PROJECT_VERSION 不一致" >&2; fail=1; }
case "$build" in
  ''|*[!0-9]*) echo "error: CFBundleVersion 必须是纯数字（现在是 '$build'）" >&2; fail=1 ;;
esac

# 可选：把 tag 也纳入断言。发版时一定要传。
if [ -n "${1:-}" ]; then
  tag="${1#v}"
  echo "tag             : $1"
  [ "$tag" = "$plist" ] || { echo "error: tag $1 与 Info.plist 的 $plist 不一致 —— 这会造成无限更新提示" >&2; fail=1; }
fi

if [ "$fail" -ne 0 ]; then
  echo "版本号校验失败。" >&2
  exit 1
fi
echo "版本号一致 ✓"
