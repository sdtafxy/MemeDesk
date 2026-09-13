#!/usr/bin/env python3
"""用 Ed25519 私钥给更新包签名。

    python3 Scripts/sign_update.py <private-key.pem> <path/to/MemeDesk-x.y.z.zip>

产出 `<zip>.ed25519`，内容是 Base64 的签名。App 端用 Info.plist 里的
`MemeDeskUpdatePublicKey`（同样是 Base64，32 字节 raw）验签 —— 见
`Sources/MemeDesk/Update/UpdateIntegrity.swift`。

生成密钥对（只需要做一次，私钥**不要进仓库**）：

    python3 Scripts/sign_update.py --generate ~/memedesk-update-key.pem

命令会把私钥写到文件、并把配套的公钥打印出来，把它填进
Resources/Info.plist 的 MemeDeskUpdatePublicKey。
CI 里再把私钥全文放进仓库 secret `MEMEDESK_UPDATE_SIGNING_KEY`。
"""
import base64
import pathlib
import sys


def generate(path: str) -> int:
    try:
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.asymmetric import ed25519
    except ImportError:
        print("需要 cryptography： python3 -m pip install cryptography", file=sys.stderr)
        return 1

    key = ed25519.Ed25519PrivateKey.generate()
    pem = key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    target = pathlib.Path(path).expanduser()
    target.write_bytes(pem)
    target.chmod(0o600)

    raw = key.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    print(f"私钥已写入 {target}（权限 600）")
    print("把下面这行填进 Resources/Info.plist 的 MemeDeskUpdatePublicKey：")
    print()
    print(f"    {base64.b64encode(raw).decode()}")
    print()
    print("再把私钥文件内容整个放进 GitHub 仓库 secret：MEMEDESK_UPDATE_SIGNING_KEY")
    return 0


def sign(key_path: str, payload_path: str) -> int:
    try:
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.asymmetric import ed25519
    except ImportError:
        print("需要 cryptography： python3 -m pip install cryptography", file=sys.stderr)
        return 1

    pem = pathlib.Path(key_path).expanduser().read_bytes()
    key = serialization.load_pem_private_key(pem, password=None)
    if not isinstance(key, ed25519.Ed25519PrivateKey):
        print("这不是 Ed25519 私钥", file=sys.stderr)
        return 1

    payload = pathlib.Path(payload_path).read_bytes()
    signature = key.sign(payload)
    out = pathlib.Path(str(payload_path) + ".ed25519")
    out.write_text(base64.b64encode(signature).decode() + "\n", encoding="utf-8")
    print(f"已签名 → {out}")
    return 0


def main() -> int:
    args = sys.argv[1:]
    if len(args) == 2 and args[0] == "--generate":
        return generate(args[1])
    if len(args) == 2:
        return sign(args[0], args[1])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
