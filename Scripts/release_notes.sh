#!/usr/bin/env bash
# 从 CHANGELOG.md 抽出指定版本的发布说明，写到文件（或 stdout）。
#
#   ./Scripts/release_notes.sh 0.1.7 [outfile]
#
# ⚠️ 抽不到就**非零退出**。这一点是重点：
# 老写法是一条 `awk | sed` 的直接重定向，CHANGELOG 里没有 `## [` 标题、
# 或者整个文件缺失，管线都会**安静地写出 0 字节并返回 0**，于是
# `softprops/action-gh-release` 会发布一个**正文为空的 Release**，不报警不失败。
# 这里补三样：`pipefail`、非空检查、标题必须带版本号。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHANGELOG="$ROOT/CHANGELOG.md"
VERSION="${1#v}"
OUT="${2:-}"

die() { echo "error: $*" >&2; exit 1; }

[ -n "$VERSION" ]   || die "用法: release_notes.sh <version|vX.Y.Z> [outfile]"
[ -f "$CHANGELOG" ] || die "找不到 $CHANGELOG"

# 只取最新那一段：遇到下一个 `## [` 标题就停。
# 标题里的 [x.y.z] 是 Keep-a-Changelog 的链接引用写法，单看正文没有链接定义，
# 所以要脱掉方括号 —— 但**版本号必须留下**（老写法 `## [^]]*] - ` 把版本号整个吃掉了）。
notes="$(awk 'BEGIN{on=0} /^## \[/{if (on) exit; on=1} on{print}' "$CHANGELOG" \
          | sed -e '1s/^## \[\([^]]*\)\] - /## \1 — /')"

if [ -z "${notes//[[:space:]]/}" ]; then
  die "CHANGELOG.md 里抽不到任何发布说明（没有 '## [' 标题，或文件是空的）"
fi
if ! printf '%s\n' "$notes" | head -1 | grep -q "^## ${VERSION} "; then
  die "抽到的不是 ${VERSION} 那一段（标题是：$(printf '%s' "$notes" | head -1)）—— 版本号是不是又忘了改？"
fi

if [ -n "$OUT" ]; then
  printf '%s\n' "$notes" > "$OUT"
  # ⚠️ 变量后面紧跟中文全角字符时**必须**写成 `${OUT}`。写成 `$OUT（` 会被
  # bash 把多字节字符的字节吞进变量名里，报一个莫名其妙的 `unbound variable`。
  echo "已写出 ${OUT}（$(printf '%s' "$notes" | wc -l | tr -d ' ') 行）"
else
  printf '%s\n' "$notes"
fi
