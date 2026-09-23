#!/usr/bin/env bash
# 打一份「给更新器用」的 zip。
#
# 为什么更新走 zip 而不是 dmg：dmg 要先挂载、再拷贝、还要弹出，中间任何一步
# 被用户或系统打断都会留下半成品；zip 解压即可，`ditto` 一条命令就能原地覆盖。
# dmg 仍然照发 —— 首次安装的用户还是拖 dmg 最直观。
#
#   ./Scripts/build.sh && ./Scripts/make_zip.sh
#
# Output: dist/MemeDesk-<version>.zip
#         dist/MemeDesk-<version>.zip.sha256           （更新器会去 Release 上取）
#         dist/MemeDesk-<version>.zip.ed25519          （配了签名私钥时才产出）
#
# 签名（可选，但强烈建议）：
#   export MEMEDESK_UPDATE_SIGNING_KEY=/path/to/private-key.pem
# 私钥只在 CI 的 secret 里和你的离线备份里，**不要进仓库**。
set -euo pipefail

# 与 build.sh 同样的处理：xcode-select 指向 CommandLineTools 时切到完整 Xcode。
if [ -z "${DEVELOPER_DIR:-}" ] \
   && [ "$(xcode-select -p 2>/dev/null || true)" = "/Library/Developer/CommandLineTools" ] \
   && [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MemeDesk"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

if [ ! -d "$APP" ]; then
  echo "error: $APP not found. Run Scripts/build.sh first." >&2
  exit 1
fi

# ⚠️ 读不出就报错退出（理由见 make_dmg.sh 里同样的注释）。
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || true)"
if [ -z "$VERSION" ]; then
  echo "error: 读不出 $APP/Contents/Info.plist 的 CFBundleShortVersionString" >&2
  exit 1
fi
ZIP="$DIST/$APP_NAME-$VERSION.zip"

rm -f "$ZIP" "$ZIP.sha256" "$ZIP.ed25519"

# --keepParent 保证 zip 里是 "MemeDesk.app/…" 而不是把包里的文件摊平 ——
# 更新器靠它才能在解压目录里找到 .app。
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# 只写纯十六进制，不带文件名：更新器两种写法都能解析，纯哈希最不容易出错。
shasum -a 256 "$ZIP" | awk '{print $1}' > "$ZIP.sha256"

# ⚠️ 自校验：这个 .sha256 是 App 端**唯一**的完整性依据（公钥为空时不验签），
# 写歪了没人会发现 —— 包括发布链路自己。重算一遍比一比。
if [ "$(shasum -a 256 "$ZIP" | awk '{print $1}')" != "$(cat "$ZIP.sha256")" ]; then
  echo "error: $ZIP.sha256 与 $ZIP 对不上" >&2
  exit 1
fi

echo "==> Done: $ZIP ($(wc -c < "$ZIP" | tr -d ' ') bytes)"
echo "    sha256: $(cat "$ZIP.sha256")"

if [ -n "${MEMEDESK_UPDATE_SIGNING_KEY:-}" ]; then
  PYTHON="${PYTHON:-python3}"
  if ! "$PYTHON" -c 'import cryptography' >/dev/null 2>&1; then
    echo "error: 需要 python 的 cryptography 包才能签名：" >&2
    echo "       python3 -m pip install cryptography" >&2
    exit 1
  fi
  "$PYTHON" "$ROOT/Scripts/sign_update.py" "$MEMEDESK_UPDATE_SIGNING_KEY" "$ZIP"
  if [ ! -s "$ZIP.ed25519" ]; then
    echo "error: 签名跑完了但 $ZIP.ed25519 不存在或是空的" >&2
    exit 1
  fi
  echo "    ed25519: $ZIP.ed25519"
else
  echo "    (未签名：没有设置 MEMEDESK_UPDATE_SIGNING_KEY)"
fi
