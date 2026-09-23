#!/usr/bin/env bash
# 更新包的签名/验签配置必须**两头一致** —— 一边配了另一边没配，就会出事。
#
# 用发版环境变量一起跑：
#   MEMEDESK_UPDATE_SIGNING_KEY=… ./Scripts/check_update_signing.sh
#
# 两个方向的坑：
#   · Info.plist 配了公钥、CI 却没有私钥 → `make_zip.sh` 不签名 → App 端对**每一个**
#     更新都硬失败在 `signatureUnavailable`（不降级，这是有意的），用户再也更不了。
#   · 有私钥但公钥是空串 → 签出来的 `.ed25519` 没人会验，是**装饰**：
#     App 只查 SHA-256，被篡改的包照样装得上。
# 现在两边的状态是"都没配"，属于自洽；这个脚本保证以后不会只改一半。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST="$ROOT/Resources/Info.plist"

key="$(/usr/libexec/PlistBuddy -c 'Print :MemeDeskUpdatePublicKey' "$PLIST" 2>/dev/null || true)"
has_private=0
[ -n "${MEMEDESK_UPDATE_SIGNING_KEY:-}" ] && has_private=1
has_public=0
[ -n "$key" ] && has_public=1

if [ "$has_private" = 1 ] && [ "$has_public" = 0 ]; then
  echo "error: 提供了签名私钥，但 Info.plist 的 MemeDeskUpdatePublicKey 是空的。" >&2
  echo "       这样签出来的 .ed25519 没有任何 App 会验证 —— 等于白签。" >&2
  echo "       要么填上公钥，要么别传 MEMEDESK_UPDATE_SIGNING_KEY。" >&2
  exit 1
fi

if [ "$has_public" = 1 ] && [ "$has_private" = 0 ]; then
  echo "error: Info.plist 配了验签公钥，但这次构建没有签名私钥。" >&2
  echo "       发布出去之后，App 会对每一个更新硬失败在 signatureUnavailable。" >&2
  echo "       给仓库配好 MEMEDESK_UPDATE_SIGNING_KEY，或者把公钥清空。" >&2
  exit 1
fi

if [ "$has_public" = 1 ]; then
  echo "更新签名：已启用（公钥 ${#key} 字符，私钥已提供）✓"
else
  echo "更新签名：未启用（公钥为空、无私钥）—— 只查 SHA-256，两头自洽 ✓"
fi
