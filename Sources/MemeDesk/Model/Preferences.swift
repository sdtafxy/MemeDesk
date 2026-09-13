import AppKit
import Foundation

/// 全局偏好。变更即落盘（带去抖，拖拽窗口时不会疯狂写 SSD）。
struct Preferences: Codable, Equatable {
    /// 所有运动行为的统一速度系数，0 = 全场禁用运动。
    var motionSpeed: Double = 1
    /// 全屏应用在前台时自动隐藏（省电，也不挡电影）。
    var hideOnFullscreen: Bool = true
    /// 遮挡即暂停：窗口被别的窗口完全盖住时停止解码。
    var pauseWhenOccluded: Bool = true
    /// 使用电池供电时暂停播放。
    var pauseOnBattery: Bool = false
    /// GIF 解码目标像素上限（单边）。超过会下采样，这是低占用的主开关之一。
    var decodePixelLimit: Int = 320
    /// 新增表情包的默认边长（点）。
    var defaultSize: Double = 220
    /// 退出后下次启动自动恢复上一次的桌面布局。
    var restoreSession: Bool = true
    /// 开机自启（封装 SMAppService）。
    var launchAtLogin: Bool = false
    /// 拖拽时是否吸边到 8pt 网格。
    var snapToEdges: Bool = true
    /// 视频音轨默认静音 —— 桌面常驻的东西出声通常很吵。
    var videosMutedByDefault: Bool = true

    // MARK: 更新

    /// 启动后、以及每隔一天自动检查一次新版本。关掉之后只能手动点「检查更新」。
    var autoCheckForUpdates: Bool = true
    /// 发现新版本后自动下载并安装。默认关 —— 重启这件事应该由用户自己决定。
    var autoInstallUpdates: Bool = false
    /// 用户点过「忽略此版本」的版本号；空串表示没有忽略任何版本。
    var skippedVersion: String = ""

    init() {}

    static let `default` = Preferences()

    // MARK: - 容错解码
    //
    // 必须逐字段 `decodeIfPresent` 风格地解，不能用合成的实现：
    // desk.json 是**旧版本**写下的，缺任何一个新增字段都会让整份解码失败，
    // 而 `Stage.load()` 是 `try?` —— 那样会静默清空用户的整个桌面布局。
    // 新增字段时**不要动这个初始化器**，否则等于给老用户埋雷。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let d = Preferences()

        motionSpeed = (try? c.decode(Double.self, forKey: .motionSpeed)) ?? d.motionSpeed
        hideOnFullscreen = (try? c.decode(Bool.self, forKey: .hideOnFullscreen)) ?? d.hideOnFullscreen
        pauseWhenOccluded = (try? c.decode(Bool.self, forKey: .pauseWhenOccluded)) ?? d.pauseWhenOccluded
        pauseOnBattery = (try? c.decode(Bool.self, forKey: .pauseOnBattery)) ?? d.pauseOnBattery
        decodePixelLimit = (try? c.decode(Int.self, forKey: .decodePixelLimit)) ?? d.decodePixelLimit
        defaultSize = (try? c.decode(Double.self, forKey: .defaultSize)) ?? d.defaultSize
        restoreSession = (try? c.decode(Bool.self, forKey: .restoreSession)) ?? d.restoreSession
        launchAtLogin = (try? c.decode(Bool.self, forKey: .launchAtLogin)) ?? d.launchAtLogin
        snapToEdges = (try? c.decode(Bool.self, forKey: .snapToEdges)) ?? d.snapToEdges
        videosMutedByDefault = (try? c.decode(Bool.self, forKey: .videosMutedByDefault))
            ?? d.videosMutedByDefault

        autoCheckForUpdates = (try? c.decode(Bool.self, forKey: .autoCheckForUpdates))
            ?? d.autoCheckForUpdates
        autoInstallUpdates = (try? c.decode(Bool.self, forKey: .autoInstallUpdates))
            ?? d.autoInstallUpdates
        skippedVersion = (try? c.decode(String.self, forKey: .skippedVersion)) ?? d.skippedVersion
    }

    private enum Keys: String, CodingKey {
        case motionSpeed, hideOnFullscreen, pauseWhenOccluded, pauseOnBattery
        case decodePixelLimit, defaultSize, restoreSession, launchAtLogin, snapToEdges
        case videosMutedByDefault
        case autoCheckForUpdates, autoInstallUpdates, skippedVersion
    }
}
