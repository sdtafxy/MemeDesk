import CryptoKit
import Foundation

/// 更新包的完整性 / 真实性校验。
///
/// 两级，强度不同，要分清楚：
/// - **SHA-256**：证明包没被截断或损坏，但**证明不了来源** —— 能改安装包的人
///   同样能改那个 `.sha256` 文件。属于"防损坏"，不是"防篡改"。
/// - **Ed25519**：用私钥签名、App 内用内置公钥验签，才能真正证明包是我们发的。
///   私钥只存在于发布的 CI 里（GitHub Actions secret），不在仓库、也不在 App 里。
///
/// 公钥配在 `Info.plist` 的 `MemeDeskUpdatePublicKey`。**一旦配了就强制验签**，
/// 拿不到签名文件就拒绝安装 —— 不会悄悄降级成只查哈希。
enum UpdateIntegrity {

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// 解析 `.sha256` 文件。同时容忍几种常见写法：
    /// 纯十六进制、`shasum` 的 `<hex>  <文件名>`、OpenSSL 的 `SHA256 (f) = <hex>`。
    static func parseChecksum(_ text: String) -> String? {
        for token in text.lowercased().split(whereSeparator: { !$0.isHexDigit })
        where token.count == 64 {
            return String(token)
        }
        return nil
    }

    /// Ed25519 验签。公钥是 Base64 编码的 32 字节 raw representation。
    static func verify(signature: Data, payload: Data, publicKeyBase64: String) -> Bool {
        guard let raw = Data(base64Encoded: publicKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines)),
              raw.count == 32,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
        else { return false }
        return key.isValidSignature(signature, for: payload)
    }
}
