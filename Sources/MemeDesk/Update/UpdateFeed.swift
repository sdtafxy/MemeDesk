import Foundation

/// 一次成功的更新检查所带回来的东西。
struct ReleaseInfo: Equatable, Sendable {
    /// 解析好的版本号（来自 tag，例如 `v0.1.0` → `0.1.0`）。
    let version: SemanticVersion
    let tag: String
    /// 对应的 GitHub Release 页面，用于「打不开更新时手动去看一眼」。
    let pageURL: URL
    /// Release 正文（就是 CHANGELOG 里那一段）。
    let notes: String
    /// 更新包（zip）的直链。
    ///
    /// **刻意可为空**：一个 Release 可能只有 dmg。判"要不要更新"应该先比版本号，
    /// 而不是先看有没有包 —— 否则遇到一个比当前版本更旧的、恰好又没有 zip 的 Release
    /// （0.0.2 就是），就会报"更新失败"，而正确结论其实是"已是最新"。
    let archiveURL: URL?
    let archiveSize: Int?
    /// `<zip>.sha256` 的直链，缺了就只能靠 TLS 兜底。
    let checksumURL: URL?
    /// `<zip>.ed25519` 的直链。**有它 + Info.plist 里配了公钥时才会强制验签**。
    let signatureURL: URL?

    var versionString: String { version.display }
    var archiveName: String { archiveURL?.lastPathComponent ?? "MemeDesk-\(versionString).zip" }
}

/// 检查更新时可能出的岔子。故意只表达"类型"，文案交给 UI 层，
/// 这样这个文件只依赖 Foundation，可以被单独编译出来跑测试。
enum UpdateFeedError: Error, Sendable {
    /// 非 200。附带状态码。
    case badStatus(Int)
    /// HTTP 403 且配额见底 —— GitHub 对匿名请求限流。
    case rateLimited
    /// 服务端返回的东西解不开。
    case malformedResponse
}

/// 更新相关的网络请求一律走这个 session。
///
/// **不要用 `URLSession.shared`**：它的 `URLCache` 会按 `Last-Modified` 做启发式
/// 新鲜度判断。校验和 / 签名文件被缓存住之后，就会出现"包变了、比对用的还是旧哈希"
/// —— 那是**误判为通过**，属于会放行坏包的方向。宁可不复用连接、不走缓存。
enum UpdateNetwork {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()
}

/// 从 GitHub Releases 读最新版本。
///
/// 选 GitHub Releases 当信息源，而不是自己维护一个 `update.json`：
/// 发版流程本来就会建 Release，**不需要多维护一份清单文件**，也就不会出现
/// 「清单忘了更新所以推不动」这种经典故障。
///
/// `/releases/latest` 天然排除 draft 与 prerelease，所以 Beta 版不会被推给用户。
enum UpdateFeed {

    /// GitHub API 要求带 User-Agent，否则直接 403。
    static func userAgent(appVersion: String) -> String {
        "MemeDesk/\(appVersion) (macOS)"
    }

    static func latestReleaseURL(repository: String) -> URL? {
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")
    }

    /// 返回 nil 表示「仓库里还没有任何正式 Release」，不是错误。
    static func latestRelease(repository: String,
                              appVersion: String,
                              session: URLSession = UpdateNetwork.session) async throws -> ReleaseInfo? {
        guard let url = latestReleaseURL(repository: repository) else {
            throw UpdateFeedError.malformedResponse
        }
        var request = URLRequest(url: url)
        request.setValue(userAgent(appVersion: appVersion), forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateFeedError.malformedResponse
        }
        switch http.statusCode {
        case 200:
            break
        case 404:
            return nil                       // 一个 Release 都还没有
        case 403, 429:
            throw UpdateFeedError.rateLimited
        default:
            throw UpdateFeedError.badStatus(http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let release = try? decoder.decode(GitHubRelease.self, from: data) else {
            throw UpdateFeedError.malformedResponse
        }
        guard !release.draft, !release.prerelease else { return nil }
        guard let version = SemanticVersion(release.tagName) else {
            throw UpdateFeedError.malformedResponse
        }

        let assets = release.assets
        // 没有 zip 也照常返回 —— 要不要更新由调用方先比版本号说了算。
        let archive = assets.first { $0.name.lowercased().hasSuffix(".zip") }
        guard let pageURL = URL(string: release.htmlUrl) else {
            throw UpdateFeedError.malformedResponse
        }

        func assetURL(suffix: String) -> URL? {
            guard let name = archive?.name else { return nil }
            return assets.first { $0.name == name + suffix }
                .flatMap { URL(string: $0.browserDownloadUrl) }
        }

        return ReleaseInfo(version: version,
                           tag: release.tagName,
                           pageURL: pageURL,
                           notes: (release.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                           archiveURL: archive.flatMap { URL(string: $0.browserDownloadUrl) },
                           archiveSize: archive?.size,
                           checksumURL: assetURL(suffix: ".sha256"),
                           signatureURL: assetURL(suffix: ".ed25519"))
    }

    // MARK: - 只解我们真正用到的字段

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlUrl: String
        let body: String?
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: String
            let size: Int
        }
    }
}
