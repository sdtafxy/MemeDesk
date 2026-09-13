import AppKit
import Combine
import Foundation
import OSLog

/// 更新中枢。
///
/// - 检查来源：**GitHub Releases**（见 `UpdateFeed`）
/// - 完整性：SHA-256，配了公钥再加 Ed25519 验签（见 `UpdateIntegrity`）
/// - 安装：App 退出后由 helper 原地覆盖（见 `UpdateInstaller`）
///
/// 这是**全项目唯一会联网**的地方，而且是可关的：
/// 关掉「自动检查更新」之后，就只剩手动点按钮才会发请求。
///
/// 全程写系统日志（subsystem `com.memedesk.app`，category `update`）。
/// 更新这种东西不出问题则已，一出问题就必须能查 —— 现场在真机上，只能靠日志：
///
///     log show --predicate 'subsystem == "com.memedesk.app"' --last 10m --info
@MainActor
final class UpdateService: ObservableObject {

    static let shared = UpdateService()

    /// `nonisolated`：日志要能在 `Task.detached` 里直接用，不然 Swift 6 模式下
    /// 会报"main actor-isolated 属性不能从 actor 外访问"。`Logger` 本身是 Sendable 的。
    private nonisolated static let log = Logger(subsystem: "com.memedesk.app", category: "update")

    enum Status: Equatable {
        case idle
        case checking
        /// 已经是最新，或仓库里还没有 Release。
        case upToDate
        case available(ReleaseInfo)
        case downloading(Double)
        /// 包已下载并校验通过，等着安装。
        case ready(ReleaseInfo)
        case installing
        /// 装不了（多半是没权限覆盖 App 所在的目录）。
        case blocked(ReleaseInfo)
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastChecked: Date?

    /// 菜单栏面板上的红点用它。
    var updateAvailable: Bool {
        switch status {
        case .available, .downloading, .ready, .blocked: return true
        default: return false
        }
    }

    /// 是否已经下好、可以直接装。
    var readyToInstall: ReleaseInfo? {
        if case .ready(let release) = status { return release }
        return nil
    }

    private let defaultsKey = "MemeDesk.lastUpdateCheck"
    private var timer: Timer?
    private var busy = false

    private init() {
        lastChecked = UserDefaults.standard.object(forKey: defaultsKey) as? Date
    }

    // MARK: - 配置（从 Info.plist 读，fork 也能改）

    private var repository: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "MemeDeskUpdateRepository") as? String
        return (value?.isEmpty == false) ? value : nil
    }

    private var publicKey: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "MemeDeskUpdatePublicKey") as? String
        return (value?.isEmpty == false) ? value : nil
    }

    var currentVersionString: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }

    private var currentVersion: SemanticVersion? { SemanticVersion(currentVersionString) }

    private var bundleIdentifier: String { Bundle.main.bundleIdentifier ?? "com.memedesk.app" }

    /// 正在运行的 App 本体 —— 要覆盖的就是它。
    private var destination: URL { Bundle.main.bundleURL }

    /// 下载 / 解压 / 日志都放缓存目录：不污染 App 包，也不出现在用户看得见的地方。
    private var workingDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("MemeDesk/Updates", isDirectory: true)
    }

    private func userAgent() -> String { UpdateFeed.userAgent(appVersion: currentVersionString) }

    var installLogURL: URL { UpdateInstaller.logURL(workingDirectory: workingDirectory) }

    // MARK: - 自动检查

    /// 启动时调一次。首次检查延后 10 秒，别跟启动时的解码抢 IO。
    func start() {
        guard let repository else {
            Self.log.notice("update service not started: Info.plist 里没有 MemeDeskUpdateRepository")
            return
        }
        guard timer == nil else { return }
        Self.log.notice("update service started; repository=\(repository, privacy: .public) current=\(self.currentVersionString, privacy: .public) first check in 10s")
        scheduleAutoCheck(after: 10)
    }

    private func scheduleAutoCheck(after delay: TimeInterval) {
        timer?.invalidate()
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            // 在**外层**就把弱引用解成强引用。
            // Timer 的 block 是 `@Sendable`，如果改到里面的 `Task` 里再 `guard let self`，
            // 就变成"在并发执行的代码里引用被捕获的 var"，CI 的编译器会直接报错
            // （本地 Swift 6.4 在 Swift 5 语言模式下不报，所以这条只有 CI 才发现得了）。
            guard let service = self else { return }
            Task { @MainActor in service.autoCheckFired(delay: delay) }
        }
        // 容差要**按延迟比例**给，不能一律 60 秒：
        // Timer 的 tolerance 允许系统把触发时刻往后推，10 秒的首查配上 60 秒容差
        // 意味着它可能拖到一分钟之后才跑。长周期那个 60 秒无所谓。
        t.tolerance = min(delay * 0.1, 60)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func autoCheckFired(delay: TimeInterval) {
        Self.log.debug("auto-check timer fired (delay \(Int(delay))s)")
        Task { @MainActor in
            if Stage.shared.preferences.autoCheckForUpdates {
                await checkForUpdates(userInitiated: false)
            } else {
                Self.log.notice("auto check is off; skipping")
            }
            scheduleAutoCheck(after: 24 * 60 * 60)
        }
    }

    // MARK: - 检查

    func checkForUpdates(userInitiated: Bool) async {
        guard let repository else {
            if userInitiated { status = .failed(L(.updateNoFeed)) }
            return
        }
        guard !busy else { return }
        busy = true
        defer { busy = false }

        Self.log.notice("checking \(repository, privacy: .public) — current \(self.currentVersionString, privacy: .public), manual=\(userInitiated, privacy: .public)")
        status = .checking
        // 「上次检查」记的是**尝试**时间，不是成功时间：失败也要记。
        // 否则一旦某次检查失败，设置页会永远停在「尚未检查过」，看起来像功能没跑。
        defer { markChecked() }
        do {
            let release = try await UpdateFeed.latestRelease(repository: repository,
                                                            appVersion: currentVersionString)

            guard let release else {
                Self.log.notice("仓库里还没有任何 Release")
                status = .upToDate
                return
            }
            guard let current = currentVersion, release.version > current else {
                Self.log.notice("up to date (latest=\(release.versionString, privacy: .public))")
                status = .upToDate
                return
            }
            // 用户主动点检查时，不再尊重「忽略此版本」
            if !userInitiated, release.versionString == Stage.shared.preferences.skippedVersion {
                Self.log.notice("\(release.versionString, privacy: .public) is skipped by the user")
                status = .upToDate
                return
            }
            // 确认对方确实比我们新之后，才轮到"有没有更新包"这个问题。
            // 比当前版本旧的 Release 有没有 zip 与我们无关 —— 先判版本就不会误报失败。
            guard release.archiveURL != nil else {
                Self.log.error("\(release.versionString, privacy: .public) 比当前版本新，但这个 Release 里没有 zip 资产")
                status = .failed(L(.updateNoArchive))
                return
            }

            Self.log.notice("update available: \(release.versionString, privacy: .public) archive=\(release.archiveName, privacy: .public) checksum=\(release.checksumURL != nil, privacy: .public) signature=\(release.signatureURL != nil, privacy: .public)")
            status = .available(release)
            if Stage.shared.preferences.autoInstallUpdates {
                await download(release, thenInstall: true)
            }
        } catch {
            let reason = message(for: error)
            Self.log.error("check failed: \(String(describing: error), privacy: .public) → \(reason, privacy: .public)")
            status = .failed(reason)
        }
    }

    private func markChecked() {
        let now = Date()
        lastChecked = now
        UserDefaults.standard.set(now, forKey: defaultsKey)
    }

    private func message(for error: Error) -> String {
        if let e = error as? UpdateFeedError {
            switch e {
            case .rateLimited: return L(.updateRateLimited)
            case .malformedResponse: return L(.updateBadResponse)
            case .badStatus(let code): return String(format: L(.updateHTTPError), code)
            }
        }
        if let e = error as? UpdateDownloadError {
            switch e {
            case .checksumMismatch: return L(.updateChecksumFailed)
            case .signatureInvalid: return L(.updateSignatureFailed)
            case .signatureUnavailable, .checksumUnavailable:
                return L(.updateVerificationUnavailable)
            case .archiveMissing: return L(.updateNoArchive)
            case .badStatus(let code): return String(format: L(.updateHTTPError), code)
            }
        }
        if let e = error as? UpdateInstallError {
            switch e {
            case .identityMismatch, .versionMismatch: return L(.updateWrongBundle)
            case .unarchiveFailed, .bundleNotFound: return L(.updateUnarchiveFailed)
            case .destinationNotWritable: return L(.updateNotWritable)
            case .helperFailed: return L(.updateInstallFailed)
            }
        }
        return (error as NSError).localizedDescription
    }

    // MARK: - 下载

    /// 下载进度回调（从下载器的并发上下文跳回主 actor）。
    private func reportDownloadProgress(_ fraction: Double) {
        guard case .downloading = status else { return }
        status = .downloading(fraction)
    }

    /// 下载并校验。`thenInstall` 为真时，装完直接进入安装流程。
    func download(_ release: ReleaseInfo, thenInstall: Bool) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }

        status = .downloading(0)
        Self.log.notice("downloading \(release.archiveName, privacy: .public) (\(release.archiveSize ?? 0) bytes)")
        do {
            let userAgent = self.userAgent()
            let key = publicKey
            let directory = workingDirectory
            let zip = try await UpdateDownloader.downloadVerified(
                release,
                into: directory,
                userAgent: userAgent,
                publicKeyBase64: key,
                progress: { [weak self] fraction in
                    // 同上：这个闭包也是 `@Sendable`，弱引用必须在外面解开。
                    guard let service = self else { return }
                    Task { @MainActor in service.reportDownloadProgress(fraction) }
                }
            )
            status = .ready(release)
            Self.log.notice("downloaded and verified → \(zip.path, privacy: .public)")
            if thenInstall {
                install(release: release, zipURL: zip)
            }
        } catch {
            let reason = message(for: error)
            Self.log.error("download failed: \(String(describing: error), privacy: .public) → \(reason, privacy: .public)")
            status = .failed(reason)
        }
    }

    // MARK: - 安装

    func install(release: ReleaseInfo, zipURL: URL? = nil) {
        let destination = self.destination
        guard UpdateInstaller.canReplace(destination: destination) else {
            Self.log.error("cannot replace \(destination.path, privacy: .public): 目录不可写")
            status = .blocked(release)
            return
        }

        let archive = zipURL ?? workingDirectory
            .appendingPathComponent("MemeDesk-\(release.versionString).zip")
        guard FileManager.default.fileExists(atPath: archive.path) else {
            // 还没下就先下，下完再装
            Task { await download(release, thenInstall: true) }
            return
        }

        status = .installing
        let identifier = bundleIdentifier
        let working = workingDirectory

        // 解压要等 ditto，是阻塞 IO，挪出主线程。
        Task.detached {
            do {
                let replacement = try UpdateInstaller.prepare(zipURL: archive,
                                                              in: working,
                                                              expectedBundleID: identifier,
                                                              expectedVersion: release.versionString)
                try UpdateInstaller.scheduleInstall(workingDirectory: working,
                                                    destination: destination,
                                                    replacement: replacement,
                                                    relaunch: true)
                Self.log.notice("installer scheduled for \(release.versionString, privacy: .public); quitting so the helper can swap the bundle")
                await MainActor.run {
                    // 先把存档落盘：helper 会等我们退出后立刻动手。
                    Stage.shared.saveNow()
                    // 兜底强退。helper 在门外等我们消失，一旦退出流程被什么卡住
                    // （AppKit 的退出流程是可以被卡住的），更新就会永远停在这一步 ——
                    // 对一个自更新器来说那是最糟的失败方式：用户以为在更新，其实什么也没发生。
                    // 用 GCD 而不是 Task：主 actor 此刻可能正忙，而 GCD 块在嵌套 runloop 里也能跑。
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exit(0) }
                    NSApp.terminate(nil)
                }
            } catch {
                Self.log.error("install failed: \(String(describing: error), privacy: .public)")
                await MainActor.run {
                    UpdateService.shared.status = .failed(UpdateService.shared.message(for: error))
                }
            }
        }
    }

    // MARK: - 兜底出口

    /// 在访达里显示已下好的包 —— 没权限自动替换时的退路。
    func revealDownload(in release: ReleaseInfo) {
        let zip = workingDirectory.appendingPathComponent("MemeDesk-\(release.versionString).zip")
        if FileManager.default.fileExists(atPath: zip.path) {
            NSWorkspace.shared.activateFileViewerSelecting([zip])
        } else {
            NSWorkspace.shared.open(release.pageURL)
        }
    }

    func openReleasePage(_ release: ReleaseInfo) {
        NSWorkspace.shared.open(release.pageURL)
    }

    /// 失败状态下手里没有 Release，直接开仓库的 releases/latest。
    func openLatestReleasePage() {
        guard let repository,
              let url = URL(string: "https://github.com/\(repository)/releases/latest") else { return }
        NSWorkspace.shared.open(url)
    }

    /// 上次安装失败时留下的日志。
    func revealInstallLog() {
        let log = installLogURL
        if FileManager.default.fileExists(atPath: log.path) {
            NSWorkspace.shared.activateFileViewerSelecting([log])
        }
    }

    // MARK: - 忽略此版本

    func skip(_ release: ReleaseInfo) {
        Stage.shared.preferences.skippedVersion = release.versionString
        status = .upToDate
    }

    func clearSkippedVersion() {
        Stage.shared.preferences.skippedVersion = ""
    }
}
