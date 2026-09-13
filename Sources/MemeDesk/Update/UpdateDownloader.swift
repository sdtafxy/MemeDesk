import Foundation

enum UpdateDownloadError: Error, Sendable {
    case badStatus(Int)
    /// 这个 Release 没有 zip 资产。
    case archiveMissing
    /// 服务端没提供校验和，无从判断包是否完整。
    case checksumUnavailable
    case checksumMismatch(expected: String, actual: String)
    /// App 里配了公钥，但 Release 上没有签名文件。
    case signatureUnavailable
    case signatureInvalid
}

/// 把更新包拉下来，并校验。
enum UpdateDownloader {

    /// 流式下载到 `destination`。`progress` 回调是 0…1，节流到每 64 KB 一次
    /// —— 逐字节回调会在主线程上烧掉无谓的时间。
    static func download(_ url: URL,
                         to destination: URL,
                         session: URLSession = UpdateNetwork.session,
                         userAgent: String,
                         progress: (@Sendable (Double) -> Void)? = nil) async throws {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 60

        let (stream, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateDownloadError.badStatus(http.statusCode)
        }

        let expected = max(response.expectedContentLength, 0)
        var data = Data()
        if expected > 0 { data.reserveCapacity(Int(expected)) }

        var sinceReport = 0
        for try await byte in stream {
            data.append(byte)
            sinceReport += 1
            if sinceReport >= 65_536 {
                sinceReport = 0
                if expected > 0 { progress?(min(Double(data.count) / Double(expected), 1)) }
            }
        }

        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
        progress?(1)
    }

    /// 取一小段文本（`.sha256` / `.ed25519` 之类）。
    static func fetchText(_ url: URL,
                          session: URLSession = UpdateNetwork.session,
                          userAgent: String) async throws -> String? {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 下载 + 校验一条龙。`publicKeyBase64` 非空时**强制**验签。
    static func downloadVerified(_ release: ReleaseInfo,
                                 into directory: URL,
                                 session: URLSession = UpdateNetwork.session,
                                 userAgent: String,
                                 publicKeyBase64: String?,
                                 progress: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
        guard let archiveURL = release.archiveURL else {
            throw UpdateDownloadError.archiveMissing
        }
        let zipURL = directory.appendingPathComponent("MemeDesk-\(release.versionString).zip")
        try? FileManager.default.removeItem(at: zipURL)

        try await download(archiveURL, to: zipURL, session: session,
                           userAgent: userAgent, progress: progress)

        let payload = try Data(contentsOf: zipURL)

        // ① 哈希
        if let checksumURL = release.checksumURL,
           let text = try? await fetchText(checksumURL, session: session, userAgent: userAgent),
           let expected = UpdateIntegrity.parseChecksum(text) {
            let actual = UpdateIntegrity.sha256Hex(payload)
            guard actual == expected else {
                try? FileManager.default.removeItem(at: zipURL)
                throw UpdateDownloadError.checksumMismatch(expected: expected, actual: actual)
            }
        } else if publicKeyBase64?.isEmpty == false {
            // 要验签就得先确认包本身完整，否则等于放弃了哈希这道防线
            try? FileManager.default.removeItem(at: zipURL)
            throw UpdateDownloadError.checksumUnavailable
        }

        // ② 签名（配了公钥就必查）
        if let publicKeyBase64, !publicKeyBase64.isEmpty {
            guard let signatureURL = release.signatureURL,
                  let text = try? await fetchText(signatureURL, session: session, userAgent: userAgent),
                  let signature = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines))
            else {
                try? FileManager.default.removeItem(at: zipURL)
                throw UpdateDownloadError.signatureUnavailable
            }
            guard UpdateIntegrity.verify(signature: signature,
                                         payload: payload,
                                         publicKeyBase64: publicKeyBase64) else {
                try? FileManager.default.removeItem(at: zipURL)
                throw UpdateDownloadError.signatureInvalid
            }
        }

        return zipURL
    }
}
